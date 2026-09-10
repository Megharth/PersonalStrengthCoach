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
}
