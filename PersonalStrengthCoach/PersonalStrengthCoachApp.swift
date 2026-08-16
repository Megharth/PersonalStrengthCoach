import SwiftUI
import SwiftData

@main
struct PersonalStrengthCoachApp: App {
    private let container: ModelContainer

    init() {
        do {
            container = try ModelContainer(for: Schema(AppSchemaV5.models), migrationPlan: AppMigrationPlan.self)
        } catch {
            fatalError("Could not create the data store: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(.dark)
        }
        .modelContainer(container)
    }
}
