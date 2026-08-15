import XCTest
@testable import PersonalStrengthCoach

final class PreviousSetTests: XCTestCase {
    private func makeSet(
        _ exercise: String,
        weight: Double,
        reps: Int,
        setNumber: Int,
        muscle: MuscleGroup = .chest
    ) -> ExerciseSet {
        ExerciseSet(exercise: exercise, weight: weight, reps: reps, setNumber: setNumber, primaryMuscle: muscle)
    }

    private func makeWorkout(date: Date, sets: [ExerciseSet]) -> Workout {
        let workout = Workout(date: date, title: "Session", durationMinutes: 45)
        workout.sets = sets
        for set in sets { set.workout = workout }
        return workout
    }

    func testMostRecentWorkoutWinsOverOlderHigherVolumeWorkout() {
        let older = makeWorkout(date: Date(timeIntervalSince1970: 1_000), sets: [
            makeSet("Bench Press", weight: 100, reps: 10, setNumber: 1),
            makeSet("Bench Press", weight: 100, reps: 10, setNumber: 2)
        ])
        let newer = makeWorkout(date: Date(timeIntervalSince1970: 2_000), sets: [
            makeSet("Bench Press", weight: 60, reps: 5, setNumber: 1)
        ])

        let result = PreviousSetEngine.mostRecentPerformance(for: "Bench Press", in: [older, newer])

        XCTAssertEqual(result?.sets.map(\.weight), [60])
        XCTAssertEqual(result?.date, newer.date)
    }

    func testAliasesMatchNormalizedExerciseNames() {
        let workout = makeWorkout(date: Date(timeIntervalSince1970: 1_000), sets: [
            makeSet("Barbell Bench Press", weight: 80, reps: 8, setNumber: 1)
        ])

        let result = PreviousSetEngine.mostRecentPerformance(for: "Bench Press", in: [workout])

        XCTAssertEqual(result?.sets.count, 1)
        XCTAssertEqual(result?.sets.first?.exercise, "Barbell Bench Press")
    }

    func testExcludesWorkoutBeingEdited() {
        let current = makeWorkout(date: Date(timeIntervalSince1970: 2_000), sets: [
            makeSet("Squat", weight: 150, reps: 3, setNumber: 1, muscle: .quads)
        ])
        let previous = makeWorkout(date: Date(timeIntervalSince1970: 1_000), sets: [
            makeSet("Squat", weight: 120, reps: 5, setNumber: 1, muscle: .quads)
        ])

        let result = PreviousSetEngine.mostRecentPerformance(for: "Squat", in: [current, previous], excluding: current)

        XCTAssertEqual(result?.sets.first?.weight, 120)
        XCTAssertEqual(result?.date, previous.date)
    }

    func testReturnsNilForExerciseWithoutHistory() {
        let workout = makeWorkout(date: Date(timeIntervalSince1970: 1_000), sets: [
            makeSet("Bench Press", weight: 80, reps: 8, setNumber: 1)
        ])

        XCTAssertNil(PreviousSetEngine.mostRecentPerformance(for: "Deadlift", in: [workout]))
    }

    func testSetsAreOrderedBySetNumberWithDeterministicTieBreakers() {
        let workout = makeWorkout(date: Date(timeIntervalSince1970: 1_000), sets: [
            makeSet("Bench Press", weight: 70, reps: 6, setNumber: 2),
            makeSet("Bench Press", weight: 60, reps: 8, setNumber: 1),
            makeSet("Bench Press", weight: 65, reps: 7, setNumber: 1),
            makeSet("Bench Press", weight: 80, reps: 5, setNumber: 3)
        ])

        let result = PreviousSetEngine.mostRecentPerformance(for: "Bench Press", in: [workout])

        XCTAssertEqual(result?.sets.map(\.setNumber), [1, 1, 2, 3])
        XCTAssertEqual(result?.sets.map(\.weight), [60, 65, 70, 80])
        XCTAssertEqual(result?.sets.map(\.reps), [8, 7, 6, 5])
    }

    func testEqualDatesUseInputOrderDeterministically() {
        let first = makeWorkout(date: Date(timeIntervalSince1970: 1_000), sets: [
            makeSet("Bench Press", weight: 60, reps: 8, setNumber: 1)
        ])
        let second = makeWorkout(date: first.date, sets: [
            makeSet("Bench Press", weight: 80, reps: 5, setNumber: 1)
        ])

        let result = PreviousSetEngine.mostRecentPerformance(for: "Bench Press", in: [first, second])

        XCTAssertEqual(result?.sets.first?.weight, 60)
    }

    func testDraftExercisePrefillsCorrespondingPreviousSets() {
        let workout = makeWorkout(date: Date(timeIntervalSince1970: 1_000), sets: [
            makeSet("Bench Press", weight: 80, reps: 8, setNumber: 1),
            makeSet("Bench Press", weight: 82.5, reps: 6, setNumber: 2)
        ])
        let previous = PreviousSetEngine.mostRecentPerformance(for: "Bench Press", in: [workout])
        let exercise = LibraryExercise(name: "Bench Press", primaryMuscle: .chest)

        let draft = LoggedExercise.draftExercise(from: exercise, previous: previous)

        XCTAssertEqual(draft.sets.map { $0.weight }, [80, 82.5])
        XCTAssertEqual(draft.sets.map { $0.reps }, [8, 6])
    }

    func testDraftExerciseRetainsDefaultSetsWithoutHistory() {
        let exercise = LibraryExercise(name: "New Exercise", primaryMuscle: .upperBack)

        let draft = LoggedExercise.draftExercise(from: exercise)

        XCTAssertEqual(draft.sets.count, 3)
        XCTAssertEqual(draft.sets.map { $0.weight }, [0, 0, 0])
        XCTAssertEqual(draft.sets.map { $0.reps }, [8, 8, 8])
    }
}
