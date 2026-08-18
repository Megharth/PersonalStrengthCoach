import SwiftUI
import SwiftData

@main
struct PersonalStrengthCoachApp: App {
    private let container: ModelContainer

    init() {
        do {
            container = try AppTestConfiguration.makeContainer()
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
