import XCTest
import SwiftData
@testable import PersonalStrengthCoach

// MARK: - Group A: pure RoutineEngine.buildWorkout tests (no ModelContainer)
//
// Mirrors TrainingEngineTests.swift's pattern of instantiating @Model classes directly
// as plain value holders, since RoutineEngine is a stateless builder with no ModelContext
// side effects.

final class RoutineEngineBuildWorkoutTests: XCTestCase {
    func testBuildWorkoutOrdersExercisesByExplicitOrderNotInsertionOrder() {
        // Appended out of `order` sequence (third, first, second) to prove the builder
        // sorts by the explicit `order` field rather than trusting relationship array order.
        let third = RoutineExercise(exercise: "Overhead Press", primaryMuscle: .frontDelts, order: 2, targetSets: 1, targetReps: 8)
        let first = RoutineExercise(exercise: "Bench Press", primaryMuscle: .chest, order: 0, targetSets: 1, targetReps: 8)
        let second = RoutineExercise(exercise: "Incline Press", primaryMuscle: .chest, order: 1, targetSets: 1, targetReps: 8)
        let routine = Routine(name: "Push Day", exercises: [third, first, second])

        let workout = RoutineEngine.buildWorkout(from: routine)

        XCTAssertEqual(workout.sets.map(\.exercise), ["Bench Press", "Incline Press", "Overhead Press"])
    }

    func testBuildWorkoutGeneratesOneSetPerTargetSetWithSequentialSetNumbers() {
        let exercise = RoutineExercise(exercise: "Squat", primaryMuscle: .quads, order: 0, targetSets: 3, targetReps: 5)
        let routine = Routine(name: "Leg Day", exercises: [exercise])

        let workout = RoutineEngine.buildWorkout(from: routine)

        XCTAssertEqual(workout.sets.count, 3)
        XCTAssertEqual(workout.sets.map(\.setNumber), [1, 2, 3])
    }

    func testBuildWorkoutUsesTargetWeightWhenPresent() {
        let exercise = RoutineExercise(exercise: "Bench Press", primaryMuscle: .chest, order: 0, targetSets: 2, targetReps: 5, targetWeight: 100)
        let routine = Routine(name: "Push Day", exercises: [exercise])

        let workout = RoutineEngine.buildWorkout(from: routine)

        XCTAssertEqual(workout.sets.map(\.weight), [100, 100])
    }

    func testBuildWorkoutDefaultsWeightToZeroWhenTargetWeightIsNil() {
        let exercise = RoutineExercise(exercise: "Pull Up", primaryMuscle: .lats, order: 0, targetSets: 2, targetReps: 8)
        let routine = Routine(name: "Pull Day", exercises: [exercise])

        let workout = RoutineEngine.buildWorkout(from: routine)

        XCTAssertEqual(workout.sets.map(\.weight), [0, 0])
    }

    func testBuildWorkoutCopiesTargetRepsIntoEachGeneratedSet() {
        let exercise = RoutineExercise(exercise: "Row", primaryMuscle: .upperBack, order: 0, targetSets: 3, targetReps: 12)
        let routine = Routine(name: "Pull Day", exercises: [exercise])

        let workout = RoutineEngine.buildWorkout(from: routine)

        XCTAssertEqual(workout.sets.map(\.reps), [12, 12, 12])
    }

    func testBuildWorkoutHandlesEmptyRoutineByReturningWorkoutWithNoSets() {
        let routine = Routine(name: "Rest Day")

        let workout = RoutineEngine.buildWorkout(from: routine)

        XCTAssertTrue(workout.sets.isEmpty)
        XCTAssertEqual(workout.title, "Rest Day")
    }

