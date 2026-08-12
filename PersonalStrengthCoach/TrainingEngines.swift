import Foundation

enum ReadinessConfidence { case low, medium, high }

struct ReadinessResult {
    let score: Int
    let color: String
    let factors: [String]
    let confidence: ReadinessConfidence
}

enum RecoveryEngine {
    static func readiness(today: DailyRecovery?, recent: [DailyRecovery], workouts: [Workout], now: Date = .now) -> ReadinessResult {
        guard let today else { return ReadinessResult(score: 50, color: "Yellow", factors: ["Connect Apple Health to calculate readiness."], confidence: .low) }
        let dayDiff = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: today.date), to: Calendar.current.startOfDay(for: now)).day ?? Int.max
        let isStale = dayDiff > 1 || dayDiff < 0
        if isStale {
            return ReadinessResult(score: 50, color: "Yellow", factors: ["Your recovery data looks stale — sync Apple Health to refresh."], confidence: .low)
        }
        let baseline = recent.filter { $0.date < today.date }.prefix(14)
        let validBaseline = baseline.filter { $0.hrv > 0 && $0.restingHeartRate > 0 }
        let hrvBaselineAvg = validBaseline.map(\.hrv).average
        let rhrBaselineAvg = validBaseline.map(\.restingHeartRate).average
        let sleep = min(30, max(0, (today.sleepHours / 8) * 30))
        let hrv: Double = (today.hrv > 0 && hrvBaselineAvg != nil) ? min(30, max(0, (today.hrv / hrvBaselineAvg!) * 30)) : 15
        let rhr: Double = (today.restingHeartRate > 0 && rhrBaselineAvg != nil) ? min(20, max(0, (rhrBaselineAvg! / today.restingHeartRate) * 20)) : 10
        let yesterdayLoad = workouts.filter { Calendar.current.isDateInYesterday($0.date) }.reduce(0) { $0 + $1.volume }
        let load = yesterdayLoad > 8_000 ? 8.0 : yesterdayLoad > 4_000 ? 14.0 : 20.0
        let score = Int((sleep + hrv + rhr + load).rounded())
        let color = score >= 75 ? "Green" : score >= 55 ? "Yellow" : "Red"
        let todayValid = today.hrv > 0 && today.restingHeartRate > 0
        let confidence: ReadinessConfidence
        switch validBaseline.count {
        case ..<3: confidence = .low
        case 3..<7: confidence = .medium
        default: confidence = todayValid ? .high : .medium
        }
        return ReadinessResult(score: score, color: color, factors: ["Sleep \(String(format: "%.1f", today.sleepHours))h", "HRV \(Int(today.hrv)) ms", "RHR \(Int(today.restingHeartRate)) bpm"], confidence: confidence)
    }

    static func muscleRecovery(_ muscle: MuscleGroup, workouts: [Workout], now: Date = .now) -> Int {
        let loads = workouts.flatMap(\.sets).filter { ExerciseCatalog.muscles(for: $0.exercise).contains(muscle) }
        guard let last = loads.compactMap(\.workout).map(\.date).max() else { return 100 }
        let hours = max(0, now.timeIntervalSince(last) / 3600)
        return min(100, Int(hours / 72 * 100))
    }
}

enum PerformanceEngine {
    static func weeklyVolume(_ workouts: [Workout], now: Date = .now) -> Double {
        let start = Calendar.current.date(byAdding: .day, value: -7, to: now)!
        return workouts.filter { $0.date >= start }.reduce(0) { $0 + $1.volume }
    }
    static func estimated1RM(for exercise: String, sets: [ExerciseSet]) -> Double {
        sets.filter { $0.normalizedExercise == ExerciseCatalog.normalize(exercise) }.map(\.estimated1RM).max() ?? 0
    }

    /// Best estimated 1RM for each recorded workout containing the exercise,
    /// ordered oldest to newest. Multiple sets in one workout produce one point.
    static func estimated1RMHistory(for exercise: String, sets: [ExerciseSet]) -> [Double] {
        let normalized = ExerciseCatalog.normalize(exercise)
        let relevant = sets.filter {
            $0.normalizedExercise == normalized && $0.estimated1RM.isFinite && $0.estimated1RM > 0
        }
        let linkedSets = relevant.compactMap { set -> (workout: Workout, set: ExerciseSet)? in
            guard let workout = set.workout else { return nil }
            return (workout, set)
        }
        let sessions = Dictionary(grouping: linkedSets) { ObjectIdentifier($0.workout) }
        return sessions.values.compactMap { session -> (date: Date, best: Double)? in
            guard let workout = session.first?.workout,
                  let best = session.map({ $0.set.estimated1RM }).max() else { return nil }
            return (workout.date, best)
        }
        .sorted { $0.date < $1.date }
        .map(\.best)
    }
    static func personalRecords(in workout: Workout, history: [Workout]) -> [String] {
        let past = history.filter { $0.date < workout.date }
        var records: [String] = []
        for set in workout.sets {
            let previous = past.flatMap(\.sets).filter { $0.normalizedExercise == set.normalizedExercise }
            let previousBest = previous.map(\.estimated1RM).max()
            if isAllowedPR(new: set.estimated1RM, previousBest: previousBest) { records.append("\(set.normalizedExercise) estimated 1RM") }
        }
        let previousBestVolume = past.map(\.volume).max()
        if isAllowedPR(new: workout.volume, previousBest: previousBestVolume) { records.append("Workout volume") }
        return Array(Set(records)).sorted()
    }

