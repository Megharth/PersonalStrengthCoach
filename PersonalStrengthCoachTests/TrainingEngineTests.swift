import XCTest
@testable import PersonalStrengthCoach

final class TrainingEngineTests: XCTestCase {
    func testReadinessWithoutHealthDataUsesNeutralFallback() {
        let result = RecoveryEngine.readiness(today: nil, recent: [], workouts: [])

        XCTAssertEqual(result.score, 50)
        XCTAssertEqual(result.color, "Yellow")
        XCTAssertEqual(result.factors, ["Connect Apple Health to calculate readiness."])
        XCTAssertEqual(result.confidence, .low)
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
        // Weight/reps raised from the original 80x5 (volume 400) so the old workout's volume (550)
        // keeps the current workout's 725 within the new 40% single-session PR guard.
        let old = Workout(date: Date(timeIntervalSince1970: 100), title: "Old", durationMinutes: 0, sets: [
            ExerciseSet(exercise: "Bench Press", weight: 55, reps: 10, setNumber: 1, primaryMuscle: .chest)
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

    func testMuscleRecoveryClampsFutureDatedWorkoutToZero() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let futureWorkout = workout(date: now.addingTimeInterval(3_600), exercises: [("Bench Press", .chest)])

        XCTAssertEqual(RecoveryEngine.muscleRecovery(.chest, workouts: [futureWorkout], now: now), 0)
    }

    private func validBaselineDays(count: Int, before date: Date, calendar: Calendar = .current) -> [DailyRecovery] {
        (1...count).map { offset in
            DailyRecovery(date: calendar.date(byAdding: .day, value: -offset, to: date)!, sleepHours: 8, hrv: 60, restingHeartRate: 50, weightKg: 80)
        }
    }

    func testReadinessTreatsMissingHRVAsNeutralWhenRestingHeartRateIsValid() {
        let calendar = Calendar.current
        let now = Date()
        let today = calendar.startOfDay(for: now)
        let recovery = DailyRecovery(date: today, sleepHours: 8, hrv: 0, restingHeartRate: 50, weightKg: 80)
        let baseline = DailyRecovery(date: calendar.date(byAdding: .day, value: -2, to: today)!, sleepHours: 8, hrv: 60, restingHeartRate: 50, weightKg: 80)

        let result = RecoveryEngine.readiness(today: recovery, recent: [baseline], workouts: [], now: now)

        // sleep 30 + HRV neutral 15 + RHR 20 (computed normally) + load 20 (no workouts) = 85
        XCTAssertEqual(result.score, 85)
        XCTAssertEqual(result.color, "Green")
    }

    func testReadinessTreatsMissingRestingHeartRateAsNeutralWhenHRVIsValid() {
        let calendar = Calendar.current
        let now = Date()
        let today = calendar.startOfDay(for: now)
        let recovery = DailyRecovery(date: today, sleepHours: 8, hrv: 60, restingHeartRate: 0, weightKg: 80)
        let baseline = DailyRecovery(date: calendar.date(byAdding: .day, value: -2, to: today)!, sleepHours: 8, hrv: 60, restingHeartRate: 50, weightKg: 80)

        let result = RecoveryEngine.readiness(today: recovery, recent: [baseline], workouts: [], now: now)

        // sleep 30 + HRV 30 (computed normally) + RHR neutral 10 + load 20 (no workouts) = 90
        XCTAssertEqual(result.score, 90)
        XCTAssertEqual(result.color, "Green")
    }

    func testReadinessTreatsMissingHRVAndRestingHeartRateAsNeutral() {
        let calendar = Calendar.current
        let now = Date()
        let today = calendar.startOfDay(for: now)
        let recovery = DailyRecovery(date: today, sleepHours: 8, hrv: 0, restingHeartRate: 0, weightKg: 80)
        let baseline = DailyRecovery(date: calendar.date(byAdding: .day, value: -2, to: today)!, sleepHours: 8, hrv: 60, restingHeartRate: 50, weightKg: 80)

        let result = RecoveryEngine.readiness(today: recovery, recent: [baseline], workouts: [], now: now)

        // sleep 30 + HRV neutral 15 + RHR neutral 10 + load 20 (no workouts) = 75
        XCTAssertEqual(result.score, 75)
        XCTAssertEqual(result.color, "Green")
        XCTAssertEqual(result.confidence, .low)
    }

    func testReadinessTreatsEmptyBaselineAsNeutralForHRVAndRHR() {
        let calendar = Calendar.current
        let now = Date()
        let today = calendar.startOfDay(for: now)
        let recovery = DailyRecovery(date: today, sleepHours: 8, hrv: 60, restingHeartRate: 50, weightKg: 80)

        let result = RecoveryEngine.readiness(today: recovery, recent: [], workouts: [], now: now)

        // No baseline day to compare against, so both HRV and RHR fall back to neutral
        // even though today's readings are themselves valid.
        // sleep 30 + HRV neutral 15 + RHR neutral 10 + load 20 (no workouts) = 75
        XCTAssertEqual(result.score, 75)
        XCTAssertEqual(result.color, "Green")
        XCTAssertEqual(result.confidence, .low)
    }

    func testReadinessTreatsAllInvalidBaselineReadingsAsNeutralForHRVAndRHR() {
        let calendar = Calendar.current
        let now = Date()
        let today = calendar.startOfDay(for: now)
        let recovery = DailyRecovery(date: today, sleepHours: 8, hrv: 60, restingHeartRate: 50, weightKg: 80)
        let invalidBaseline = DailyRecovery(date: calendar.date(byAdding: .day, value: -2, to: today)!, sleepHours: 8, hrv: 0, restingHeartRate: 0, weightKg: 80)

        let result = RecoveryEngine.readiness(today: recovery, recent: [invalidBaseline], workouts: [], now: now)

        // The only baseline day has 0/invalid HRV and RHR, so it must not be averaged in;
        // this is equivalent to having no valid baseline day at all.
        XCTAssertEqual(result.score, 75)
        XCTAssertEqual(result.color, "Green")
        XCTAssertEqual(result.confidence, .low)
    }

    func testReadinessTreatsDataOlderThanYesterdayAsStaleAndReturnsNeutralFallback() {
        let calendar = Calendar.current
        let now = Date()
        let staleDate = calendar.date(byAdding: .day, value: -3, to: calendar.startOfDay(for: now))!
        let recovery = DailyRecovery(date: staleDate, sleepHours: 8, hrv: 60, restingHeartRate: 50, weightKg: 80)

        let result = RecoveryEngine.readiness(today: recovery, recent: [], workouts: [], now: now)

        XCTAssertEqual(result.score, 50)
        XCTAssertEqual(result.color, "Yellow")
        XCTAssertEqual(result.confidence, .low)
        XCTAssertNotEqual(result.factors, ["Connect Apple Health to calculate readiness."])
        XCTAssertTrue(result.factors.contains { $0.localizedCaseInsensitiveContains("stale") || $0.localizedCaseInsensitiveContains("sync") })
    }

    func testReadinessTreatsYesterdaysDataAsNotStale() {
        let calendar = Calendar.current
        let now = Date()
        let today = calendar.startOfDay(for: now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
        let recovery = DailyRecovery(date: yesterday, sleepHours: 8, hrv: 60, restingHeartRate: 50, weightKg: 80)
        let baseline = DailyRecovery(date: calendar.date(byAdding: .day, value: -3, to: today)!, sleepHours: 8, hrv: 60, restingHeartRate: 50, weightKg: 80)

        let result = RecoveryEngine.readiness(today: recovery, recent: [baseline], workouts: [], now: now)

        // Yesterday is within the 1-day tolerance, so this computes normally rather than
        // falling back to the stale-data neutral result.
        XCTAssertEqual(result.score, 100)
        XCTAssertEqual(result.color, "Green")
    }

    func testReadinessTreatsFutureDatedDataAsStaleAndReturnsNeutralFallback() {
        let calendar = Calendar.current
        let now = Date()
        let futureDate = calendar.date(byAdding: .day, value: 2, to: calendar.startOfDay(for: now))!
        let recovery = DailyRecovery(date: futureDate, sleepHours: 8, hrv: 60, restingHeartRate: 50, weightKg: 80)

        let result = RecoveryEngine.readiness(today: recovery, recent: [], workouts: [], now: now)

        XCTAssertEqual(result.score, 50)
        XCTAssertEqual(result.color, "Yellow")
        XCTAssertEqual(result.confidence, .low)
    }

    func testReadinessConfidenceIsLowWithFewerThanThreeValidBaselineDays() {
        let calendar = Calendar.current
        let now = Date()
        let today = calendar.startOfDay(for: now)
        let recovery = DailyRecovery(date: today, sleepHours: 8, hrv: 60, restingHeartRate: 50, weightKg: 80)
        let baseline = validBaselineDays(count: 2, before: today, calendar: calendar)

        let result = RecoveryEngine.readiness(today: recovery, recent: baseline, workouts: [], now: now)

        XCTAssertEqual(result.confidence, .low)
    }

    func testReadinessConfidenceIsMediumWithFourValidBaselineDays() {
        let calendar = Calendar.current
        let now = Date()
        let today = calendar.startOfDay(for: now)
        let recovery = DailyRecovery(date: today, sleepHours: 8, hrv: 60, restingHeartRate: 50, weightKg: 80)
        let baseline = validBaselineDays(count: 4, before: today, calendar: calendar)

        let result = RecoveryEngine.readiness(today: recovery, recent: baseline, workouts: [], now: now)

        XCTAssertEqual(result.confidence, .medium)
    }

    func testReadinessConfidenceIsHighWithSevenValidBaselineDaysAndValidToday() {
        let calendar = Calendar.current
        let now = Date()
        let today = calendar.startOfDay(for: now)
        let recovery = DailyRecovery(date: today, sleepHours: 8, hrv: 60, restingHeartRate: 50, weightKg: 80)
        let baseline = validBaselineDays(count: 7, before: today, calendar: calendar)

        let result = RecoveryEngine.readiness(today: recovery, recent: baseline, workouts: [], now: now)

        XCTAssertEqual(result.confidence, .high)
    }

    func testReadinessConfidenceIsMediumWhenOnlyOneMetricInvalidDespiteSufficientBaseline() {
        let calendar = Calendar.current
        let now = Date()
        let today = calendar.startOfDay(for: now)
        let recovery = DailyRecovery(date: today, sleepHours: 8, hrv: 0, restingHeartRate: 50, weightKg: 80)
        let baseline = validBaselineDays(count: 7, before: today, calendar: calendar)

        let result = RecoveryEngine.readiness(today: recovery, recent: baseline, workouts: [], now: now)

        XCTAssertEqual(result.confidence, .medium)
    }

    func testPersonalRecordsRejectsOneRepMaxJumpOver40Percent() {
        let old = Workout(date: Date(timeIntervalSince1970: 100), title: "Old", durationMinutes: 0, sets: [
            ExerciseSet(exercise: "Deadlift", weight: 50, reps: 1, setNumber: 1, primaryMuscle: .hamstrings)
        ])
        let current = Workout(date: Date(timeIntervalSince1970: 200), title: "Current", durationMinutes: 0, sets: [
            ExerciseSet(exercise: "Deadlift", weight: 500, reps: 1, setNumber: 1, primaryMuscle: .hamstrings)
        ])

        XCTAssertFalse(PerformanceEngine.personalRecords(in: current, history: [old]).contains("Deadlift estimated 1RM"))
    }

    func testPersonalRecordsAllowsOneRepMaxJumpAtExactly40PercentBoundary() {
        let old = Workout(date: Date(timeIntervalSince1970: 100), title: "Old", durationMinutes: 0, sets: [
            ExerciseSet(exercise: "Deadlift", weight: 50, reps: 1, setNumber: 1, primaryMuscle: .hamstrings)
        ])
        // 70 / 50 == 1.4 exactly (same rep count keeps the e1RM ratio equal to the weight ratio).
        let current = Workout(date: Date(timeIntervalSince1970: 200), title: "Current", durationMinutes: 0, sets: [
            ExerciseSet(exercise: "Deadlift", weight: 70, reps: 1, setNumber: 1, primaryMuscle: .hamstrings)
        ])

        XCTAssertTrue(PerformanceEngine.personalRecords(in: current, history: [old]).contains("Deadlift estimated 1RM"))
    }

    func testPersonalRecordsRejectsWorkoutVolumeJumpOver40Percent() {
        let old = Workout(date: Date(timeIntervalSince1970: 100), title: "Old", durationMinutes: 0, sets: [
            ExerciseSet(exercise: "Squat", weight: 100, reps: 5, setNumber: 1, primaryMuscle: .quads)
        ])
        let current = Workout(date: Date(timeIntervalSince1970: 200), title: "Current", durationMinutes: 0, sets: [
            ExerciseSet(exercise: "Squat", weight: 100, reps: 5, setNumber: 1, primaryMuscle: .quads),
            ExerciseSet(exercise: "Row", weight: 50, reps: 5, setNumber: 2, primaryMuscle: .upperBack)
        ])

        XCTAssertEqual(current.volume, 750, accuracy: 0.001)
        XCTAssertFalse(PerformanceEngine.personalRecords(in: current, history: [old]).contains("Workout volume"))
    }

    func testPersonalRecordsAlwaysRecordsFirstEverAttemptAtExerciseAsPR() {
        let old = Workout(date: Date(timeIntervalSince1970: 100), title: "Old", durationMinutes: 0, sets: [
            ExerciseSet(exercise: "Row", weight: 40, reps: 5, setNumber: 1, primaryMuscle: .upperBack)
        ])
        let current = Workout(date: Date(timeIntervalSince1970: 200), title: "Current", durationMinutes: 0, sets: [
            ExerciseSet(exercise: "Deadlift", weight: 500, reps: 1, setNumber: 1, primaryMuscle: .hamstrings)
        ])

        XCTAssertTrue(PerformanceEngine.personalRecords(in: current, history: [old]).contains("Deadlift estimated 1RM"))
    }

    func testPersonalRecordsWithNoHistoryRecordsBothOneRepMaxAndVolumePRs() {
        let current = Workout(date: Date(timeIntervalSince1970: 200), title: "Current", durationMinutes: 0, sets: [
            ExerciseSet(exercise: "Deadlift", weight: 100, reps: 5, setNumber: 1, primaryMuscle: .hamstrings)
        ])

        let records = PerformanceEngine.personalRecords(in: current, history: [])

        XCTAssertTrue(records.contains("Deadlift estimated 1RM"))
        XCTAssertTrue(records.contains("Workout volume"))
    }

    func testPersonalRecordsTreatsZeroWeightPriorRecordAsNoPriorData() {
        // A degenerate historical set with 0 recorded weight (e.g. bad data or a bodyweight
        // entry logged without a weight) must not be treated as a real prior best of 0, which
        // would otherwise cap all future PRs at 0 * 1.4 = 0 and permanently block them.
        let old = Workout(date: Date(timeIntervalSince1970: 100), title: "Old", durationMinutes: 0, sets: [
            ExerciseSet(exercise: "Deadlift", weight: 0, reps: 5, setNumber: 1, primaryMuscle: .hamstrings)
        ])
        let current = Workout(date: Date(timeIntervalSince1970: 200), title: "Current", durationMinutes: 0, sets: [
            ExerciseSet(exercise: "Deadlift", weight: 100, reps: 5, setNumber: 1, primaryMuscle: .hamstrings)
        ])

        let records = PerformanceEngine.personalRecords(in: current, history: [old])

        XCTAssertTrue(records.contains("Deadlift estimated 1RM"))
        XCTAssertTrue(records.contains("Workout volume"))
    }

    func testPersonalRecordsDoesNotFlagRepeatedZeroWeightBodyweightSetAsPR() {
        // Bodyweight exercises (e.g. pull-ups) are legitimately logged with weight == 0, so
        // estimated1RM == 0 for every such set. A genuine prior best of 0.0 (not nil) must not
        // let a same-or-fewer-rep repeat register as a "new" PR just because new == 0 isn't
        // greater than a nil previousBest fallback.
        let old = Workout(date: Date(timeIntervalSince1970: 100), title: "Old", durationMinutes: 0, sets: [
            ExerciseSet(exercise: "Pull Up", weight: 0, reps: 10, setNumber: 1, primaryMuscle: .upperBack)
        ])
        let current = Workout(date: Date(timeIntervalSince1970: 200), title: "Current", durationMinutes: 0, sets: [
            ExerciseSet(exercise: "Pull Up", weight: 0, reps: 8, setNumber: 1, primaryMuscle: .upperBack)
        ])

        let records = PerformanceEngine.personalRecords(in: current, history: [old])

        XCTAssertFalse(records.contains("Pull Up estimated 1RM"))
    }

    func testPersonalRecordsStillFlagsRealWeightedPRAfterZeroWeightBodyweightHistory() {
        // A prior 0-weight bodyweight history for one exercise must not suppress a genuine
        // weighted PR on a different (or the same) exercise.
        let old = Workout(date: Date(timeIntervalSince1970: 100), title: "Old", durationMinutes: 0, sets: [
            ExerciseSet(exercise: "Pull Up", weight: 0, reps: 10, setNumber: 1, primaryMuscle: .upperBack)
        ])
        let current = Workout(date: Date(timeIntervalSince1970: 200), title: "Current", durationMinutes: 0, sets: [
            ExerciseSet(exercise: "Pull Up", weight: 25, reps: 5, setNumber: 1, primaryMuscle: .upperBack)
        ])

        let records = PerformanceEngine.personalRecords(in: current, history: [old])

        XCTAssertTrue(records.contains("Pull Up estimated 1RM"))
    }

    func testReadinessConfidenceIsMediumAtLowerBoundaryOfThreeValidBaselineDays() {
        let calendar = Calendar.current
        let now = Date()
        let today = calendar.startOfDay(for: now)
        let recovery = DailyRecovery(date: today, sleepHours: 8, hrv: 60, restingHeartRate: 50, weightKg: 80)
        let baseline = validBaselineDays(count: 3, before: today, calendar: calendar)

        let result = RecoveryEngine.readiness(today: recovery, recent: baseline, workouts: [], now: now)

        XCTAssertEqual(result.confidence, .medium)
    }

    func testReadinessConfidenceIsMediumAtUpperBoundaryOfSixValidBaselineDays() {
        let calendar = Calendar.current
        let now = Date()
        let today = calendar.startOfDay(for: now)
        let recovery = DailyRecovery(date: today, sleepHours: 8, hrv: 60, restingHeartRate: 50, weightKg: 80)
        let baseline = validBaselineDays(count: 6, before: today, calendar: calendar)

        let result = RecoveryEngine.readiness(today: recovery, recent: baseline, workouts: [], now: now)

        XCTAssertEqual(result.confidence, .medium)
    }

    func testReadinessConfidenceIsHighWithEightValidBaselineDaysAndValidToday() {
        let calendar = Calendar.current
        let now = Date()
        let today = calendar.startOfDay(for: now)
        let recovery = DailyRecovery(date: today, sleepHours: 8, hrv: 60, restingHeartRate: 50, weightKg: 80)
        let baseline = validBaselineDays(count: 8, before: today, calendar: calendar)

        let result = RecoveryEngine.readiness(today: recovery, recent: baseline, workouts: [], now: now)

        XCTAssertEqual(result.confidence, .high)
    }

    func testPersonalRecordsAllowsWorkoutVolumeJumpAtExactly40PercentBoundary() {
        let old = Workout(date: Date(timeIntervalSince1970: 100), title: "Old", durationMinutes: 0, sets: [
            ExerciseSet(exercise: "Squat", weight: 100, reps: 5, setNumber: 1, primaryMuscle: .quads)
        ])
        // 700 / 500 == 1.4 exactly.
        let current = Workout(date: Date(timeIntervalSince1970: 200), title: "Current", durationMinutes: 0, sets: [
            ExerciseSet(exercise: "Squat", weight: 100, reps: 5, setNumber: 1, primaryMuscle: .quads),
            ExerciseSet(exercise: "Row", weight: 40, reps: 5, setNumber: 2, primaryMuscle: .upperBack)
        ])

        XCTAssertEqual(current.volume, 700, accuracy: 0.001)
        XCTAssertTrue(PerformanceEngine.personalRecords(in: current, history: [old]).contains("Workout volume"))
    }

    func testReadinessBaselineFilterExcludesSameDayAndFutureEntriesFromRecent() {
        let calendar = Calendar.current
        let now = Date()
        let today = calendar.startOfDay(for: now)
        let recovery = DailyRecovery(date: today, sleepHours: 8, hrv: 60, restingHeartRate: 50, weightKg: 80)
        let realBaseline = validBaselineDays(count: 2, before: today, calendar: calendar)
        // These entries share today's own date (or are future-dated) and carry very different
        // readings; if the baseline filter ever became inclusive of "today" (e.g. `<=` instead
        // of `<`) or skipped the future check, they would skew the baseline average and
        // inflate the valid-baseline-day count used for confidence.
        let sameDayEntry = DailyRecovery(date: today, sleepHours: 8, hrv: 200, restingHeartRate: 10, weightKg: 80)
        let futureEntry = DailyRecovery(date: calendar.date(byAdding: .day, value: 1, to: today)!, sleepHours: 8, hrv: 200, restingHeartRate: 10, weightKg: 80)

        let result = RecoveryEngine.readiness(today: recovery, recent: realBaseline + [sameDayEntry, futureEntry], workouts: [], now: now)

        // Only the 2 genuine baseline days (both strictly before today) should count:
        // sleep 30 + HRV 30 + RHR 20 + load 20 = 100, with only 2 valid baseline days -> low confidence.
        XCTAssertEqual(result.score, 100)
        XCTAssertEqual(result.color, "Green")
        XCTAssertEqual(result.confidence, .low)
    }
}
