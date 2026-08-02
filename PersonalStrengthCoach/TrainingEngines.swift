import Foundation

struct ReadinessResult {
    let score: Int
    let color: String
    let factors: [String]
}

enum RecoveryEngine {
    static func readiness(today: DailyRecovery?, recent: [DailyRecovery], workouts: [Workout]) -> ReadinessResult {
        guard let today else { return ReadinessResult(score: 50, color: "Yellow", factors: ["Connect Apple Health to calculate readiness."]) }
        let baseline = recent.filter { $0.date < today.date }.prefix(14)
        let hrvBase = baseline.map(\.hrv).average ?? today.hrv
        let rhrBase = baseline.map(\.restingHeartRate).average ?? today.restingHeartRate
        let sleep = min(30, max(0, (today.sleepHours / 8) * 30))
        let hrv = min(30, max(0, (today.hrv / hrvBase) * 30))
        let rhr = min(20, max(0, (rhrBase / today.restingHeartRate) * 20))
        let yesterdayLoad = workouts.filter { Calendar.current.isDateInYesterday($0.date) }.reduce(0) { $0 + $1.volume }
        let load = yesterdayLoad > 8_000 ? 8.0 : yesterdayLoad > 4_000 ? 14.0 : 20.0
        let score = Int((sleep + hrv + rhr + load).rounded())
        let color = score >= 75 ? "Green" : score >= 55 ? "Yellow" : "Red"
        return ReadinessResult(score: score, color: color, factors: ["Sleep \(String(format: "%.1f", today.sleepHours))h", "HRV \(Int(today.hrv)) ms", "RHR \(Int(today.restingHeartRate)) bpm"])
    }

    static func muscleRecovery(_ muscle: MuscleGroup, workouts: [Workout], now: Date = .now) -> Int {
        let loads = workouts.flatMap(\.sets).filter { ExerciseCatalog.muscles(for: $0.exercise).contains(muscle) }
        guard let last = loads.compactMap(\.workout).map(\.date).max() else { return 100 }
        let hours = now.timeIntervalSince(last) / 3600
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
    static func personalRecords(in workout: Workout, history: [Workout]) -> [String] {
        let past = history.filter { $0.date < workout.date }
        var records: [String] = []
        for set in workout.sets {
            let previous = past.flatMap(\.sets).filter { $0.normalizedExercise == set.normalizedExercise }
            if set.estimated1RM > (previous.map(\.estimated1RM).max() ?? 0) { records.append("\(set.normalizedExercise) estimated 1RM") }
        }
        if workout.volume > (past.map(\.volume).max() ?? 0) { records.append("Workout volume") }
        return Array(Set(records))
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
