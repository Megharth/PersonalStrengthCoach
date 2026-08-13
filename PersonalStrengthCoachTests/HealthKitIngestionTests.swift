import SwiftData
import XCTest
@testable import PersonalStrengthCoach

final class HealthKitIngestionTests: XCTestCase {
    func testAppSchemaV3ContainerBuildsWithMigrationPlan() throws {
        _ = try makeInMemoryContainer()
    }

    func testDailyRecoverySampleCountsDefaultToZero() throws {
        let container = try makeInMemoryContainer()
        let context = ModelContext(container)
        let recovery = DailyRecovery(date: .now, sleepHours: 7.5, hrv: 60, restingHeartRate: 58, weightKg: 82)
        context.insert(recovery)
        try context.save()

        let fetched = try XCTUnwrap(context.fetch(FetchDescriptor<DailyRecovery>()).first)
        XCTAssertEqual(fetched.sleepSampleCount, 0)
        XCTAssertEqual(fetched.hrvSampleCount, 0)
        XCTAssertEqual(fetched.restingHeartRateSampleCount, 0)
        XCTAssertEqual(fetched.bodyMassSampleCount, 0)
    }

    func testDailyRecoverySampleCountsPersist() throws {
        let container = try makeInMemoryContainer()
        let context = ModelContext(container)
        let recovery = DailyRecovery(
            date: .now,
            sleepHours: 8,
            hrv: 72,
            restingHeartRate: 52,
            weightKg: 84,
            sleepSampleCount: 4,
            hrvSampleCount: 8,
            restingHeartRateSampleCount: 2,
            bodyMassSampleCount: 1
        )
        context.insert(recovery)
        try context.save()

        let fetched = try XCTUnwrap(context.fetch(FetchDescriptor<DailyRecovery>()).first)
        XCTAssertEqual(fetched.sleepSampleCount, 4)
        XCTAssertEqual(fetched.hrvSampleCount, 8)
        XCTAssertEqual(fetched.restingHeartRateSampleCount, 2)
        XCTAssertEqual(fetched.bodyMassSampleCount, 1)
    }

    func testRecoveryExportIncludesSampleCounts() throws {
        let export = PersonalStrengthExport(
            schemaVersion: 3,
            exportedAt: Date(timeIntervalSince1970: 0),
            workouts: [],
            recovery: [RecoveryExport(
                date: Date(timeIntervalSince1970: 0),
                sleepHours: 7.5,
                hrv: 63,
                restingHeartRate: 54,
                weightKg: 80,
                sleepSampleCount: 3,
                hrvSampleCount: 7,
                restingHeartRateSampleCount: 2,
                bodyMassSampleCount: 1
            )],
            customExercises: [],
            routines: []
        )

        let data = try JSONEncoder().encode(export)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["schemaVersion"] as? Int, 3)
        let recovery = try XCTUnwrap((object["recovery"] as? [[String: Any]])?.first)
        XCTAssertEqual(recovery["sleepSampleCount"] as? Int, 3)
        XCTAssertEqual(recovery["hrvSampleCount"] as? Int, 7)
        XCTAssertEqual(recovery["restingHeartRateSampleCount"] as? Int, 2)
        XCTAssertEqual(recovery["bodyMassSampleCount"] as? Int, 1)
    }

    // MARK: - File-backed migration
    //
    // In-memory containers are always created fresh at V3, so the `.lightweight` stages in
    // AppMigrationPlan never actually run. These tests write a store under the *historical*
    // schema, close it, then reopen it at V3 through the migration plan — the one scenario
    // the frozen nested models in AppSchemaV1/V2 exist to keep safe.

    func testStoreCreatedUnderV1MigratesToV3AndPreservesData() throws {
        let url = try makeTemporaryStoreURL()
        defer { removeStore(at: url) }

        let recoveryDate = Date(timeIntervalSince1970: 1_700_000_000)
        do {
            let legacy = try ModelContainer(
                for: Schema(AppSchemaV1.models),
                configurations: ModelConfiguration(url: url)
            )
            let context = ModelContext(legacy)
            context.insert(AppSchemaV1.DailyRecovery(
                date: recoveryDate,
                sleepHours: 7.5,
                hrv: 61,
                restingHeartRate: 55,
                weightKg: 81
            ))
            try context.save()
        }

        let migrated = try ModelContainer(
            for: Schema(AppSchemaV3.models),
            migrationPlan: AppMigrationPlan.self,
            configurations: ModelConfiguration(url: url)
        )
        let context = ModelContext(migrated)
        let fetched = try XCTUnwrap(context.fetch(FetchDescriptor<DailyRecovery>()).first)

        XCTAssertEqual(fetched.sleepHours, 7.5)
        XCTAssertEqual(fetched.hrv, 61)
        XCTAssertEqual(fetched.restingHeartRate, 55)
        XCTAssertEqual(fetched.weightKg, 81)
        // Rows written before the sample-count fields existed backfill to zero, which is
        // indistinguishable from "no data" — pre-upgrade history reads as zero-confidence.
        XCTAssertEqual(fetched.sleepSampleCount, 0)
        XCTAssertEqual(fetched.hrvSampleCount, 0)
        XCTAssertEqual(fetched.restingHeartRateSampleCount, 0)
        XCTAssertEqual(fetched.bodyMassSampleCount, 0)
    }

    func testStoreCreatedUnderV2MigratesToV3AndPreservesRoutines() throws {
        let url = try makeTemporaryStoreURL()
        defer { removeStore(at: url) }

        do {
            let legacy = try ModelContainer(
                for: Schema(AppSchemaV2.models),
                configurations: ModelConfiguration(url: url)
            )
            let context = ModelContext(legacy)
            let routine = AppSchemaV2.Routine(name: "Push Day")
            let exercise = AppSchemaV2.RoutineExercise(
                exercise: "Bench Press",
                normalizedExercise: "Bench Press",
                primaryMuscleRaw: MuscleGroup.chest.rawValue,
                order: 0,
                targetSets: 3,
                targetReps: 8
            )
            exercise.routine = routine
            routine.exercises.append(exercise)
            context.insert(routine)
            try context.save()
        }

        let migrated = try ModelContainer(
            for: Schema(AppSchemaV3.models),
            migrationPlan: AppMigrationPlan.self,
            configurations: ModelConfiguration(url: url)
        )
        let context = ModelContext(migrated)
        let routine = try XCTUnwrap(context.fetch(FetchDescriptor<Routine>()).first)

        XCTAssertEqual(routine.name, "Push Day")
        XCTAssertEqual(routine.exercises.map(\.exercise), ["Bench Press"])
        XCTAssertEqual(routine.exercises.first?.targetSets, 3)
    }

    private func makeTemporaryStoreURL() throws -> URL {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("PersonalStrengthCoachTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("store.sqlite")
    }

    private func removeStore(at url: URL) {
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }

    private func makeInMemoryContainer() throws -> ModelContainer {
        try ModelContainer(
            for: Schema(AppSchemaV3.models),
            migrationPlan: AppMigrationPlan.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }
}
