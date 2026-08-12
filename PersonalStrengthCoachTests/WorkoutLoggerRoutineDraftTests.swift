import XCTest
@testable import PersonalStrengthCoach

final class WorkoutLoggerRoutineDraftTests: XCTestCase {
    func testDraftExercisesOrdersByExplicitOrderNotInsertionOrder() {
        let third = RoutineExercise(exercise: "Overhead Press", primaryMuscle: .frontDelts, order: 2, targetSets: 1, targetReps: 8)
        let first = RoutineExercise(exercise: "Bench Press", primaryMuscle: .chest, order: 0, targetSets: 1, targetReps: 8)
        let second = RoutineExercise(exercise: "Incline Press", primaryMuscle: .chest, order: 1, targetSets: 1, targetReps: 8)
        let routine = Routine(name: "Push Day", exercises: [third, first, second])

        let drafts = LoggedExercise.draftExercises(from: routine)

        XCTAssertEqual(drafts.map(\.name), ["Bench Press", "Incline Press", "Overhead Press"])
    }

    func testDraftExercisesGeneratesOneEditableSetPerTargetSet() {
        let exercise = RoutineExercise(exercise: "Squat", primaryMuscle: .quads, order: 0, targetSets: 3, targetReps: 5)
        let routine = Routine(name: "Leg Day", exercises: [exercise])

        let drafts = LoggedExercise.draftExercises(from: routine)

        XCTAssertEqual(drafts.first?.sets.count, 3)
    }

    func testDraftExercisesPrefillsWeightFromTargetWeightWhenPresent() {
        let exercise = RoutineExercise(exercise: "Bench Press", primaryMuscle: .chest, order: 0, targetSets: 2, targetReps: 5, targetWeight: 100)
        let routine = Routine(name: "Push Day", exercises: [exercise])

        let drafts = LoggedExercise.draftExercises(from: routine)

        XCTAssertEqual(drafts.first?.sets.map(\.weight), [100, 100])
    }

    func testDraftExercisesDefaultsWeightToZeroWhenTargetWeightIsNil() {
        let exercise = RoutineExercise(exercise: "Pull Up", primaryMuscle: .lats, order: 0, targetSets: 2, targetReps: 8)
        let routine = Routine(name: "Pull Day", exercises: [exercise])

        let drafts = LoggedExercise.draftExercises(from: routine)

        XCTAssertEqual(drafts.first?.sets.map(\.weight), [0, 0])
    }

    func testDraftExercisesPrefillsRepsFromTargetReps() {
        let exercise = RoutineExercise(exercise: "Row", primaryMuscle: .upperBack, order: 0, targetSets: 3, targetReps: 12)
        let routine = Routine(name: "Pull Day", exercises: [exercise])

        let drafts = LoggedExercise.draftExercises(from: routine)

        XCTAssertEqual(drafts.first?.sets.map(\.reps), [12, 12, 12])
    }

    func testDraftExercisesHandlesEmptyRoutineByReturningNoExercises() {
        let routine = Routine(name: "Rest Day")

        let drafts = LoggedExercise.draftExercises(from: routine)

        XCTAssertTrue(drafts.isEmpty)
    }

    func testDraftExercisesPreservesDuplicateExerciseNamesAsIndependentEntries() {
        let firstBench = RoutineExercise(exercise: "Bench Press", primaryMuscle: .chest, order: 0, targetSets: 2, targetReps: 8)
        let secondBench = RoutineExercise(exercise: "Bench Press", primaryMuscle: .chest, order: 1, targetSets: 3, targetReps: 5)
        let routine = Routine(name: "Push Day", exercises: [firstBench, secondBench])

        let drafts = LoggedExercise.draftExercises(from: routine)

        XCTAssertEqual(drafts.count, 2)
        XCTAssertEqual(drafts.map(\.name), ["Bench Press", "Bench Press"])
        XCTAssertEqual(drafts[0].sets.count, 2)
        XCTAssertEqual(drafts[1].sets.count, 3)
        XCTAssertEqual(drafts[0].sets.map(\.reps), [8, 8])
        XCTAssertEqual(drafts[1].sets.map(\.reps), [5, 5, 5])
    }

    func testDraftExercisesClampsNonPositiveTargetSetsToAtLeastOneSet() {
        let zeroSets = RoutineExercise(exercise: "Bench Press", primaryMuscle: .chest, order: 0, targetSets: 0, targetReps: 5)
        let negativeSets = RoutineExercise(exercise: "Squat", primaryMuscle: .quads, order: 1, targetSets: -3, targetReps: 5)
        let routine = Routine(name: "Push Day", exercises: [zeroSets, negativeSets])

        let drafts = LoggedExercise.draftExercises(from: routine)

        XCTAssertEqual(drafts.map { $0.sets.count }, [1, 1])
    }

    func testDraftExercisesCopiesPrimaryMuscleFromRoutineExercise() {
        let exercise = RoutineExercise(exercise: "Overhead Press", primaryMuscle: .frontDelts, order: 0, targetSets: 1, targetReps: 8)
        let routine = Routine(name: "Push Day", exercises: [exercise])

        let drafts = LoggedExercise.draftExercises(from: routine)

        XCTAssertEqual(drafts.first?.primaryMuscle, .frontDelts)
    }

    func testDraftExercisesGivesEachPrefilledSetADistinctIdentity() {
        let exercise = RoutineExercise(exercise: "Bench Press", primaryMuscle: .chest, order: 0, targetSets: 4, targetReps: 8)
        let routine = Routine(name: "Push Day", exercises: [exercise])

        let drafts = LoggedExercise.draftExercises(from: routine)
        let ids = drafts.first?.sets.map(\.id) ?? []

        XCTAssertEqual(Set(ids).count, ids.count)
    }
}
