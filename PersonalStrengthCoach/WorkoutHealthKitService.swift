import Combine
import HealthKit
import SwiftData

@MainActor
final class WorkoutHealthKitService: ObservableObject {
    private static let store = HKHealthStore()

    private var builder: HKWorkoutBuilder?

    @Published var isActive = false
    @Published var syncState: SyncState = .idle

    enum SyncState: Equatable {
        case idle
        case syncing
        case synced(heartRateSamples: Int, hrvSamples: Int)
        case failed(String)
        case unavailable
    }

    struct RetroactiveSyncResult: Equatable {
        let heartRateSampleCount: Int
        let hrvSampleCount: Int
        let calories: Int?
    }

    static var workoutType: HKWorkoutType { HKObjectType.workoutType() }
    static var heartRateType: HKQuantityType { HKObjectType.quantityType(forIdentifier: .heartRate)! }
    static var hrvType: HKQuantityType { HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN)! }
    static var activeEnergyType: HKQuantityType { HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)! }
    static let sourceMetadataKey = "Source"
    static let sourceMetadataValue = "PersonalStrengthCoach"

    func startWorkout(at date: Date) async {
        guard !ProcessInfo.processInfo.arguments.contains("-uitesting") else {
            isActive = true
            syncState = .idle
            return
        }
        guard HKHealthStore.isHealthDataAvailable() else {
            syncState = .unavailable
            return
        }
        await HealthKitService.requestWorkoutWriteAuthorization()

        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .traditionalStrengthTraining
        configuration.locationType = .indoor

        let newBuilder = HKWorkoutBuilder(healthStore: Self.store, configuration: configuration, device: .local())
        do {
            try await newBuilder.beginCollection(at: date)
            builder = newBuilder
            isActive = true
            syncState = .idle
        } catch {
            syncState = .failed(error.localizedDescription)
        }
    }

    func finishIfNeeded(at endDate: Date) async {
        guard !ProcessInfo.processInfo.arguments.contains("-uitesting") else {
            builder = nil
            isActive = false
            return
        }
        guard let builder else { return }
        do {
            try await builder.endCollection(at: endDate)
            _ = try await builder.finishWorkout()
        } catch {
            syncState = .failed(error.localizedDescription)
        }
        self.builder = nil
        isActive = false
    }

    func discardWorkout() {
        builder = nil
        isActive = false
        syncState = .idle
    }

    func syncBiometrics(from start: Date, to end: Date) async {
        guard !ProcessInfo.processInfo.arguments.contains("-uitesting") else {
            syncState = .synced(heartRateSamples: 42, hrvSamples: 5)
            builder = nil
            isActive = false
            return
        }
        guard HKHealthStore.isHealthDataAvailable() else {
            syncState = .unavailable
            return
        }
        guard let builder else {
            syncState = .failed("No active Apple Health workout to attach samples to.")
            return
        }
        syncState = .syncing

        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)

        do {
            async let hrSamples: [HKQuantitySample] = querySamples(of: Self.heartRateType, predicate: predicate)
            async let hrvSamples: [HKQuantitySample] = querySamples(of: Self.hrvType, predicate: predicate)
            let (hr, hrv) = try await (hrSamples, hrvSamples)
            let allSamples: [HKSample] = hr + hrv
            if !allSamples.isEmpty {
                try await builder.addSamples(allSamples)
            }
            try await builder.endCollection(at: end)
            _ = try await builder.finishWorkout()
            self.builder = nil
            isActive = false
            syncState = .synced(heartRateSamples: hr.count, hrvSamples: hrv.count)
        } catch {
            syncState = .failed(error.localizedDescription)
        }
    }

    static func syncRetroactiveBiometrics(for workout: Workout, in context: ModelContext) async throws -> RetroactiveSyncResult {
        guard !ProcessInfo.processInfo.arguments.contains("-uitesting") else {
            if workout.calories == 0 {
                workout.calories = 320
                try? context.save()
            }
            return RetroactiveSyncResult(
                heartRateSampleCount: 42,
                hrvSampleCount: 5,
                calories: workout.calories > 0 ? workout.calories : 320
            )
        }
        guard HKHealthStore.isHealthDataAvailable() else {
            throw NSError(
                domain: "WorkoutHealthKitService",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Apple Health is not available on this device."]
            )
        }
        await HealthKitService.requestWorkoutWriteAuthorization()

        let startDate = workout.date
        let durationSeconds = TimeInterval(max(1, workout.durationMinutes) * 60)
        let endDate = startDate.addingTimeInterval(durationSeconds)
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)

        async let existingWorkouts: [HKWorkout] = querySamples(of: workoutType, predicate: predicate)
        async let hrSamples: [HKQuantitySample] = querySamples(of: heartRateType, predicate: predicate)
        async let hrvSamples: [HKQuantitySample] = querySamples(of: hrvType, predicate: predicate)
        async let calorieSamples: [HKQuantitySample] = querySamples(of: activeEnergyType, predicate: predicate)

        let (workouts, hr, hrv, calories) = try await (existingWorkouts, hrSamples, hrvSamples, calorieSamples)

        let targetWorkout: HKWorkout
        if let existing = workouts.first {
            targetWorkout = existing
        } else {
            let totalCalorieQuantity: HKQuantity? = calories.isEmpty ? nil : HKQuantity(
                unit: .kilocalorie(),
                doubleValue: calories.reduce(0.0) { $0 + $1.quantity.doubleValue(for: .kilocalorie()) }
            )
            let newWorkout = HKWorkout(
                activityType: .traditionalStrengthTraining,
                start: startDate,
                end: endDate,
                duration: durationSeconds,
                totalEnergyBurned: totalCalorieQuantity,
                totalDistance: nil,
                metadata: [Self.sourceMetadataKey: Self.sourceMetadataValue]
            )
            try await saveObject(newWorkout)
            targetWorkout = newWorkout
        }

        let allSamples: [HKSample] = hr + hrv + calories
        if !allSamples.isEmpty {
            try? await addSamples(allSamples, to: targetWorkout)
        }

        var updatedCalories: Int? = nil
        let calorieSum = calories.reduce(0.0) { $0 + $1.quantity.doubleValue(for: .kilocalorie()) }
        if calorieSum > 0 {
            let rounded = Int(calorieSum.rounded())
            if workout.calories == 0 {
                workout.calories = rounded
                try context.save()
            }
            updatedCalories = rounded
        } else if let energy = targetWorkout.totalEnergyBurned?.doubleValue(for: .kilocalorie()), energy > 0 {
            let rounded = Int(energy.rounded())
            if workout.calories == 0 {
                workout.calories = rounded
                try context.save()
            }
            updatedCalories = rounded
        }

        return RetroactiveSyncResult(
            heartRateSampleCount: hr.count,
            hrvSampleCount: hrv.count,
            calories: updatedCalories ?? (workout.calories > 0 ? workout.calories : nil)
        )
    }

    static func deleteWorkout(startDate: Date, durationMinutes: Int) async throws {
        guard !ProcessInfo.processInfo.arguments.contains("-uitesting") else { return }
        guard HKHealthStore.isHealthDataAvailable() else { return }
        await HealthKitService.requestWorkoutWriteAuthorization()

        let durationSeconds = TimeInterval(max(1, durationMinutes) * 60)
        let endDate = startDate.addingTimeInterval(durationSeconds)
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: [])

        let candidates: [HKWorkout] = try await querySamples(of: workoutType, predicate: predicate)
        let ours = Self.filterOwnedWorkouts(candidates)
        guard !ours.isEmpty else { return }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            store.delete(ours) { success, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: NSError(
                        domain: "WorkoutHealthKitService",
                        code: 4,
                        userInfo: [NSLocalizedDescriptionKey: "Failed to delete workout from Apple Health."]
                    ))
                }
            }
        }
    }

    static func filterOwnedWorkouts(_ candidates: [HKWorkout]) -> [HKWorkout] {
        candidates.filter { $0.metadata?[Self.sourceMetadataKey] as? String == Self.sourceMetadataValue }
    }

    private static func saveObject(_ object: HKObject) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            store.save(object) { success, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: NSError(
                        domain: "WorkoutHealthKitService",
                        code: 2,
                        userInfo: [NSLocalizedDescriptionKey: "Failed to save workout to Apple Health."]
                    ))
                }
            }
        }
    }

    private static func addSamples(_ samples: [HKSample], to workout: HKWorkout) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            store.add(samples, to: workout) { success, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: NSError(
                        domain: "WorkoutHealthKitService",
                        code: 3,
                        userInfo: [NSLocalizedDescriptionKey: "Failed to attach biometric samples to workout."]
                    ))
                }
            }
        }
    }

    private func querySamples<T: HKSample>(of type: HKSampleType, predicate: NSPredicate) async throws -> [T] {
        try await Self.querySamples(of: type, predicate: predicate)
    }

    private static func querySamples<T: HKSample>(of type: HKSampleType, predicate: NSPredicate) async throws -> [T] {
        try await withCheckedThrowingContinuation { continuation in
            Self.store.execute(HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: samples as? [T] ?? [])
                }
            })
        }
    }
}
