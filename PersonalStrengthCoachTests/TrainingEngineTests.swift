import XCTest
@testable import PersonalStrengthCoach

final class TrainingEngineTests: XCTestCase {
    func testReadinessWithoutHealthDataUsesNeutralFallback() {
        let result = RecoveryEngine.readiness(today: nil, recent: [], workouts: [])

        XCTAssertEqual(result.score, 50)
        XCTAssertEqual(result.color, "Yellow")
        XCTAssertEqual(result.factors, ["Connect Apple Health to calculate readiness."])
    }

    func testReadinessUsesSleepRecoveryAndYesterdayLoadBucket() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
        let recovery = DailyRecovery(date: today, sleepHours: 8, hrv: 60, restingHeartRate: 50, weightKg: 80)
        let baseline = DailyRecovery(date: calendar.date(byAdding: .day, value: -2, to: today)!, sleepHours: 8, hrv: 60, restingHeartRate: 50, weightKg: 80)
        let workout = Workout(date: yesterday, title: "Heavy", durationMinutes: 0, sets: [
            ExerciseSet(exercise: "Bench Press", weight: 1_000, reps: 5, setNumber: 1, primaryMuscle: .chest)
        ])

        let result = RecoveryEngine.readiness(today: recovery, recent: [baseline], workouts: [workout])

        XCTAssertEqual(result.score, 94)
        XCTAssertEqual(result.color, "Green")
    }

    func testPerformanceCalculatesVolumeEstimatedOneRMAndPersonalRecords() {
        let old = Workout(date: Date(timeIntervalSince1970: 100), title: "Old", durationMinutes: 0, sets: [
            ExerciseSet(exercise: "Bench Press", weight: 80, reps: 5, setNumber: 1, primaryMuscle: .chest)
        ])
        let current = Workout(date: Date(timeIntervalSince1970: 200), title: "Current", durationMinutes: 0, sets: [
            ExerciseSet(exercise: "Barbell Bench Press", weight: 85, reps: 5, setNumber: 1, primaryMuscle: .chest),
            ExerciseSet(exercise: "Squat", weight: 100, reps: 3, setNumber: 2, primaryMuscle: .quads)
        ])

        XCTAssertEqual(current.volume, 725, accuracy: 0.001)
        XCTAssertEqual(PerformanceEngine.estimated1RM(for: "Bench Press", sets: current.sets), 99.1666667, accuracy: 0.000001)
        XCTAssertTrue(PerformanceEngine.personalRecords(in: current, history: [old]).contains("Bench Press estimated 1RM"))
        XCTAssertTrue(PerformanceEngine.personalRecords(in: current, history: [old]).contains("Workout volume"))
    }

    func testWeeklyVolumeExcludesWorkoutsOlderThanSevenDays() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let recent = Workout(date: now.addingTimeInterval(-6 * 86_400), title: "Recent", durationMinutes: 0, sets: [
            ExerciseSet(exercise: "Row", weight: 10, reps: 5, setNumber: 1, primaryMuscle: .upperBack)
        ])
        let old = Workout(date: now.addingTimeInterval(-7 * 86_400 - 1), title: "Old", durationMinutes: 0, sets: [
            ExerciseSet(exercise: "Row", weight: 100, reps: 5, setNumber: 1, primaryMuscle: .upperBack)
        ])

        XCTAssertEqual(PerformanceEngine.weeklyVolume([recent, old], now: now), 50)
    }

    func testRecommendationUsesRecoveredMusclesAndDefaultsToActiveRecovery() {
        XCTAssertEqual(RecommendationEngine.nextWorkout(workouts: []).title, "Push Day")

        let recent = Workout(title: "Recent", durationMinutes: 0)
        for (exercise, muscle) in [("Bench Press", MuscleGroup.chest), ("Row", .upperBack), ("Squat", .quads)] {
            let set = ExerciseSet(exercise: exercise, weight: 10, reps: 5, setNumber: recent.sets.count + 1, primaryMuscle: muscle)
            set.workout = recent
            recent.sets.append(set)
        }

        XCTAssertEqual(RecommendationEngine.nextWorkout(workouts: [recent]).title, "Active Recovery")
    }

    private func workout(date: Date, exercises: [(String, MuscleGroup)]) -> Workout {
        let workout = Workout(date: date, title: "Workout", durationMinutes: 0)
        for (index, exercise) in exercises.enumerated() {
            let set = ExerciseSet(exercise: exercise.0, weight: 10, reps: 5, setNumber: index + 1, primaryMuscle: exercise.1)
            set.workout = workout
            workout.sets.append(set)
        }
        return workout
    }

    func testRecommendationSelectsPullDayWhenOnlyBackIsRecovered() {
        let chestRecent = workout(date: .now, exercises: [("Bench Press", .chest)])
        let backRecovered = workout(date: .now.addingTimeInterval(-4 * 86_400), exercises: [("Row", .upperBack)])

        XCTAssertEqual(RecommendationEngine.nextWorkout(workouts: [chestRecent, backRecovered]).title, "Pull Day")
    }

    func testRecommendationSelectsLegDayWhenChestAndBackAreNotRecovered() {
        let upperBodyRecent = workout(date: .now, exercises: [("Bench Press", .chest), ("Row", .upperBack)])

        XCTAssertEqual(RecommendationEngine.nextWorkout(workouts: [upperBodyRecent]).title, "Leg Day")
    }

    func testMuscleRecoveryRampsLinearlyAndCapsAtSeventyTwoHours() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let atThreshold = workout(date: now.addingTimeInterval(-50.4 * 3_600), exercises: [("Bench Press", .chest)])
        let justBelowThreshold = workout(date: now.addingTimeInterval(-49.4 * 3_600), exercises: [("Bench Press", .chest)])

        XCTAssertEqual(RecoveryEngine.muscleRecovery(.chest, workouts: [atThreshold], now: now), 70)
        XCTAssertLessThan(RecoveryEngine.muscleRecovery(.chest, workouts: [justBelowThreshold], now: now), 70)
        XCTAssertEqual(RecoveryEngine.muscleRecovery(.chest, workouts: [], now: now), 100)
    }
}
