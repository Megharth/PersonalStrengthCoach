import XCTest
@testable import PersonalStrengthCoach

final class RoutineEditorLogicTests: XCTestCase {
    func testRemovedExerciseIDsIsEmptyWhenNoRowsWereDropped() {
        let first = RoutineExercise(exercise: "Bench Press", primaryMuscle: .chest, order: 0, targetSets: 3, targetReps: 8)
        let second = RoutineExercise(exercise: "Squat", primaryMuscle: .quads, order: 1, targetSets: 3, targetReps: 5)
        let original = Set([ObjectIdentifier(first), ObjectIdentifier(second)])

        let removed = RoutineEditorLogic.removedExerciseIDs(original: original, remaining: original)

        XCTAssertTrue(removed.isEmpty)
    }

    func testRemovedExerciseIDsIsEmptyAfterPureReorderWithNoDeletes() {
        let first = RoutineExercise(exercise: "Bench Press", primaryMuscle: .chest, order: 0, targetSets: 3, targetReps: 8)
        let second = RoutineExercise(exercise: "Squat", primaryMuscle: .quads, order: 1, targetSets: 3, targetReps: 5)
        let original = Set([ObjectIdentifier(first), ObjectIdentifier(second)])
        let reordered = Set([ObjectIdentifier(second), ObjectIdentifier(first)])

        let removed = RoutineEditorLogic.removedExerciseIDs(original: original, remaining: reordered)

        XCTAssertTrue(removed.isEmpty)
    }

    func testRemovedExerciseIDsIncludesRowsRemovedFromTheDraft() {
        let kept = RoutineExercise(exercise: "Bench Press", primaryMuscle: .chest, order: 0, targetSets: 3, targetReps: 8)
        let removedExercise = RoutineExercise(exercise: "Squat", primaryMuscle: .quads, order: 1, targetSets: 3, targetReps: 5)
        let original = Set([ObjectIdentifier(kept), ObjectIdentifier(removedExercise)])

        let removed = RoutineEditorLogic.removedExerciseIDs(original: original, remaining: [ObjectIdentifier(kept)])

        XCTAssertEqual(removed, [ObjectIdentifier(removedExercise)])
    }

    func testRemovedExerciseIDsHandlesDraftShrinkingToEmpty() {
        let first = RoutineExercise(exercise: "Bench Press", primaryMuscle: .chest, order: 0, targetSets: 3, targetReps: 8)
        let second = RoutineExercise(exercise: "Squat", primaryMuscle: .quads, order: 1, targetSets: 3, targetReps: 5)
        let original = Set([ObjectIdentifier(first), ObjectIdentifier(second)])

        let removed = RoutineEditorLogic.removedExerciseIDs(original: original, remaining: [])

        XCTAssertEqual(removed, original)
    }

    func testFinalOrderValuesAreSequentialAndZeroBasedRegardlessOfOriginalOrderGaps() {
        let finalOrders = RoutineEditorLogic.finalOrderValues(count: 4)

        XCTAssertEqual(finalOrders, [0, 1, 2, 3])
    }
}
