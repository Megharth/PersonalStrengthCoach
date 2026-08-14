import XCTest
import SwiftData
@testable import PersonalStrengthCoach

// MARK: - Group A: pure editor logic (no ModelContainer)

final class WorkoutEditorLogicTests: XCTestCase {
    private func makeSet(_ exercise: String, weight: Double, reps: Int, setNumber: Int, muscle: MuscleGroup = .chest) -> ExerciseSet {
        ExerciseSet(exercise: exercise, weight: weight, reps: reps, setNumber: setNumber, primaryMuscle: muscle)
    }

    private func makeWorkout(sets: [ExerciseSet]) -> Workout {
        let workout = Workout(title: "Session", durationMinutes: 45)
        for set in sets { set.workout = workout }
        workout.sets = sets
        return workout
    }

    func testRemovedSetIDsIsEmptyWhenNothingWasDropped() {
        let ids = Set([makeSet("Bench Press", weight: 60, reps: 8, setNumber: 1)].map(ObjectIdentifier.init))
        XCTAssertTrue(WorkoutEditorLogic.removedSetIDs(original: ids, remaining: ids).isEmpty)
    }

    func testRemovedSetIDsReturnsTheDroppedSets() {
        let kept = makeSet("Bench Press", weight: 60, reps: 8, setNumber: 1)
        let dropped = makeSet("Bench Press", weight: 60, reps: 8, setNumber: 2)
        let original = Set([kept, dropped].map(ObjectIdentifier.init))
        let remaining = Set([kept].map(ObjectIdentifier.init))

        let removed = WorkoutEditorLogic.removedSetIDs(original: original, remaining: remaining)

        XCTAssertEqual(removed, Set([ObjectIdentifier(dropped)]))
    }

    func testRemovedSetIDsHandlesDraftShrinkingToEmpty() {
        let a = makeSet("Bench Press", weight: 60, reps: 8, setNumber: 1)
        let b = makeSet("Bench Press", weight: 60, reps: 8, setNumber: 2)
        let original = Set([a, b].map(ObjectIdentifier.init))

        XCTAssertEqual(WorkoutEditorLogic.removedSetIDs(original: original, remaining: []), original)
    }

    func testEditableExercisesGroupsByRawExerciseNameNotNormalizedName() {
        // "Barbell Bench Press" normalizes to "Bench Press"; the draft must keep the
        // user's raw entry, not silently rename it.
        let workout = makeWorkout(sets: [makeSet("Barbell Bench Press", weight: 100, reps: 5, setNumber: 1)])

        let drafts = LoggedExercise.draftExercises(from: workout)

        XCTAssertEqual(drafts.map(\.name), ["Barbell Bench Press"])
    }

    func testEditableExercisesOrdersSetsBySetNumberFromUnorderedInput() {
        let workout = makeWorkout(sets: [
            makeSet("Bench Press", weight: 60, reps: 8, setNumber: 3),
            makeSet("Bench Press", weight: 60, reps: 8, setNumber: 1),
            makeSet("Bench Press", weight: 60, reps: 8, setNumber: 2)
        ])

        let drafts = LoggedExercise.draftExercises(from: workout)

        XCTAssertEqual(drafts.count, 1)
        XCTAssertEqual(drafts[0].sets.map { $0.existingModel?.setNumber }, [1, 2, 3])
    }

    func testEditableExercisesWiresEachDraftSetToItsPersistedModel() {
        let set = makeSet("Bench Press", weight: 80, reps: 6, setNumber: 1)
        let workout = makeWorkout(sets: [set])

        let drafts = LoggedExercise.draftExercises(from: workout)

        XCTAssertTrue(drafts[0].sets[0].existingModel === set)
        XCTAssertEqual(drafts[0].sets[0].weight, 80)
        XCTAssertEqual(drafts[0].sets[0].reps, 6)
    }

    func testEditableExercisesHandlesContinuousSetNumberingAcrossExercises() {
        // Seed/Strong-imported workouts number sets continuously across the whole
        // session rather than restarting per exercise; grouping must still yield
        // two blocks with the right sets.
        let workout = makeWorkout(sets: [
            makeSet("Bench Press", weight: 100, reps: 5, setNumber: 1),
            makeSet("Bench Press", weight: 100, reps: 5, setNumber: 2),
            makeSet("Squat", weight: 140, reps: 5, setNumber: 3, muscle: .quads),
            makeSet("Squat", weight: 140, reps: 5, setNumber: 4, muscle: .quads)
        ])

        let drafts = LoggedExercise.draftExercises(from: workout)

        XCTAssertEqual(drafts.map(\.name), ["Bench Press", "Squat"])
        XCTAssertEqual(drafts.map { $0.sets.count }, [2, 2])
    }