    func testBuildWorkoutPreservesDuplicateExerciseNamesAsIndependentEntries() {
        let firstBench = RoutineExercise(exercise: "Bench Press", primaryMuscle: .chest, order: 0, targetSets: 2, targetReps: 8)
        let secondBench = RoutineExercise(exercise: "Bench Press", primaryMuscle: .chest, order: 1, targetSets: 3, targetReps: 5)
        let routine = Routine(name: "Push Day", exercises: [firstBench, secondBench])

        let workout = RoutineEngine.buildWorkout(from: routine)

        XCTAssertEqual(workout.sets.count, 5)
        let firstEntrySets = Array(workout.sets.prefix(2))
        let secondEntrySets = Array(workout.sets.suffix(3))
        // Each routine exercise restarts setNumber at 1, matching WorkoutLoggerView.save()'s
        // per-exercise numbering rather than SeedData's continuous numbering.
        XCTAssertEqual(firstEntrySets.map(\.setNumber), [1, 2])
        XCTAssertEqual(secondEntrySets.map(\.setNumber), [1, 2, 3])
        XCTAssertTrue(firstEntrySets.allSatisfy { $0.exercise == "Bench Press" })
        XCTAssertTrue(secondEntrySets.allSatisfy { $0.exercise == "Bench Press" })
    }

    func testBuildWorkoutSetsWorkoutTitleFromRoutineName() {
        let date = Date(timeIntervalSince1970: 500_000)
        let routine = Routine(name: "Upper Body Strength")

        let workout = RoutineEngine.buildWorkout(from: routine, date: date)

        XCTAssertEqual(workout.title, "Upper Body Strength")
        XCTAssertEqual(workout.date, date)
    }

    func testBuildWorkoutNormalizesExerciseNameConsistentlyWithExerciseSet() {
        // ExerciseCatalog.normalize's alias table (Models.swift) maps the lowercased key
        // "barbell bench press" to "Bench Press" — confirmed by reading the table directly
        // rather than assuming an alias exists.
        let exercise = RoutineExercise(exercise: "Barbell Bench Press", primaryMuscle: .chest, order: 0, targetSets: 1, targetReps: 5)
        XCTAssertEqual(exercise.normalizedExercise, ExerciseCatalog.normalize("Barbell Bench Press"))
        XCTAssertEqual(exercise.normalizedExercise, "Bench Press")

        let routine = Routine(name: "Push Day", exercises: [exercise])
        let workout = RoutineEngine.buildWorkout(from: routine)

        XCTAssertEqual(workout.sets.first?.normalizedExercise, "Bench Press")
    }

    func testBuildWorkoutClampsNonPositiveTargetSetsToAtLeastOneSet() {
        // Non-positive targetSets clamps to exactly one generated set, so a routine exercise
        // never silently vanishes from the built workout.
        let zeroSets = RoutineExercise(exercise: "Bench Press", primaryMuscle: .chest, order: 0, targetSets: 0, targetReps: 5)
        let negativeSets = RoutineExercise(exercise: "Squat", primaryMuscle: .quads, order: 1, targetSets: -3, targetReps: 5)
        let routine = Routine(name: "Push Day", exercises: [zeroSets, negativeSets])

        let workout = RoutineEngine.buildWorkout(from: routine)

        XCTAssertEqual(workout.sets.count, 2)
        XCTAssertEqual(workout.sets.map(\.setNumber), [1, 1])
        XCTAssertEqual(workout.sets.map(\.exercise), ["Bench Press", "Squat"])
    }

    func testBuildWorkoutLinksGeneratedSetsBackToTheWorkout() {
        let exercise = RoutineExercise(exercise: "Squat", primaryMuscle: .quads, order: 0, targetSets: 2, targetReps: 5)
        let routine = Routine(name: "Leg Day", exercises: [exercise])

        let workout = RoutineEngine.buildWorkout(from: routine)

        XCTAssertEqual(workout.sets.count, 2)
        XCTAssertTrue(workout.sets.allSatisfy { $0.workout === workout })
    }
}

// MARK: - Group B: SwiftData in-memory container tests
//
// New harness: nothing in the codebase constructs a ModelContainer in tests yet, so this
// establishes a minimal, per-test in-memory container built from AppSchemaV2 + AppMigrationPlan.

