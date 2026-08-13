import Foundation
import SwiftData

enum MuscleGroup: String, CaseIterable, Codable, Identifiable {
    case chest = "Chest", upperBack = "Upper Back", lats = "Lats", rearDelts = "Rear Delts"
    case frontDelts = "Front Delts", sideDelts = "Side Delts", quads = "Quads", hamstrings = "Hamstrings"
    case glutes = "Glutes", calves = "Calves", biceps = "Biceps", triceps = "Triceps", forearms = "Forearms", core = "Core"
    var id: String { rawValue }
}

@Model
final class Workout {
    var date: Date
    var title: String
    var durationMinutes: Int
    var calories: Int
    var notes: String
    @Relationship(deleteRule: .cascade, inverse: \ExerciseSet.workout) var sets: [ExerciseSet]

    init(date: Date = .now, title: String, durationMinutes: Int, calories: Int = 0, notes: String = "", sets: [ExerciseSet] = []) {
        self.date = date; self.title = title; self.durationMinutes = durationMinutes
        self.calories = calories; self.notes = notes; self.sets = sets
    }
    var volume: Double { sets.reduce(0) { $0 + $1.weight * Double($1.reps) } }
}

@Model
final class ExerciseSet {
    var exercise: String
    var normalizedExercise: String
    var weight: Double
    var reps: Int
    var setNumber: Int
    var primaryMuscleRaw: String
    var workout: Workout?

    init(exercise: String, normalizedExercise: String? = nil, weight: Double, reps: Int, setNumber: Int, primaryMuscle: MuscleGroup) {
        self.exercise = exercise; self.normalizedExercise = normalizedExercise ?? ExerciseCatalog.normalize(exercise)
        self.weight = weight; self.reps = reps; self.setNumber = setNumber; self.primaryMuscleRaw = primaryMuscle.rawValue
    }
    var primaryMuscle: MuscleGroup { MuscleGroup(rawValue: primaryMuscleRaw) ?? .core }
    var estimated1RM: Double { weight * (1 + Double(reps) / 30) }
}

@Model
final class DailyRecovery {
    var date: Date
    var sleepHours: Double
    var hrv: Double
    var restingHeartRate: Double
    var weightKg: Double
    var sleepSampleCount: Int = 0
    var hrvSampleCount: Int = 0
    var restingHeartRateSampleCount: Int = 0
    var bodyMassSampleCount: Int = 0

    init(
        date: Date,
        sleepHours: Double,
        hrv: Double,
        restingHeartRate: Double,
        weightKg: Double,
        sleepSampleCount: Int = 0,
        hrvSampleCount: Int = 0,
        restingHeartRateSampleCount: Int = 0,
        bodyMassSampleCount: Int = 0
    ) {
        self.date = date
        self.sleepHours = sleepHours
        self.hrv = hrv
        self.restingHeartRate = restingHeartRate
        self.weightKg = weightKg
        self.sleepSampleCount = sleepSampleCount
        self.hrvSampleCount = hrvSampleCount
        self.restingHeartRateSampleCount = restingHeartRateSampleCount
        self.bodyMassSampleCount = bodyMassSampleCount
    }
}

@Model
final class Routine {
    var name: String
    var createdAt: Date
    @Relationship(deleteRule: .cascade, inverse: \RoutineExercise.routine) var exercises: [RoutineExercise]

    init(name: String, createdAt: Date = .now, exercises: [RoutineExercise] = []) {
        self.name = name; self.createdAt = createdAt; self.exercises = exercises
    }
}

@Model
final class RoutineExercise {
    var exercise: String
    var normalizedExercise: String
    var primaryMuscleRaw: String
    var order: Int
    var targetSets: Int
    var targetReps: Int
    var targetWeight: Double?
    var routine: Routine?

    init(exercise: String, normalizedExercise: String? = nil, primaryMuscle: MuscleGroup, order: Int, targetSets: Int, targetReps: Int, targetWeight: Double? = nil) {
        self.exercise = exercise; self.normalizedExercise = normalizedExercise ?? ExerciseCatalog.normalize(exercise)
        self.primaryMuscleRaw = primaryMuscle.rawValue; self.order = order
        self.targetSets = targetSets; self.targetReps = targetReps; self.targetWeight = targetWeight
    }
    var primaryMuscle: MuscleGroup { MuscleGroup(rawValue: primaryMuscleRaw) ?? .core }
}

@Model
final class CustomExercise {
    var name: String
    var primaryMuscleRaw: String
    var createdAt: Date

    init(name: String, primaryMuscle: MuscleGroup, createdAt: Date = .now) {
        self.name = name
        self.primaryMuscleRaw = primaryMuscle.rawValue
        self.createdAt = createdAt
    }
    var primaryMuscle: MuscleGroup { MuscleGroup(rawValue: primaryMuscleRaw) ?? .core }
}

enum ExerciseCatalog {
    static func normalize(_ name: String) -> String {
        let key = name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let aliases = ["barbell bench press": "Bench Press", "flat bench": "Bench Press", "back squat": "Squat", "conventional deadlift": "Deadlift"]
        return aliases[key] ?? name.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    static func muscles(for exercise: String) -> [MuscleGroup] {
        switch normalize(exercise).lowercased() {
        case let name where name.contains("squat") || name.contains("leg press") || name.contains("leg extension") || name.contains("lunge"): return [.quads, .glutes, .hamstrings]
        case let name where name.contains("deadlift"): return [.hamstrings, .glutes, .upperBack]
        case let name where name.contains("booty builder") || name.contains("hip thrust"): return [.glutes, .hamstrings]
        case let name where name.contains("row"): return [.upperBack, .lats, .biceps]
        case let name where name.contains("bench") || name.contains("press"): return [.chest, .frontDelts, .triceps]
        default: return [.core]
        }
    }
}

struct LibraryExercise: Identifiable, Hashable {
    let name: String
    let primaryMuscle: MuscleGroup
    var id: String { name }
}

enum ExerciseLibrary {
    static let seeded: [LibraryExercise] = [
        .init(name: "Barbell Bench Press", primaryMuscle: .chest),
        .init(name: "Incline Dumbbell Press", primaryMuscle: .chest),
        .init(name: "Cable Fly", primaryMuscle: .chest),
        .init(name: "Overhead Press", primaryMuscle: .frontDelts),
        .init(name: "Dumbbell Lateral Raise", primaryMuscle: .sideDelts),
        .init(name: "Face Pull", primaryMuscle: .rearDelts),
        .init(name: "Barbell Row", primaryMuscle: .upperBack),
        .init(name: "Lat Pulldown", primaryMuscle: .lats),
        .init(name: "Pull Up", primaryMuscle: .lats),
        .init(name: "Back Squat", primaryMuscle: .quads),
        .init(name: "Leg Press", primaryMuscle: .quads),
        .init(name: "Romanian Deadlift", primaryMuscle: .hamstrings),
        .init(name: "Conventional Deadlift", primaryMuscle: .hamstrings),
        .init(name: "Hip Thrust", primaryMuscle: .glutes),
        .init(name: "Standing Calf Raise", primaryMuscle: .calves),
        .init(name: "Barbell Curl", primaryMuscle: .biceps),
        .init(name: "Triceps Pushdown", primaryMuscle: .triceps),
        .init(name: "Cable Crunch", primaryMuscle: .core)
    ]
}