    func testEditableExercisesMergesDuplicateSameNameBlocks() {
        // Documented lossy behaviour: two separate "Bench Press" blocks collapse into
        // one, because ExerciseSet stores no intra-workout ordering to split them.
        let workout = makeWorkout(sets: [
            makeSet("Bench Press", weight: 100, reps: 5, setNumber: 1),
            makeSet("Bench Press", weight: 100, reps: 5, setNumber: 2),
            makeSet("Bench Press", weight: 60, reps: 12, setNumber: 1),
            makeSet("Bench Press", weight: 60, reps: 12, setNumber: 2),
            makeSet("Bench Press", weight: 60, reps: 12, setNumber: 3)
        ])

        let drafts = LoggedExercise.draftExercises(from: workout)

        XCTAssertEqual(drafts.count, 1)
        XCTAssertEqual(drafts[0].sets.count, 5)
    }

    func testEditableExercisesPreservesPrimaryMuscleFromStoredSets() {
        let workout = makeWorkout(sets: [makeSet("Squat", weight: 140, reps: 5, setNumber: 1, muscle: .quads)])

        let drafts = LoggedExercise.draftExercises(from: workout)

        XCTAssertEqual(drafts[0].primaryMuscle, .quads)
    }

    func testEditableExercisesReturnsNoExercisesForAWorkoutWithNoSets() {
        XCTAssertTrue(LoggedExercise.draftExercises(from: makeWorkout(sets: [])).isEmpty)
    }
}

// MARK: - Group B: SwiftData in-memory container persistence

