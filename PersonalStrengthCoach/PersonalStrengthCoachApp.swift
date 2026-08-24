import SwiftUI
import SwiftData

@main
struct PersonalStrengthCoachApp: App {
    private let container: ModelContainer

    init() {
        do {
            if ProcessInfo.processInfo.arguments.contains("-uitesting") {
                // UI tests need a pristine, deterministic store on every launch —
                // an in-memory store means each run starts empty and gets
                // reseeded, with no leftover drafts/state from prior runs. Reset
                // AppStorage-backed preferences too, so a unit toggled during
                // manual testing on the same simulator can't leak into a run.
                UserDefaults.standard.removeObject(forKey: "weightUnit")
                let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
                container = try ModelContainer(for: Schema(AppSchemaV5.models), configurations: configuration)
            } else {
                container = try ModelContainer(for: Schema(AppSchemaV5.models), migrationPlan: AppMigrationPlan.self)
            }
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