    private static func isAllowedPR(new: Double, previousBest: Double?) -> Bool {
        guard new > 0 else { return false }
        guard let previousBest, previousBest > 0 else { return true }
        guard new > previousBest else { return false }
        return new <= previousBest * 1.4 + 1e-6
    }

    /// The exercise (by normalizedExercise name) with the most logged sets across
    /// all workouts. Returns nil if there are no sets at all. Ties are broken
    /// alphabetically (ascending) on the normalized exercise name, for determinism.
    /// Best estimated-1RM per trailing weekly window for the given exercise,
    /// oldest week first, most recent week last, using half-open [start, end)
    /// windows ending exactly at `now`. A week with zero sets for that exercise
    /// is OMITTED from the result (not zero-filled).
    static func weeklyEstimated1RM(for exercise: String, workouts: [Workout], weeks: Int = 7, now: Date = .now) -> [Double] {
        let normalized = ExerciseCatalog.normalize(exercise)
        let sets = workouts.flatMap { workout in workout.sets.map { (date: workout.date, set: $0) } }
            .filter { $0.set.normalizedExercise == normalized && $0.set.estimated1RM.isFinite && $0.set.estimated1RM > 0 }
        guard weeks > 0 else { return [] }
        var results: [Double] = []
        for i in 1...weeks {
            let start = Calendar.current.date(byAdding: .day, value: -(weeks - i + 1) * 7, to: now) ?? now
            let end = Calendar.current.date(byAdding: .day, value: -(weeks - i) * 7, to: now) ?? now
            let best = sets.filter { $0.date >= start && $0.date < end }.map { $0.set.estimated1RM }.max()
            if let best { results.append(best) }
        }
        return results
    }


    /// Chooses the exercise with the strongest usable recent trend. Preference is
    /// given to more populated weekly histories, then more valid sets, then name.
    static func strengthTrend(in workouts: [Workout], weeks: Int = 7, now: Date = .now) -> (exercise: String, points: [Double])? {
        guard weeks > 0,
              let start = Calendar.current.date(byAdding: .day, value: -weeks * 7, to: now) else { return nil }
        let recentSets = workouts.filter { $0.date >= start && $0.date < now }.flatMap(\.sets)
            .filter { $0.estimated1RM.isFinite && $0.estimated1RM > 0 }
        let candidates = Dictionary(grouping: recentSets, by: \.normalizedExercise)
        return candidates.compactMap { exercise, sets -> (exercise: String, points: [Double], setCount: Int)? in
            let points = weeklyEstimated1RM(for: exercise, workouts: workouts, weeks: weeks, now: now)
            guard points.count > 1 else { return nil }
            return (exercise, points, sets.count)
        }
        .max { lhs, rhs in
            if lhs.points.count != rhs.points.count { return lhs.points.count < rhs.points.count }
            if lhs.setCount != rhs.setCount { return lhs.setCount < rhs.setCount }
            return lhs.exercise > rhs.exercise
        }
        .map { ($0.exercise, $0.points) }
    }
}

enum RecommendationEngine {
    static func nextWorkout(workouts: [Workout]) -> (title: String, detail: String) {
        let chest = RecoveryEngine.muscleRecovery(.chest, workouts: workouts)
        let quads = RecoveryEngine.muscleRecovery(.quads, workouts: workouts)
        let back = RecoveryEngine.muscleRecovery(.upperBack, workouts: workouts)
        if chest >= 70 && back >= 70 { return ("Push Day", "Chest and shoulders are recovered and ready for pressing.") }
        if back >= 70 { return ("Pull Day", "Your back is recovered and has the most room for quality work.") }
        if quads >= 70 { return ("Leg Day", "Lower body recovery supports a productive session.") }
        return ("Active Recovery", "Give your trained muscles more time before the next hard session.")
    }
}

private extension Array where Element == Double { var average: Double? { isEmpty ? nil : reduce(0, +) / Double(count) } }

/// Pure helper for turning a workout session's start/end timestamps into a
/// stored `durationMinutes` value.
enum WorkoutTimerEngine {
    /// Elapsed minutes between start and end, rounded down to the nearest whole
    /// minute, floored at 1 minute (a workout logged in under a minute still counts
    /// as having happened) and capped at 240 minutes (guards against a sheet left
    /// open/backgrounded for hours before Save is tapped).
    static func elapsedMinutes(start: Date, end: Date) -> Int {
        max(1, min(240, Int(end.timeIntervalSince(start) / 60)))
    }
}