final class WorkoutEditingPersistenceTests: XCTestCase {
    private func makeInMemoryContainer() throws -> ModelContainer {
        try ModelContainer(
            for: Schema(AppSchemaV3.models),
            migrationPlan: AppMigrationPlan.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    private func makeWorkout(title: String, date: Date, sets: [ExerciseSet], calories: Int = 0, notes: String = "", durationMinutes: Int = 45) -> Workout {
        let workout = Workout(date: date, title: title, durationMinutes: durationMinutes, calories: calories, notes: notes)
        for set in sets { set.workout = workout }
        workout.sets = sets
        return workout
    }

    func testDeletingWorkoutCascadesToItsExerciseSets() throws {
        let container = try makeInMemoryContainer()
        let context = ModelContext(container)

        let workout = makeWorkout(title: "Push", date: Date(timeIntervalSince1970: 1_000_000), sets: [
            ExerciseSet(exercise: "Bench Press", weight: 100, reps: 5, setNumber: 1, primaryMuscle: .chest),
            ExerciseSet(exercise: "Bench Press", weight: 100, reps: 5, setNumber: 2, primaryMuscle: .chest),
            ExerciseSet(exercise: "Bench Press", weight: 100, reps: 5, setNumber: 3, primaryMuscle: .chest)
        ])
        context.insert(workout)
        try context.save()

        context.delete(workout)
        try context.save()

        XCTAssertTrue(try context.fetch(FetchDescriptor<ExerciseSet>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<Workout>()).isEmpty)
    }

    func testDeletingWorkoutDoesNotAffectOtherWorkoutsSets() throws {
        let container = try makeInMemoryContainer()
        let context = ModelContext(container)

        let doomed = makeWorkout(title: "Push", date: Date(timeIntervalSince1970: 1_000_000), sets: [
            ExerciseSet(exercise: "Bench Press", weight: 100, reps: 5, setNumber: 1, primaryMuscle: .chest)
        ])
        let survivor = makeWorkout(title: "Legs", date: Date(timeIntervalSince1970: 2_000_000), sets: [
            ExerciseSet(exercise: "Squat", weight: 140, reps: 5, setNumber: 1, primaryMuscle: .quads),
            ExerciseSet(exercise: "Squat", weight: 140, reps: 5, setNumber: 2, primaryMuscle: .quads)
        ])
        context.insert(doomed)
        context.insert(survivor)
        try context.save()

        context.delete(doomed)
        try context.save()

        let workouts = try context.fetch(FetchDescriptor<Workout>())
        XCTAssertEqual(workouts.count, 1)
        XCTAssertEqual(workouts.first?.sets.count, 2)
        XCTAssertEqual(try context.fetch(FetchDescriptor<ExerciseSet>()).count, 2)
    }

    func testDeletingPRSettingWorkoutPromotesNextBestLiftToPR() throws {
        let container = try makeInMemoryContainer()
        let context = ModelContext(container)

        let base = makeWorkout(title: "A", date: Date(timeIntervalSince1970: 1_000_000), sets: [
            ExerciseSet(exercise: "Deadlift", weight: 100, reps: 5, setNumber: 1, primaryMuscle: .hamstrings)
        ])
        let peak = makeWorkout(title: "B", date: Date(timeIntervalSince1970: 2_000_000), sets: [
            ExerciseSet(exercise: "Deadlift", weight: 120, reps: 5, setNumber: 1, primaryMuscle: .hamstrings)
        ])
        let middling = makeWorkout(title: "C", date: Date(timeIntervalSince1970: 3_000_000), sets: [
            ExerciseSet(exercise: "Deadlift", weight: 110, reps: 5, setNumber: 1, primaryMuscle: .hamstrings)
        ])
        for workout in [base, peak, middling] { context.insert(workout) }
        try context.save()

        // With the 120 kg session present, the 110 kg session is not a PR.
        XCTAssertFalse(PerformanceEngine.personalRecords(in: middling, history: [base, peak, middling]).contains("Deadlift estimated 1RM"))

        context.delete(peak)
        try context.save()

        let remaining = try context.fetch(FetchDescriptor<Workout>())
        let reloadedMiddling = remaining.first { $0.title == "C" }!
        XCTAssertTrue(PerformanceEngine.personalRecords(in: reloadedMiddling, history: remaining).contains("Deadlift estimated 1RM"))
    }

    func testEditingSetWeightChangesWorkoutVolumeAndEstimated1RM() throws {
        let container = try makeInMemoryContainer()
        let context = ModelContext(container)

        let set = ExerciseSet(exercise: "Bench Press", weight: 100, reps: 5, setNumber: 1, primaryMuscle: .chest)
        let workout = makeWorkout(title: "Push", date: Date(timeIntervalSince1970: 1_000_000), sets: [set])
        context.insert(workout)
        try context.save()

        XCTAssertEqual(workout.volume, 500, accuracy: 0.001)
        let before = PerformanceEngine.estimated1RM(for: "Bench Press", sets: [set])

        set.weight = 120
        try context.save()

        let reloaded = try context.fetch(FetchDescriptor<Workout>()).first!
        XCTAssertEqual(reloaded.volume, 600, accuracy: 0.001)
        XCTAssertGreaterThan(PerformanceEngine.estimated1RM(for: "Bench Press", sets: reloaded.sets), before)
    }

    func testEditingDownATypoedHeavySetRemovesTheBogusPR() throws {
        let container = try makeInMemoryContainer()
        let context = ModelContext(container)

        // 400 kg baseline lets a 500 kg typo slip past the 1.4x PR sanity guard.
        let base = makeWorkout(title: "A", date: Date(timeIntervalSince1970: 1_000_000), sets: [
            ExerciseSet(exercise: "Deadlift", weight: 400, reps: 1, setNumber: 1, primaryMuscle: .hamstrings)
        ])
        let typoSet = ExerciseSet(exercise: "Deadlift", weight: 500, reps: 1, setNumber: 1, primaryMuscle: .hamstrings)
        let typo = makeWorkout(title: "B", date: Date(timeIntervalSince1970: 2_000_000), sets: [typoSet])
        context.insert(base)
        context.insert(typo)
        try context.save()

        XCTAssertTrue(PerformanceEngine.personalRecords(in: typo, history: [base, typo]).contains("Deadlift estimated 1RM"))

        typoSet.weight = 50
        try context.save()

        let workouts = try context.fetch(FetchDescriptor<Workout>())
        let reloadedTypo = workouts.first { $0.title == "B" }!
        XCTAssertFalse(PerformanceEngine.personalRecords(in: reloadedTypo, history: workouts).contains("Deadlift estimated 1RM"))
    }

    func testEditingAWorkoutPreservesDurationCaloriesAndNotes() throws {
        // Regression guard against a future "rebuild the Workout" refactor of save():
        // reusing the existing model must leave calories/notes/duration intact.
        let container = try makeInMemoryContainer()
        let context = ModelContext(container)

        let workout = makeWorkout(
            title: "Imported", date: Date(timeIntervalSince1970: 1_000_000),
            sets: [ExerciseSet(exercise: "Bench Press", weight: 100, reps: 5, setNumber: 1, primaryMuscle: .chest)],
            calories: 410, notes: "felt strong", durationMinutes: 68
        )
        context.insert(workout)
        try context.save()

        // An edit that changes title/date and a set weight, reusing the same instance.
        workout.title = "Renamed"
        workout.date = Date(timeIntervalSince1970: 1_500_000)
        workout.sets.first?.weight = 105
        try context.save()

        let reloaded = try context.fetch(FetchDescriptor<Workout>()).first!
        XCTAssertEqual(reloaded.calories, 410)
        XCTAssertEqual(reloaded.notes, "felt strong")
        XCTAssertEqual(reloaded.durationMinutes, 68)
        XCTAssertEqual(reloaded.title, "Renamed")
    }
}
