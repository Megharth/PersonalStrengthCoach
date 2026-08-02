import SwiftUI
import SwiftData

@main
struct PersonalStrengthCoachApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(.dark)
        }
        .modelContainer(for: [Workout.self, ExerciseSet.self, DailyRecovery.self, CustomExercise.self])
    }
}