final class RoutinePersistenceTests: XCTestCase {
    private func makeInMemoryContainer() throws -> ModelContainer {
        try ModelContainer(
            for: Schema(AppSchemaV2.models),
            migrationPlan: AppMigrationPlan.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    func testAppSchemaV2ContainerBuildsWithMigrationPlan() throws {
        // This is the project's first non-empty migration stage: the migration plan must
        // resolve and a container must construct without throwing.
        let container = try makeInMemoryContainer()

        XCTAssertNotNil(container)
    }

    func testAppSchemaV2IncludesRoutineAndRoutineExerciseModels() {
        let v2Names = Set(AppSchemaV2.models.map { String(describing: $0) })
        XCTAssertTrue(v2Names.contains(String(describing: Routine.self)))
        XCTAssertTrue(v2Names.contains(String(describing: RoutineExercise.self)))

        // AppSchemaV1 is the historical anchor and must not be edited to include the new models.
        let v1Names = Set(AppSchemaV1.models.map { String(describing: $0) })
        XCTAssertFalse(v1Names.contains(String(describing: Routine.self)))
        XCTAssertFalse(v1Names.contains(String(describing: RoutineExercise.self)))
    }

    func testDeletingRoutineCascadesToItsRoutineExercises() throws {
        let container = try makeInMemoryContainer()
        let context = ModelContext(container)

        let routine = Routine(name: "Push Day")
        let exercise = RoutineExercise(exercise: "Bench Press", primaryMuscle: .chest, order: 0, targetSets: 3, targetReps: 8)
        exercise.routine = routine
        routine.exercises.append(exercise)
        context.insert(routine)
        try context.save()

        context.delete(routine)
        try context.save()

        let remaining = try context.fetch(FetchDescriptor<RoutineExercise>())
        XCTAssertTrue(remaining.isEmpty)
    }

    func testDeletingRoutineDoesNotAffectLoggedWorkouts() throws {
        let container = try makeInMemoryContainer()
        let context = ModelContext(container)

        let routine = Routine(name: "Push Day")
        let routineExercise = RoutineExercise(exercise: "Bench Press", primaryMuscle: .chest, order: 0, targetSets: 3, targetReps: 8)
        routineExercise.routine = routine
        routine.exercises.append(routineExercise)

        let workout = Workout(title: "Logged Session", durationMinutes: 45)
        let set = ExerciseSet(exercise: "Squat", weight: 100, reps: 5, setNumber: 1, primaryMuscle: .quads)
        set.workout = workout
        workout.sets.append(set)

        context.insert(routine)
        context.insert(workout)
        try context.save()

        context.delete(routine)
        try context.save()

        let workouts = try context.fetch(FetchDescriptor<Workout>())
        XCTAssertEqual(workouts.count, 1)
        XCTAssertEqual(workouts.first?.sets.count, 1)
    }

    func testRoutineExercisesPersistAndReloadInExplicitOrder() throws {
        let container = try makeInMemoryContainer()
        let context = ModelContext(container)

        let routine = Routine(name: "Push Day")
        let third = RoutineExercise(exercise: "Overhead Press", primaryMuscle: .frontDelts, order: 2, targetSets: 3, targetReps: 8)
        let first = RoutineExercise(exercise: "Bench Press", primaryMuscle: .chest, order: 0, targetSets: 3, targetReps: 8)
        let second = RoutineExercise(exercise: "Incline Press", primaryMuscle: .chest, order: 1, targetSets: 3, targetReps: 8)
        for exercise in [third, first, second] {
            exercise.routine = routine
            routine.exercises.append(exercise)
        }
        context.insert(routine)
        try context.save()

        let descriptor = FetchDescriptor<RoutineExercise>(sortBy: [SortDescriptor(\.order)])
        let reloaded = try context.fetch(descriptor)

        XCTAssertEqual(reloaded.map(\.exercise), ["Bench Press", "Incline Press", "Overhead Press"])
    }
}
