import XCTest
@testable import PersonalStrengthCoach

final class TrainingEngineTests: XCTestCase {
    func testRepsValidationClampsToMinimumAndMaximum() {
        XCTAssertEqual(RepsEngine.validated(-1), 1)
        XCTAssertEqual(RepsEngine.validated(0), 1)
        XCTAssertEqual(RepsEngine.validated(8), 8)
        XCTAssertEqual(RepsEngine.validated(1_000), 999)
    }

    func testRPEValidationAndRIRConversion() {
        XCTAssertNil(RPEEngine.validated(nil))
        XCTAssertNil(RPEEngine.validated(-0.5))
        XCTAssertNil(RPEEngine.validated(10.5))
        XCTAssertNil(RPEEngine.validated(.infinity))
        XCTAssertEqual(RPEEngine.validated(7.24), 7.0)
        XCTAssertEqual(RPEEngine.validated(7.26), 7.5)
        XCTAssertEqual(RPEEngine.rir(from: 8.5), 1.5)
        XCTAssertEqual(RPEEngine.rpe(fromRIR: 1.5), 8.5)
        XCTAssertNil(RPEEngine.rpe(fromRIR: -1))
    }

    func testWarmupsAreExcludedFromVolumeAndEstimatedOneRMButOtherSetTypesCount() {
        let warmup = ExerciseSet(exercise: "Bench Press", weight: 200, reps: 10, setNumber: 1, primaryMuscle: .chest, setType: .warmup)
        let drop = ExerciseSet(exercise: "Bench Press", weight: 80, reps: 5, setNumber: 2, primaryMuscle: .chest, setType: .dropSet)
        let failure = ExerciseSet(exercise: "Bench Press", weight: 90, reps: 5, setNumber: 3, primaryMuscle: .chest, setType: .failure)
        let workout = Workout(title: "Session", durationMinutes: 0, sets: [warmup, drop, failure])

        XCTAssertEqual(workout.volume, 850, accuracy: 0.001)
        XCTAssertEqual(PerformanceEngine.estimated1RM(for: "Bench Press", sets: workout.sets), failure.estimated1RM, accuracy: 0.001)
    }

    func testWarmupsAreExcludedFromPRCandidatesAndHistoricalBest() {
        let old = Workout(date: Date(timeIntervalSince1970: 100), title: "Old", durationMinutes: 0, sets: [
            ExerciseSet(exercise: "Squat", weight: 100, reps: 5, setNumber: 1, primaryMuscle: .quads, setType: .warmup)
        ])
        let current = Workout(date: Date(timeIntervalSince1970: 200), title: "Current", durationMinutes: 0, sets: [
            ExerciseSet(exercise: "Squat", weight: 80, reps: 5, setNumber: 1, primaryMuscle: .quads)
        ])

        XCTAssertTrue(PerformanceEngine.personalRecords(in: current, history: [old]).contains("Squat estimated 1RM"))
    }

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

    // MARK: - PerformanceEngine.weeklyEstimated1RM
    //
    // These tests pin down the following boundary convention for `weeks: Int, now: Date`
    // trailing weekly windows, oldest first: with `W = weeks` and window index `i` in `1...W`
    // (1 = oldest, W = most recent, each window half-open [start, end)):
    //   window i = [now - (W - i + 1) * 7 days, now - (W - i) * 7 days)
    // so the most recent window's upper bound is exactly `now`, and a set logged exactly on a
    // 7-day boundary belongs to the *later* (start-inclusive) window, not the earlier one.

