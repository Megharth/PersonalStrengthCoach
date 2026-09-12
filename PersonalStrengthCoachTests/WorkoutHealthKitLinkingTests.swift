import SwiftData
import XCTest
@testable import PersonalStrengthCoach

@MainActor
final class WorkoutHealthKitLinkingTests: XCTestCase {
    private func makeContext() throws -> ModelContext {
        let schema = Schema(AppSchemaV7.models)
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: configuration)
        return ModelContext(container)
    }

    func testNewWorkoutHasNoLinkedHealthKitWorkout() throws {
        let workout = Workout(title: "Push", durationMinutes: 45)
        XCTAssertNil(workout.linkedHealthKitWorkoutUUID)
    }

    func testLinkedHealthKitWorkoutUUIDPersistsAcrossFetches() throws {
        let context = try makeContext()
        let linkedUUID = UUID()
        let workout = Workout(date: Date(timeIntervalSince1970: 1_700_000_000), title: "Pull", durationMinutes: 60)
        workout.linkedHealthKitWorkoutUUID = linkedUUID
        context.insert(workout)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<Workout>())
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.linkedHealthKitWorkoutUUID, linkedUUID)
    }

    func testLinkedHealthKitWorkoutUUIDCanBeClearedAndSaved() throws {
        let context = try makeContext()
        let workout = Workout(title: "Legs", durationMinutes: 50)
        workout.linkedHealthKitWorkoutUUID = UUID()
        context.insert(workout)
        try context.save()

        workout.linkedHealthKitWorkoutUUID = nil
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<Workout>())
        XCTAssertNil(fetched.first?.linkedHealthKitWorkoutUUID)
    }

    func testLinkedHealthKitWorkoutUUIDIsIndependentPerWorkout() throws {
        let context = try makeContext()
        let firstUUID = UUID()
        let secondUUID = UUID()
        let first = Workout(date: Date(timeIntervalSince1970: 1_700_000_000), title: "Push", durationMinutes: 45)
        first.linkedHealthKitWorkoutUUID = firstUUID
        let second = Workout(date: Date(timeIntervalSince1970: 1_700_100_000), title: "Pull", durationMinutes: 55)
        second.linkedHealthKitWorkoutUUID = secondUUID
        context.insert(first)
        context.insert(second)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<Workout>(sortBy: [SortDescriptor(\.date)]))
        XCTAssertEqual(fetched.count, 2)
        XCTAssertEqual(fetched.first?.linkedHealthKitWorkoutUUID, firstUUID)
        XCTAssertEqual(fetched.last?.linkedHealthKitWorkoutUUID, secondUUID)
    }

    func testResolvedSelectionPrefersPersistedLinkWhenStillAvailable() {
        let persisted = UUID()
        let summaries = [
            WorkoutHealthKitService.HKWorkoutSummary(
                uuid: UUID(),
                startDate: Date(timeIntervalSince1970: 1_700_000_000),
                endDate: Date(timeIntervalSince1970: 1_700_003_600),
                activityType: .traditionalStrengthTraining,
                sourceName: "Apple Watch"
            ),
            WorkoutHealthKitService.HKWorkoutSummary(
                uuid: persisted,
                startDate: Date(timeIntervalSince1970: 1_700_007_200),
                endDate: Date(timeIntervalSince1970: 1_700_010_800),
                activityType: .mixedCardio,
                sourceName: "Amazfit"
            )
        ]

        XCTAssertEqual(
            WorkoutHealthKitService.resolvedSelection(persisted: persisted, among: summaries),
            persisted
        )
    }

    func testResolvedSelectionFallsBackToDefaultWhenPersistedLinkIsMissing() {
        let onlySummary = WorkoutHealthKitService.HKWorkoutSummary(
            uuid: UUID(),
            startDate: Date(timeIntervalSince1970: 1_700_000_000),
            endDate: Date(timeIntervalSince1970: 1_700_003_600),
            activityType: .traditionalStrengthTraining,
            sourceName: "Apple Watch"
        )

        XCTAssertEqual(
            WorkoutHealthKitService.resolvedSelection(persisted: UUID(), among: [onlySummary]),
            onlySummary.uuid
        )
    }

    func testResolvedSelectionReturnsNilWhenPersistedLinkIsMissingAndChoiceIsAmbiguous() {
        let summaries = [
            WorkoutHealthKitService.HKWorkoutSummary(
                uuid: UUID(),
                startDate: Date(timeIntervalSince1970: 1_700_000_000),
                endDate: Date(timeIntervalSince1970: 1_700_003_600),
                activityType: .traditionalStrengthTraining,
                sourceName: "Apple Watch"
            ),
            WorkoutHealthKitService.HKWorkoutSummary(
                uuid: UUID(),
                startDate: Date(timeIntervalSince1970: 1_700_007_200),
                endDate: Date(timeIntervalSince1970: 1_700_010_800),
                activityType: .mixedCardio,
                sourceName: "Amazfit"
            )
        ]

        XCTAssertNil(WorkoutHealthKitService.resolvedSelection(persisted: UUID(), among: summaries))
    }

    func testResolvedSelectionWithoutPersistedLinkMatchesDefaultSelection() {
        let summaries = [
            WorkoutHealthKitService.HKWorkoutSummary(
                uuid: UUID(),
                startDate: Date(timeIntervalSince1970: 1_700_000_000),
                endDate: Date(timeIntervalSince1970: 1_700_003_600),
                activityType: .traditionalStrengthTraining,
                sourceName: "Apple Watch"
            )
        ]

        XCTAssertEqual(
            WorkoutHealthKitService.resolvedSelection(persisted: nil, among: summaries),
            WorkoutHealthKitService.defaultSelection(among: summaries)
        )
    }

    func testResolvedSelectionReturnsNilForEmptySummaries() {
        XCTAssertNil(WorkoutHealthKitService.resolvedSelection(persisted: UUID(), among: []))
        XCTAssertNil(WorkoutHealthKitService.resolvedSelection(persisted: nil, among: []))
    }

    func testWorkoutExportCarriesLinkedHealthKitWorkoutUUID() throws {
        let linkedUUID = UUID()
        let export = WorkoutExport(
            date: Date(timeIntervalSince1970: 1_700_000_000),
            title: "Push",
            durationMinutes: 45,
            calories: 320,
            notes: "",
            linkedHealthKitWorkoutUUID: linkedUUID,
            sets: []
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(WorkoutExport.self, from: try encoder.encode(export))

        XCTAssertEqual(decoded.linkedHealthKitWorkoutUUID, linkedUUID)
    }

    func testWorkoutExportDecodesLegacyPayloadWithoutLinkedWorkout() throws {
        let legacy = """
        {
            "date": "2023-11-14T22:13:20Z",
            "title": "Push",
            "durationMinutes": 45,
            "calories": 320,
            "notes": "",
            "sets": []
        }
        """

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(WorkoutExport.self, from: Data(legacy.utf8))

        XCTAssertNil(decoded.linkedHealthKitWorkoutUUID)
        XCTAssertEqual(decoded.title, "Push")
    }

    func testSchemaV7IsCurrentAndIncludesAllModels() {
        XCTAssertEqual(AppSchemaV7.versionIdentifier, Schema.Version(7, 0, 0))
        XCTAssertEqual(AppSchemaV7.models.count, 8)
        XCTAssertTrue(AppMigrationPlan.schemas.contains { $0 == AppSchemaV7.self })
        XCTAssertEqual(AppMigrationPlan.stages.count, AppMigrationPlan.schemas.count - 1)
    }
}
