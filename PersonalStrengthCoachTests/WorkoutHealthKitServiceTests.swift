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
}