    func testWeeklyEstimated1RMBoundaryDateLandsInExactlyOneWeek() {
        // weeks = 3 windows of 7 days each, ending exactly at `now`:
        //   window 1 (oldest):      [now - 21d, now - 14d)
        //   window 2:               [now - 14d, now -  7d)
        //   window 3 (most recent): [now -  7d, now)
        // A set logged exactly at the now-14d boundary must land in window 2 (start-inclusive)
        // and NOT window 1 (end-exclusive).
        let now = Date(timeIntervalSince1970: 1_000_000)
        let day: TimeInterval = 86_400
        let markerInWindow1 = Workout(date: now.addingTimeInterval(-20 * day), title: "W1", durationMinutes: 0, sets: [
            ExerciseSet(exercise: "Bench Press", weight: 10, reps: 1, setNumber: 1, primaryMuscle: .chest)
        ])
        let onBoundary = Workout(date: now.addingTimeInterval(-14 * day), title: "Boundary", durationMinutes: 0, sets: [
            ExerciseSet(exercise: "Bench Press", weight: 100, reps: 1, setNumber: 1, primaryMuscle: .chest)
        ])

        let result = PerformanceEngine.weeklyEstimated1RM(for: "Bench Press", workouts: [markerInWindow1, onBoundary], weeks: 3, now: now)

        // If the boundary date fell into window 1 instead of window 2, its much larger e1RM
        // (103.33) would win max() for that single week, collapsing this into one element.
        // Landing correctly in window 2 keeps the two sets in separate, ordered buckets.
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0], 10 * (1 + 1.0 / 30), accuracy: 0.0001)
        XCTAssertEqual(result[1], 100 * (1 + 1.0 / 30), accuracy: 0.0001)
    }

    func testWeeklyEstimated1RMOmitsWeekWithNoSetsRatherThanZeroFilling() {
        // Sets in week 1 ([-21d, -14d)) and week 3 ([-7d, now)); nothing in week 2. The result
        // must have exactly 2 elements, not 3, and not 3 with a 0.0 placeholder for week 2.
        let now = Date(timeIntervalSince1970: 1_000_000)
        let day: TimeInterval = 86_400
        let week1 = Workout(date: now.addingTimeInterval(-18 * day), title: "W1", durationMinutes: 0, sets: [
            ExerciseSet(exercise: "Bench Press", weight: 50, reps: 5, setNumber: 1, primaryMuscle: .chest)
        ])
        let week3 = Workout(date: now.addingTimeInterval(-3 * day), title: "W3", durationMinutes: 0, sets: [
            ExerciseSet(exercise: "Bench Press", weight: 90, reps: 5, setNumber: 1, primaryMuscle: .chest)
        ])

        let result = PerformanceEngine.weeklyEstimated1RM(for: "Bench Press", workouts: [week1, week3], weeks: 3, now: now)

        XCTAssertEqual(result.count, 2)
        XCTAssertFalse(result.contains(0.0))
        XCTAssertEqual(result[0], 50 * (1 + 5.0 / 30), accuracy: 0.0001)
        XCTAssertEqual(result[1], 90 * (1 + 5.0 / 30), accuracy: 0.0001)
    }

    func testWeeklyEstimated1RMTakesBestNotAverageOrSumWithinAWeek() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let day: TimeInterval = 86_400
        let session = Workout(date: now.addingTimeInterval(-3 * day), title: "Session", durationMinutes: 0, sets: [
            ExerciseSet(exercise: "Bench Press", weight: 50, reps: 5, setNumber: 1, primaryMuscle: .chest),
            ExerciseSet(exercise: "Bench Press", weight: 90, reps: 3, setNumber: 2, primaryMuscle: .chest),
            ExerciseSet(exercise: "Bench Press", weight: 20, reps: 10, setNumber: 3, primaryMuscle: .chest)
        ])
        // e1RMs: 50*(1+5/30)=58.33, 90*(1+3/30)=99, 20*(1+10/30)=26.67 -> best is 99, not the
        // sum (~184) or the average (~61.33).
        let expectedBest = 99.0

        let result = PerformanceEngine.weeklyEstimated1RM(for: "Bench Press", workouts: [session], weeks: 3, now: now)

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0], expectedBest, accuracy: 0.0001)
    }

    func testWeeklyEstimated1RMExcludesSetsForADifferentExerciseAndNormalizesAliases() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let day: TimeInterval = 86_400
        let session = Workout(date: now.addingTimeInterval(-3 * day), title: "Session", durationMinutes: 0, sets: [
            // "Barbell Bench Press" normalizes to "Bench Press" (ExerciseCatalog.normalize),
            // consistent with how estimated1RM(for:sets:) already matches on normalizedExercise.
            ExerciseSet(exercise: "Barbell Bench Press", weight: 50, reps: 5, setNumber: 1, primaryMuscle: .chest),
            ExerciseSet(exercise: "Squat", weight: 200, reps: 5, setNumber: 2, primaryMuscle: .quads)
        ])

        let result = PerformanceEngine.weeklyEstimated1RM(for: "Bench Press", workouts: [session], weeks: 3, now: now)

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0], 50 * (1 + 5.0 / 30), accuracy: 0.0001)
    }

    func testWeeklyEstimated1RMOrdersOldestWeekFirstAndMostRecentLast() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let day: TimeInterval = 86_400
        let oldestWeek = Workout(date: now.addingTimeInterval(-19 * day), title: "Old", durationMinutes: 0, sets: [
            ExerciseSet(exercise: "Bench Press", weight: 40, reps: 1, setNumber: 1, primaryMuscle: .chest)
        ])
        let mostRecentWeek = Workout(date: now.addingTimeInterval(-1 * day), title: "Recent", durationMinutes: 0, sets: [
            ExerciseSet(exercise: "Bench Press", weight: 150, reps: 1, setNumber: 1, primaryMuscle: .chest)
        ])

        let result = PerformanceEngine.weeklyEstimated1RM(for: "Bench Press", workouts: [oldestWeek, mostRecentWeek], weeks: 3, now: now)

        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0], 40 * (1 + 1.0 / 30), accuracy: 0.0001) // oldest week's value comes first
        XCTAssertEqual(result[1], 150 * (1 + 1.0 / 30), accuracy: 0.0001) // most recent week's value comes last
    }


    func testStrengthTrendPrefersExerciseWithUsableRecentHistory() {
        let now = Date(timeIntervalSince1970: 10_000_000)
        let day: TimeInterval = 86_400
        let oldFavorite = Workout(date: now.addingTimeInterval(-60 * day), title: "Old", durationMinutes: 0, sets: [
            ExerciseSet(exercise: "Bench Press", weight: 100, reps: 5, setNumber: 1, primaryMuscle: .chest),
            ExerciseSet(exercise: "Bench Press", weight: 100, reps: 5, setNumber: 2, primaryMuscle: .chest),
            ExerciseSet(exercise: "Bench Press", weight: 100, reps: 5, setNumber: 3, primaryMuscle: .chest)
        ])
        let recentSquatA = Workout(date: now.addingTimeInterval(-10 * day), title: "Squat A", durationMinutes: 0, sets: [
            ExerciseSet(exercise: "Squat", weight: 80, reps: 5, setNumber: 1, primaryMuscle: .quads)
        ])
        let recentSquatB = Workout(date: now.addingTimeInterval(-2 * day), title: "Squat B", durationMinutes: 0, sets: [
            ExerciseSet(exercise: "Squat", weight: 90, reps: 5, setNumber: 1, primaryMuscle: .quads)
        ])

        let trend = PerformanceEngine.strengthTrend(in: [oldFavorite, recentSquatA, recentSquatB], weeks: 7, now: now)

        XCTAssertEqual(trend?.exercise, "Squat")
        XCTAssertEqual(trend?.points.count, 2)
    }

    func testStrengthTrendReturnsNilWithoutTwoPopulatedWeeks() {
        let now = Date(timeIntervalSince1970: 10_000_000)
        let workout = Workout(date: now.addingTimeInterval(-2 * 86_400), title: "Recent", durationMinutes: 0, sets: [
            ExerciseSet(exercise: "Bench Press", weight: 80, reps: 5, setNumber: 1, primaryMuscle: .chest)
        ])

        XCTAssertNil(PerformanceEngine.strengthTrend(in: [workout], weeks: 7, now: now))
    }

    // MARK: - PerformanceEngine.personalRecords determinism

    func testPersonalRecordsReturnsDeterministicallySortedOrderForMultiplePRsInOneWorkout() {
        // Sets are logged "Squat" then "Bench Press" (not alphabetical) so that a passing test
        // actually verifies sorting, rather than coincidentally matching insertion order.
        let old = Workout(date: Date(timeIntervalSince1970: 100), title: "Old", durationMinutes: 0, sets: [
            ExerciseSet(exercise: "Squat", weight: 50, reps: 5, setNumber: 1, primaryMuscle: .quads),
            ExerciseSet(exercise: "Bench Press", weight: 40, reps: 5, setNumber: 2, primaryMuscle: .chest)
        ])
        let current = Workout(date: Date(timeIntervalSince1970: 200), title: "Current", durationMinutes: 0, sets: [
            ExerciseSet(exercise: "Squat", weight: 65, reps: 5, setNumber: 1, primaryMuscle: .quads),
            ExerciseSet(exercise: "Bench Press", weight: 50, reps: 5, setNumber: 2, primaryMuscle: .chest)
        ])

        let records = PerformanceEngine.personalRecords(in: current, history: [old])

        // Squat e1RM 50->75.83 (+30%), Bench Press e1RM 46.67->58.33 (+25%), volume 450->575
        // (+27.8%) are all within the 40% single-session PR guard, so all three PRs fire; the
        // returned order must be alphabetical, not insertion order.
        XCTAssertEqual(records, ["Bench Press estimated 1RM", "Squat estimated 1RM", "Workout volume"])
    }

    func testPersonalRecordsReturnsOneRowPerExerciseWhenMultipleSetsBreakRecord() {
        let old = Workout(date: Date(timeIntervalSince1970: 100), title: "Old", durationMinutes: 0, sets: [
            ExerciseSet(exercise: "Bench Press", weight: 50, reps: 5, setNumber: 1, primaryMuscle: .chest)
        ])
        let current = Workout(date: Date(timeIntervalSince1970: 200), title: "Current", durationMinutes: 0, sets: [
            ExerciseSet(exercise: "Bench Press", weight: 60, reps: 5, setNumber: 1, primaryMuscle: .chest),
            ExerciseSet(exercise: "Bench Press", weight: 65, reps: 5, setNumber: 2, primaryMuscle: .chest)
        ])

        let records = PerformanceEngine.personalRecords(in: current, history: [old])

        XCTAssertEqual(records.filter { $0 == "Bench Press estimated 1RM" }.count, 1)
    }

    func testEstimatedOneRMHistoryUsesBestSetPerWorkoutAndOrdersOldestFirst() {
        let old = Workout(date: Date(timeIntervalSince1970: 100), title: "Old", durationMinutes: 0)
        let oldLight = ExerciseSet(exercise: "Bench Press", weight: 40, reps: 5, setNumber: 1, primaryMuscle: .chest)
        let oldHeavy = ExerciseSet(exercise: "Bench Press", weight: 60, reps: 5, setNumber: 2, primaryMuscle: .chest)
        oldLight.workout = old
        oldHeavy.workout = old
        old.sets = [oldLight, oldHeavy]

        let current = Workout(date: Date(timeIntervalSince1970: 200), title: "Current", durationMinutes: 0)
        let currentSet = ExerciseSet(exercise: "Bench Press", weight: 70, reps: 5, setNumber: 1, primaryMuscle: .chest)
        currentSet.workout = current
        current.sets = [currentSet]

        let history = PerformanceEngine.estimated1RMHistory(for: "Bench Press", sets: [currentSet, oldLight, oldHeavy])

        XCTAssertEqual(history.count, 2)
        XCTAssertEqual(history[0], oldHeavy.estimated1RM, accuracy: 0.0001)
        XCTAssertEqual(history[1], currentSet.estimated1RM, accuracy: 0.0001)
    }


    func testEstimatedOneRMHistoryKeepsDistinctWorkoutsWithSameTimestamp() {
        let date = Date(timeIntervalSince1970: 100)
        let first = Workout(date: date, title: "First", durationMinutes: 0)
        let firstSet = ExerciseSet(exercise: "Bench Press", weight: 50, reps: 5, setNumber: 1, primaryMuscle: .chest)
        firstSet.workout = first
        first.sets = [firstSet]

        let second = Workout(date: date, title: "Second", durationMinutes: 0)
        let secondSet = ExerciseSet(exercise: "Bench Press", weight: 70, reps: 5, setNumber: 1, primaryMuscle: .chest)
        secondSet.workout = second
        second.sets = [secondSet]

        let history = PerformanceEngine.estimated1RMHistory(for: "Bench Press", sets: [firstSet, secondSet])

        XCTAssertEqual(history.count, 2)
        XCTAssertEqual(Set(history), Set([firstSet.estimated1RM, secondSet.estimated1RM]))
    }
}
