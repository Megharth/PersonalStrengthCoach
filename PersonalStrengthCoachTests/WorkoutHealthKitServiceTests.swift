import HealthKit
import XCTest
@testable import PersonalStrengthCoach

@MainActor
final class WorkoutHealthKitServiceTests: XCTestCase {
    func testWorkoutHealthKitServiceInitialState() {
        let service = WorkoutHealthKitService()
        XCTAssertFalse(service.isActive)
        XCTAssertEqual(service.syncState, .idle)
    }

    func testWorkoutHealthKitServiceStaticTypes() {
        XCTAssertEqual(WorkoutHealthKitService.workoutType, HKObjectType.workoutType())
        XCTAssertEqual(WorkoutHealthKitService.heartRateType, HKObjectType.quantityType(forIdentifier: .heartRate))
        XCTAssertEqual(WorkoutHealthKitService.hrvType, HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN))
        XCTAssertEqual(WorkoutHealthKitService.activeEnergyType, HKObjectType.quantityType(forIdentifier: .activeEnergyBurned))
    }

    func testHealthKitAuthorizationTypesIncludesWorkoutShareAndHeartRateRead() {
        let types = HealthKitService.authorizationTypes()
        XCTAssertTrue(types.share.contains(HKObjectType.workoutType()))
        XCTAssertTrue(types.read.contains(HKObjectType.quantityType(forIdentifier: .heartRate)!))
        XCTAssertTrue(types.read.contains(HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN)!))
        XCTAssertTrue(types.read.contains(HKObjectType.quantityType(forIdentifier: .restingHeartRate)!))
        XCTAssertTrue(types.read.contains(HKObjectType.quantityType(forIdentifier: .bodyMass)!))
        XCTAssertTrue(types.read.contains(HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!))
        XCTAssertTrue(types.read.contains(HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!))
    }

    func testHealthKitAuthorizationTypesIncludesWorkoutRead() {
        let types = HealthKitService.authorizationTypes()
        XCTAssertTrue(types.read.contains(WorkoutHealthKitService.workoutType))
    }

    func testRetroactiveSyncResultEquality() {
        let result1 = WorkoutHealthKitService.RetroactiveSyncResult(heartRateSampleCount: 15, hrvSampleCount: 3, calories: 250)
        let result2 = WorkoutHealthKitService.RetroactiveSyncResult(heartRateSampleCount: 15, hrvSampleCount: 3, calories: 250)
        let result3 = WorkoutHealthKitService.RetroactiveSyncResult(heartRateSampleCount: 10, hrvSampleCount: 3, calories: 250)
        let result4 = WorkoutHealthKitService.RetroactiveSyncResult(heartRateSampleCount: 15, hrvSampleCount: 1, calories: 250)
        let result5 = WorkoutHealthKitService.RetroactiveSyncResult(heartRateSampleCount: 15, hrvSampleCount: 3, calories: 300)

        XCTAssertEqual(result1, result2)
        XCTAssertNotEqual(result1, result3)
        XCTAssertNotEqual(result1, result4)
        XCTAssertNotEqual(result1, result5)
    }

    func testWorkoutHealthKitServiceDiscardResetsState() {
        let service = WorkoutHealthKitService()
        service.discardWorkout()
        XCTAssertFalse(service.isActive)
        XCTAssertEqual(service.syncState, .idle)
    }

    func testSyncStateEquality() {
        XCTAssertEqual(WorkoutHealthKitService.SyncState.idle, .idle)
        XCTAssertEqual(WorkoutHealthKitService.SyncState.syncing, .syncing)
        XCTAssertEqual(WorkoutHealthKitService.SyncState.unavailable, .unavailable)
        XCTAssertEqual(WorkoutHealthKitService.SyncState.synced(heartRateSamples: 10, hrvSamples: 2), .synced(heartRateSamples: 10, hrvSamples: 2))
        XCTAssertNotEqual(WorkoutHealthKitService.SyncState.synced(heartRateSamples: 10, hrvSamples: 2), .synced(heartRateSamples: 5, hrvSamples: 2))
        XCTAssertEqual(WorkoutHealthKitService.SyncState.failed("error"), .failed("error"))
        XCTAssertNotEqual(WorkoutHealthKitService.SyncState.failed("error 1"), .failed("error 2"))
        XCTAssertNotEqual(WorkoutHealthKitService.SyncState.idle, .syncing)
    }

    func testSourceMetadataConstantsHaveExpectedValues() {
        XCTAssertEqual(WorkoutHealthKitService.sourceMetadataKey, "Source")
        XCTAssertEqual(WorkoutHealthKitService.sourceMetadataValue, "PersonalStrengthCoach")
    }

    func testFilterOwnedWorkoutsKeepsOnlyPersonalStrengthCoachSource() {
        let start = Date()
        let end = start.addingTimeInterval(3600)
        let key = WorkoutHealthKitService.sourceMetadataKey
        let value = WorkoutHealthKitService.sourceMetadataValue
        let ours = HKWorkout(activityType: .traditionalStrengthTraining, start: start, end: end,
                             duration: 3600, totalEnergyBurned: nil, totalDistance: nil,
                             metadata: [key: value])
        let theirs = HKWorkout(activityType: .traditionalStrengthTraining, start: start, end: end,
                               duration: 3600, totalEnergyBurned: nil, totalDistance: nil,
                               metadata: [key: "SomeOtherApp"])
        let noMetadata = HKWorkout(activityType: .traditionalStrengthTraining, start: start, end: end,
                                   duration: 3600, totalEnergyBurned: nil, totalDistance: nil,
                                   metadata: nil)

        let result = WorkoutHealthKitService.filterOwnedWorkouts([ours, theirs, noMetadata])

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.metadata?[key] as? String, value)
    }

    func testFilterOwnedWorkoutsReturnsEmptyWhenNoneMatch() {
        let start = Date()
        let end = start.addingTimeInterval(3600)
        let theirs = HKWorkout(activityType: .traditionalStrengthTraining, start: start, end: end,
                               duration: 3600, totalEnergyBurned: nil, totalDistance: nil,
                               metadata: [WorkoutHealthKitService.sourceMetadataKey: "SomeOtherApp"])

        let result = WorkoutHealthKitService.filterOwnedWorkouts([theirs])

        XCTAssertTrue(result.isEmpty)
    }

    func testFilterOwnedWorkoutsReturnsEmptyForEmptyInput() {
        XCTAssertTrue(WorkoutHealthKitService.filterOwnedWorkouts([]).isEmpty)
    }

    func testDeleteWorkoutIsNoOpUnderUITesting() async throws {
        let args = ProcessInfo.processInfo.arguments
        guard args.contains("-uitesting") else {
            throw XCTSkip("Only runs under the -uitesting flag")
        }
        try await WorkoutHealthKitService.deleteWorkout(startDate: Date(), durationMinutes: 60)
    }

    func testHKWorkoutSummaryEquality() {
        let uuid1 = UUID()
        let uuid2 = UUID()
        let start = Date(timeIntervalSince1970: 1_000_000)
        let end = start.addingTimeInterval(3600)
        let a = WorkoutHealthKitService.HKWorkoutSummary(uuid: uuid1, startDate: start, endDate: end, activityType: .traditionalStrengthTraining, sourceName: "Apple Watch")
        let b = WorkoutHealthKitService.HKWorkoutSummary(uuid: uuid1, startDate: start, endDate: end, activityType: .traditionalStrengthTraining, sourceName: "Apple Watch")
        let c = WorkoutHealthKitService.HKWorkoutSummary(uuid: uuid2, startDate: start, endDate: end, activityType: .traditionalStrengthTraining, sourceName: "Apple Watch")

        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }

    func testHKWorkoutSummaryDisplayNameStrengthTraining() {
        let summary = WorkoutHealthKitService.HKWorkoutSummary(
            uuid: UUID(),
            startDate: Date(timeIntervalSince1970: 1_000_000),
            endDate: Date(timeIntervalSince1970: 1_003_600),
            activityType: .traditionalStrengthTraining,
            sourceName: "Amazfit"
        )
        XCTAssertEqual(summary.activityName, "Traditional Strength Training")
        XCTAssertEqual(summary.sourceName, "Amazfit")
    }

    func testHKWorkoutSummaryDisplayNameFunctionalStrength() {
        let summary = WorkoutHealthKitService.HKWorkoutSummary(
            uuid: UUID(),
            startDate: Date(timeIntervalSince1970: 1_000_000),
            endDate: Date(timeIntervalSince1970: 1_003_600),
            activityType: .functionalStrengthTraining,
            sourceName: "Zepp"
        )
        XCTAssertEqual(summary.activityName, "Functional Strength Training")
    }

    func testHKWorkoutSummaryDurationMinutes() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        let end = start.addingTimeInterval(75 * 60)
        let summary = WorkoutHealthKitService.HKWorkoutSummary(
            uuid: UUID(),
            startDate: start,
            endDate: end,
            activityType: .traditionalStrengthTraining,
            sourceName: "Apple Watch"
        )
        XCTAssertEqual(summary.durationMinutes, 75)
    }

    func testHKWorkoutSummaryDurationRoundsDown() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        let end = start.addingTimeInterval(90 * 60 + 45)
        let summary = WorkoutHealthKitService.HKWorkoutSummary(
            uuid: UUID(),
            startDate: start,
            endDate: end,
            activityType: .traditionalStrengthTraining,
            sourceName: "Apple Watch"
        )
        XCTAssertEqual(summary.durationMinutes, 90)
    }

    func testBuildWorkoutSummariesFromHKWorkouts() {
        let start1 = Date(timeIntervalSince1970: 1_000_000)
        let end1 = start1.addingTimeInterval(3600)
        let start2 = Date(timeIntervalSince1970: 1_010_000)
        let end2 = start2.addingTimeInterval(2700)

        let hkWorkout1 = HKWorkout(activityType: .traditionalStrengthTraining,
                                   start: start1, end: end1, duration: 3600,
                                   totalEnergyBurned: nil, totalDistance: nil,
                                   metadata: nil)
        let hkWorkout2 = HKWorkout(activityType: .functionalStrengthTraining,
                                   start: start2, end: end2, duration: 2700,
                                   totalEnergyBurned: nil, totalDistance: nil,
                                   metadata: nil)

        let summaries = WorkoutHealthKitService.buildSummaries(from: [hkWorkout1, hkWorkout2])

        XCTAssertEqual(summaries.count, 2)
        XCTAssertEqual(summaries[0].startDate, start1)
        XCTAssertEqual(summaries[0].endDate, end1)
        XCTAssertEqual(summaries[0].activityType, .traditionalStrengthTraining)
        XCTAssertEqual(summaries[1].startDate, start2)
        XCTAssertEqual(summaries[1].activityType, .functionalStrengthTraining)
    }

    func testBuildWorkoutSummariesPreservesUUID() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        let end = start.addingTimeInterval(3600)
        let hkWorkout = HKWorkout(activityType: .traditionalStrengthTraining,
                                  start: start, end: end, duration: 3600,
                                  totalEnergyBurned: nil, totalDistance: nil,
                                  metadata: nil)

        let summaries = WorkoutHealthKitService.buildSummaries(from: [hkWorkout])

        XCTAssertEqual(summaries.count, 1)
        XCTAssertEqual(summaries[0].uuid, hkWorkout.uuid)
    }

    func testBuildWorkoutSummariesSourceNameFromSourceRevision() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        let end = start.addingTimeInterval(3600)
        let hkWorkout = HKWorkout(activityType: .traditionalStrengthTraining,
                                  start: start, end: end, duration: 3600,
                                  totalEnergyBurned: nil, totalDistance: nil,
                                  metadata: nil)

        let summaries = WorkoutHealthKitService.buildSummaries(from: [hkWorkout])

        XCTAssertFalse(summaries[0].sourceName.isEmpty)
    }

    func testBuildWorkoutSummariesEmptyInput() {
        let summaries = WorkoutHealthKitService.buildSummaries(from: [])
        XCTAssertTrue(summaries.isEmpty)
    }

    func testRequiresManualSelectionTrueWhenMultiple() {
        let s = [
            WorkoutHealthKitService.HKWorkoutSummary(uuid: UUID(), startDate: Date(), endDate: Date().addingTimeInterval(3600), activityType: .traditionalStrengthTraining, sourceName: "A"),
            WorkoutHealthKitService.HKWorkoutSummary(uuid: UUID(), startDate: Date(), endDate: Date().addingTimeInterval(3600), activityType: .traditionalStrengthTraining, sourceName: "B")
        ]
        XCTAssertTrue(WorkoutHealthKitService.requiresManualSelection(among: s))
    }

    func testRequiresManualSelectionFalseWhenZeroOrOne() {
        XCTAssertFalse(WorkoutHealthKitService.requiresManualSelection(among: []))
        let single = [WorkoutHealthKitService.HKWorkoutSummary(uuid: UUID(), startDate: Date(), endDate: Date().addingTimeInterval(3600), activityType: .traditionalStrengthTraining, sourceName: "A")]
        XCTAssertFalse(WorkoutHealthKitService.requiresManualSelection(among: single))
    }

    func testDefaultSelectionReturnsOnlyCandidate() {
        let single = [WorkoutHealthKitService.HKWorkoutSummary(uuid: UUID(), startDate: Date(), endDate: Date().addingTimeInterval(3600), activityType: .traditionalStrengthTraining, sourceName: "A")]
        let uuid = single[0].uuid
        XCTAssertEqual(WorkoutHealthKitService.defaultSelection(among: single), uuid)
    }

    func testDefaultSelectionReturnsNilWhenMultiple() {
        let multiple = [
            WorkoutHealthKitService.HKWorkoutSummary(uuid: UUID(), startDate: Date(), endDate: Date().addingTimeInterval(3600), activityType: .traditionalStrengthTraining, sourceName: "A"),
            WorkoutHealthKitService.HKWorkoutSummary(uuid: UUID(), startDate: Date(), endDate: Date().addingTimeInterval(3600), activityType: .traditionalStrengthTraining, sourceName: "B")
        ]
        XCTAssertNil(WorkoutHealthKitService.defaultSelection(among: multiple))
    }

    func testDefaultSelectionReturnsNilWhenEmpty() {
        XCTAssertNil(WorkoutHealthKitService.defaultSelection(among: []))
    }
}
