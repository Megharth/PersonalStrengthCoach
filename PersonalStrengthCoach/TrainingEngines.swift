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

/// Builds a `Workout` from a `Routine`'s target exercises/sets. The caller owns
/// inserting the returned workout (and its sets) into a `ModelContext` and saving —
/// this enum has no ModelContext side effects of its own.
struct PreviousSetPerformance {
    let sets: [ExerciseSet]
    let date: Date

    var isStale: Bool {
        date < Date.now.addingTimeInterval(-56 * 86_400)
    }
}

enum PreviousSetEngine {
    /// Returns the most recent workout containing this exercise, excluding the
    /// workout currently being edited. Matching uses the same normalized name
    /// as the rest of the training engines.
    static func mostRecentPerformance(
        for exercise: String,
        in workouts: [Workout],
        excluding excludedWorkout: Workout? = nil
    ) -> PreviousSetPerformance? {
        let normalized = ExerciseCatalog.normalize(exercise)
        let candidates = workouts.enumerated().compactMap { index, workout -> (index: Int, workout: Workout, sets: [ExerciseSet])? in
            guard workout !== excludedWorkout else { return nil }
            let sets = workout.sets
                .filter { $0.normalizedExercise == normalized }
                .sorted { lhs, rhs in
                    if lhs.setNumber != rhs.setNumber { return lhs.setNumber < rhs.setNumber }
                    if lhs.weight != rhs.weight { return lhs.weight < rhs.weight }
                    return lhs.reps < rhs.reps
                }
            guard !sets.isEmpty else { return nil }
            return (index, workout, sets)
        }
        guard let candidate = candidates.min(by: { lhs, rhs in
            if lhs.workout.date != rhs.workout.date { return lhs.workout.date > rhs.workout.date }
            return lhs.index < rhs.index
        }) else { return nil }
        return PreviousSetPerformance(sets: candidate.sets, date: candidate.workout.date)
    }
}

enum RoutineEngine {
    static func buildWorkout(from routine: Routine, date: Date = .now) -> Workout {
        let workout = Workout(date: date, title: routine.name, durationMinutes: 0)
        let orderedExercises = routine.exercises.sorted { $0.order < $1.order }
        for routineExercise in orderedExercises {
            let setCount = max(1, routineExercise.targetSets)
            for setNumber in 1...setCount {
                let set = ExerciseSet(
                    exercise: routineExercise.exercise,
                    normalizedExercise: routineExercise.normalizedExercise,
                    weight: routineExercise.targetWeight ?? 0,
                    reps: routineExercise.targetReps,
                    setNumber: setNumber,
                    primaryMuscle: routineExercise.primaryMuscle
                )
                set.workout = workout
                workout.sets.append(set)
            }
        }
        return workout
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
        clampedMinutes(Int(end.timeIntervalSince(start) / 60))
    }

    /// Clamps a minute count into the same `[1, 240]` range `elapsedMinutes`
    /// produces, so a manually edited duration can't fall outside the bounds an
    /// auto-captured one respects.
    static func clampedMinutes(_ minutes: Int) -> Int {
        max(1, min(240, minutes))
    }
}

enum WorkoutInProgressEngine {
    static let defaultRestSeconds = 90

    static func volume(of exercises: [LoggedExercise]) -> Double {
        exercises.reduce(0) { total, exercise in
            total + exercise.sets.reduce(0) { total, set in
                guard set.isCompleted else { return total }
                return total + set.weight * Double(set.reps)
            }
        }
    }

    static func elapsedSeconds(start: Date, now: Date) -> Int {
        max(0, Int(now.timeIntervalSince(start)))
    }

    static func remainingRestSeconds(endsAt: Date?, now: Date) -> Int? {
        guard let endsAt else { return nil }
        return max(0, Int(ceil(endsAt.timeIntervalSince(now))))
    }

    /// Treat unfinished workout state as a singleton. The newest update wins;
    /// any older rows are stray duplicates that callers should remove.
    static func resolveActiveSession(among sessions: [WorkoutInProgress]) -> (current: WorkoutInProgress?, strays: [WorkoutInProgress]) {
        let ordered = sessions.sorted {
            if $0.lastUpdated != $1.lastUpdated { return $0.lastUpdated > $1.lastUpdated }
            return ObjectIdentifier($0).hashValue < ObjectIdentifier($1).hashValue
        }
        return (ordered.first, Array(ordered.dropFirst()))
    }
}

struct PersistedDraftSet {
    let exercise: String
    let primaryMuscle: MuscleGroup
    let exerciseOrder: Int
    let weight: Double
    let reps: Int
    let setNumber: Int
    let isCompleted: Bool

    init(exercise: String, primaryMuscle: MuscleGroup, exerciseOrder: Int, weight: Double, reps: Int, setNumber: Int, isCompleted: Bool = false) {
        self.exercise = exercise
        self.primaryMuscle = primaryMuscle
        self.exerciseOrder = exerciseOrder
        self.weight = weight
        self.reps = reps
        self.setNumber = setNumber
        self.isCompleted = isCompleted
    }
}

extension WorkoutInProgressEngine {
    static func persistedSets(from exercises: [LoggedExercise]) -> [PersistedDraftSet] {
        exercises.enumerated().flatMap { exerciseIndex, exercise in
            exercise.sets.enumerated().map { setIndex, set in
                PersistedDraftSet(
                    exercise: exercise.name,
                    primaryMuscle: exercise.primaryMuscle,
                    exerciseOrder: exerciseIndex,
                    weight: set.weight,
                    reps: set.reps,
                    setNumber: setIndex + 1,
                    isCompleted: set.isCompleted
                )
            }
        }
    }

    static func draftExercises(from sets: [PersistedDraftSet]) -> [LoggedExercise] {
        Dictionary(grouping: sets, by: { $0.exerciseOrder })
            .sorted { $0.key < $1.key }
            .map { _, group in
                let ordered = group.sorted { $0.setNumber < $1.setNumber }
                guard let first = ordered.first else { return nil }
                return LoggedExercise(
                    name: first.exercise,
                    primaryMuscle: first.primaryMuscle,
                    sets: ordered.map {
                        EditableSet(weight: $0.weight, reps: $0.reps, isCompleted: $0.isCompleted)
                    }
                )
            }
            .compactMap { $0 }
    }
}
