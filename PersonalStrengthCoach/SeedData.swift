import Foundation
import SwiftData

enum SeedData {
    static func loadIfNeeded(context: ModelContext, workouts: [Workout]) {
        guard workouts.isEmpty else { return }
        let calendar = Calendar.current
        for offset in 0..<15 {
            let date = calendar.date(byAdding: .day, value: -offset, to: .now)!
            context.insert(DailyRecovery(date: date, sleepHours: offset == 0 ? 7.6 : 6.8 + Double(offset % 4) * 0.25, hrv: offset == 0 ? 72 : 66 + Double(offset % 5) * 2, restingHeartRate: offset == 0 ? 52 : 51 + Double(offset % 4), weightKg: 79.4))
        }
        let workouts = [makeWorkout(daysAgo: 1, title: "Pull Day", sets: [("Barbell Row", 90, 8, .upperBack), ("Lat Pulldown", 70, 10, .lats)]), makeWorkout(daysAgo: 3, title: "Leg Day", sets: [("Back Squat", 120, 6, .quads), ("Romanian Deadlift", 100, 8, .hamstrings)]), makeWorkout(daysAgo: 5, title: "Push Day", sets: [("Barbell Bench Press", 100, 6, .chest), ("Overhead Press", 55, 8, .frontDelts)]), makeWorkout(daysAgo: 8, title: "Pull Day", sets: [("Barbell Row", 87.5, 8, .upperBack), ("Lat Pulldown", 67.5, 10, .lats)])]
        workouts.forEach(context.insert)
    }

    static func loadUITestScenario(_ scenario: AppTestScenario, context: ModelContext) {
        switch scenario {
        case .empty:
            break
        case .history:
            insertRecoveryFixtures(context: context)
            insertHistoryFixtures(context: context)
        case .recovery:
            insertRecoveryFixtures(context: context)
        }
        try? context.save()
    }

    private static func insertRecoveryFixtures(context: ModelContext) {
        let calendar = Calendar(identifier: .gregorian)
        let referenceDate = calendar.date(from: DateComponents(timeZone: TimeZone(secondsFromGMT: 0), year: 2026, month: 8, day: 17))!
        for offset in 0..<7 {
            let date = calendar.date(byAdding: .day, value: -offset, to: referenceDate)!
            context.insert(DailyRecovery(date: date, sleepHours: offset == 0 ? 8 : 7, hrv: offset == 0 ? 75 : 68, restingHeartRate: offset == 0 ? 50 : 53, weightKg: 80))
        }
    }

    private static func insertHistoryFixtures(context: ModelContext) {
        let calendar = Calendar(identifier: .gregorian)
        let referenceDate = calendar.date(from: DateComponents(timeZone: TimeZone(secondsFromGMT: 0), year: 2026, month: 8, day: 17))!
        let fixtures = [
            ("Fixture Pull", 1, [("Barbell Row", 90.0, 8, MuscleGroup.upperBack), ("Lat Pulldown", 70.0, 10, MuscleGroup.lats)]),
            ("Fixture Legs", 3, [("Back Squat", 120.0, 6, MuscleGroup.quads), ("Romanian Deadlift", 100.0, 8, MuscleGroup.hamstrings)])
        ]
        for fixture in fixtures {
            let workout = Workout(date: calendar.date(byAdding: .day, value: -fixture.1, to: referenceDate)!, title: fixture.0, durationMinutes: 60, calories: 400)
            workout.sets = fixture.2.enumerated().flatMap { index, value in
                (1...2).map { number in
                    ExerciseSet(exercise: value.0, weight: value.1, reps: value.2, setNumber: index * 2 + number, primaryMuscle: value.3)
                }
            }
            context.insert(workout)
        }
    }

    private static func makeWorkout(daysAgo: Int, title: String, sets: [(String, Double, Int, MuscleGroup)]) -> Workout {
        let workout = Workout(date: Calendar.current.date(byAdding: .day, value: -daysAgo, to: .now)!, title: title, durationMinutes: 68, calories: 410)
        workout.sets = sets.enumerated().flatMap { index, value in (1...3).map { number in ExerciseSet(exercise: value.0, weight: value.1, reps: value.2 - (number == 3 ? 1 : 0), setNumber: index * 3 + number, primaryMuscle: value.3) } }
        return workout
    }
}
