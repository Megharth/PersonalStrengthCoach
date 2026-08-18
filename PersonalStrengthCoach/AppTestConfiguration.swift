import Foundation
import SwiftData

enum AppTestScenario: String {
    case empty
    case history
    case recovery

    init?(arguments: [String]) {
        guard let valueIndex = arguments.firstIndex(of: "-ui-test-scenario"), arguments.indices.contains(valueIndex + 1) else {
            return nil
        }
        self.init(rawValue: arguments[valueIndex + 1])
    }
}

enum AppTestConfiguration {
    static let isUITesting = ProcessInfo.processInfo.arguments.contains("-ui-testing")
    static let scenario = AppTestScenario(arguments: ProcessInfo.processInfo.arguments) ?? .empty

    static func makeContainer() throws -> ModelContainer {
        if isUITesting {
            return try ModelContainer(
                for: Schema(AppSchemaV5.models),
                migrationPlan: AppMigrationPlan.self,
                configurations: ModelConfiguration(isStoredInMemoryOnly: true)
            )
        }
        return try ModelContainer(for: Schema(AppSchemaV5.models), migrationPlan: AppMigrationPlan.self)
    }
}
