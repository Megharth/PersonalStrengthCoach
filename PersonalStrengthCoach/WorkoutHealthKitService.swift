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

    /// A lightweight, `Sendable`-friendly projection of an `HKWorkout` used to
    /// let the user pick which candidate workout to link, instead of the
    /// service silently guessing via `.first` on a time-window query.
    struct HKWorkoutSummary: Identifiable, Equatable {
        let uuid: UUID
        let startDate: Date
        let endDate: Date
        let activityType: HKWorkoutActivityType
        let sourceName: String

        var id: UUID { uuid }

        var durationMinutes: Int {
            Int(endDate.timeIntervalSince(startDate) / 60)
        }

        var activityName: String {
            switch activityType {
            case .traditionalStrengthTraining: return "Traditional Strength Training"
            case .functionalStrengthTraining: return "Functional Strength Training"
            case .coreTraining: return "Core Training"
            case .crossTraining: return "Cross Training"
            case .highIntensityIntervalTraining: return "HIIT"
            case .running: return "Running"
            case .walking: return "Walking"
            case .cycling: return "Cycling"
            case .yoga: return "Yoga"
            case .other: return "Other Workout"
            default: return "Workout"
            }
        }
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

    /// Attaches biometric samples to the in-flight builder. When `linking` is
    /// supplied the user has explicitly chosen which Apple Health workout this
    /// session corresponds to, so that workout's own window is authoritative
    /// rather than the app's locally-timed session bounds.
    func syncBiometrics(from start: Date, to end: Date, linking summary: HKWorkoutSummary? = nil) async {
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

        let windowStart = summary?.startDate ?? start
        let windowEnd = summary?.endDate ?? end
        let predicate = HKQuery.predicateForSamples(withStart: windowStart, end: windowEnd, options: .strictStartDate)

        do {
            async let hrSamples: [HKQuantitySample] = querySamples(of: Self.heartRateType, predicate: predicate)
            async let hrvSamples: [HKQuantitySample] = querySamples(of: Self.hrvType, predicate: predicate)
            let (hr, hrv) = try await (hrSamples, hrvSamples)
            let allSamples: [HKSample] = hr + hrv
            if !allSamples.isEmpty {
                try await builder.addSamples(allSamples)
            }
            try await builder.endCollection(at: windowEnd)
            _ = try await builder.finishWorkout()
            self.builder = nil
            isActive = false
            syncState = .synced(heartRateSamples: hr.count, hrvSamples: hrv.count)
        } catch {
            syncState = .failed(error.localizedDescription)
        }
    }

    /// Projects `HKWorkout` objects into pickable `HKWorkoutSummary` values.
    /// Pure and deterministic so it can be unit-tested without a live Health store.
    static func buildSummaries(from workouts: [HKWorkout]) -> [HKWorkoutSummary] {
        workouts.map { workout in
            let source = workout.sourceRevision.source.name.trimmingCharacters(in: .whitespacesAndNewlines)
            return HKWorkoutSummary(
                uuid: workout.uuid,
                startDate: workout.startDate,
                endDate: workout.endDate,
                activityType: workout.workoutActivityType,
                sourceName: source.isEmpty ? "Apple Health" : source
            )
        }
        .sorted { $0.startDate < $1.startDate }
    }

    /// Whether the candidate list is ambiguous enough to require the user to
    /// pick one, rather than syncing could proceed unattended. Pure so the two
    /// call sites (new-workout sync sheet, retroactive workout-detail sync)
    /// share one rule instead of re-deriving it from `.count` independently.
    static func requiresManualSelection(among summaries: [HKWorkoutSummary]) -> Bool {
        summaries.count > 1
    }

    /// The workout that should be pre-selected without user input: the sole
    /// candidate when exactly one exists, otherwise nil (either nothing was
    /// found, or more than one candidate needs an explicit choice).
    static func defaultSelection(among summaries: [HKWorkoutSummary]) -> UUID? {
        guard summaries.count == 1 else { return nil }
        return summaries[0].uuid
    }

    /// The selection to restore when a workout's Health-sync UI appears. A
    /// previously saved link wins whenever that workout is still among the
    /// day's candidates; otherwise this falls back to `defaultSelection`, so a
    /// link pointing at a deleted Health workout degrades to the unambiguous
    /// single-candidate case rather than showing a phantom selection.
    static func resolvedSelection(persisted: UUID?, among summaries: [HKWorkoutSummary]) -> UUID? {
        if let persisted, summaries.contains(where: { $0.uuid == persisted }) {
            return persisted
        }
        return defaultSelection(among: summaries)
    }

    /// Queries Apple Health for all workouts that start on the same calendar day
    /// as `date`, so the user can confidently pick the one that matches their
    /// logged session instead of the service guessing.
    static func workoutsForDay(_ date: Date) async throws -> [HKWorkoutSummary] {
        guard !ProcessInfo.processInfo.arguments.contains("-uitesting") else {
            return [
                HKWorkoutSummary(
                    uuid: UUID(),
                    startDate: date,
                    endDate: date.addingTimeInterval(3600),
                    activityType: .traditionalStrengthTraining,
                    sourceName: "Apple Watch"
                ),
                HKWorkoutSummary(
                    uuid: UUID(),
                    startDate: date.addingTimeInterval(7200),
                    endDate: date.addingTimeInterval(10800),
                    activityType: .mixedCardio,
                    sourceName: "Amazfit (Zepp)"
                )
            ]
        }
        guard HKHealthStore.isHealthDataAvailable() else {
            throw NSError(
                domain: "WorkoutHealthKitService",
                code: 5,
                userInfo: [NSLocalizedDescriptionKey: "Apple Health is not available on this device."]
            )
        }
        return buildSummaries(from: try await dayWorkouts(date))
    }

    /// Fetches the full `HKWorkout` by UUID from the set of workouts starting on `date`'s calendar day.
    static func matchingHKWorkout(uuid: UUID, onDayOf date: Date) async throws -> HKWorkout? {
        try await dayWorkouts(date).first { $0.uuid == uuid }
    }

    private static func dayWorkouts(_ date: Date) async throws -> [HKWorkout] {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: date)
        let predicate = HKQuery.predicateForSamples(
            withStart: dayStart,
            end: calendar.date(byAdding: .day, value: 1, to: dayStart) ?? date.addingTimeInterval(86400),
            options: [.strictStartDate]
        )
        return try await querySamples(of: workoutType, predicate: predicate)
    }

    static func syncRetroactiveBiometrics(for workout: Workout, in context: ModelContext, linking workoutUUID: UUID? = nil) async throws -> RetroactiveSyncResult {
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

        let targetWorkout: HKWorkout
        if let workoutUUID, let chosen = try await matchingHKWorkout(uuid: workoutUUID, onDayOf: workout.date) {
            targetWorkout = chosen
        } else {
            let startDate = workout.date
            let durationSeconds = TimeInterval(max(1, workout.durationMinutes) * 60)
            let endDate = startDate.addingTimeInterval(durationSeconds)
            let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)
            let existingWorkouts: [HKWorkout] = try await querySamples(of: workoutType, predicate: predicate)

            if let existing = existingWorkouts.first {
                targetWorkout = existing
            } else {
                let newWorkout = HKWorkout(
                    activityType: .traditionalStrengthTraining,
                    start: startDate,
                    end: endDate,
                    duration: durationSeconds,
                    totalEnergyBurned: nil,
                    totalDistance: nil,
                    metadata: [Self.sourceMetadataKey: Self.sourceMetadataValue]
                )
                try await saveObject(newWorkout)
                targetWorkout = newWorkout
            }
        }

        let biometricsStart = targetWorkout.startDate
        let biometricsEnd = targetWorkout.endDate
        let biosPredicate = HKQuery.predicateForSamples(withStart: biometricsStart, end: biometricsEnd, options: .strictStartDate)
        let hrSamples: [HKQuantitySample] = try await querySamples(of: heartRateType, predicate: biosPredicate)
        let hrvSamples: [HKQuantitySample] = try await querySamples(of: hrvType, predicate: biosPredicate)
        let calorieSamples: [HKQuantitySample] = try await querySamples(of: activeEnergyType, predicate: biosPredicate)

        let allSamples: [HKSample] = hrSamples + hrvSamples + calorieSamples
        if !allSamples.isEmpty {
            try? await addSamples(allSamples, to: targetWorkout)
        }

        var updatedCalories: Int? = nil
        let calorieSum = calorieSamples.reduce(0.0) { $0 + $1.quantity.doubleValue(for: .kilocalorie()) }
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
            heartRateSampleCount: hrSamples.count,
            hrvSampleCount: hrvSamples.count,
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
