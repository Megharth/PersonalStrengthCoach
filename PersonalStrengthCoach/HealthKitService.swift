import HealthKit
import SwiftData

@MainActor
enum HealthKitService {
    private static let store = HKHealthStore()
    private static let calendar = Calendar.current

    static func sync(context: ModelContext) async -> HealthKitSyncStatus {
        guard HKHealthStore.isHealthDataAvailable() else { return .unavailable }

        let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!
        let hrvType = HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN)!
        let restingHeartRateType = HKObjectType.quantityType(forIdentifier: .restingHeartRate)!
        let bodyMassType = HKObjectType.quantityType(forIdentifier: .bodyMass)!
        let readTypes: Set<HKObjectType> = [sleepType, hrvType, restingHeartRateType, bodyMassType]

        do {
            let authorizationStatus = try await store.statusForAuthorizationRequest(toShare: [], read: readTypes)
            if authorizationStatus == .shouldRequest {
                try await store.requestAuthorization(toShare: [], read: readTypes)
                let updatedStatus = try await store.statusForAuthorizationRequest(toShare: [], read: readTypes)
                if updatedStatus == .shouldRequest { return .notDetermined }
            } else if authorizationStatus == .unknown {
                return .notDetermined
            }

            let start = calendar.date(byAdding: .day, value: -15, to: calendar.startOfDay(for: .now))!
            async let sleepSamples: [HKCategorySample] = samples(of: sleepType, since: start)
            async let hrvSamples: [HKQuantitySample] = samples(of: hrvType, since: start)
            async let heartRateSamples: [HKQuantitySample] = samples(of: restingHeartRateType, since: start)
            async let massSamples: [HKQuantitySample] = samples(of: bodyMassType, since: start)
            let (sleep, hrv, heartRate, mass) = try await (sleepSamples, hrvSamples, heartRateSamples, massSamples)

            let stored = try context.fetch(FetchDescriptor<DailyRecovery>())
            var validSampleCount = 0
            for offset in 0..<15 {
                let day = calendar.date(byAdding: .day, value: -offset, to: calendar.startOfDay(for: .now))!
                // Attribute overnight sleep to the day it ends (the user's wake-up day).
                let sleepResult = asleepHours(from: sleep.filter { calendar.isDate($0.endDate, inSameDayAs: day) })
                let hrvResult = dailyReading(hrv, on: day, unit: .secondUnit(with: .milli), metric: .hrvSDNN)
                let heartRateResult = dailyReading(heartRate, on: day, unit: .count().unitDivided(by: .minute()), metric: .restingHeartRate)
                let weightResult = latestBodyMass(mass, on: day)
                validSampleCount += [sleepResult, hrvResult, heartRateResult, weightResult].compactMap { $0?.sampleCount }.reduce(0, +)

                if let existing = stored.first(where: { calendar.isDate($0.date, inSameDayAs: day) }) {
                    apply(sleepResult, to: existing, keyPath: \DailyRecovery.sleepHours, countKeyPath: \DailyRecovery.sleepSampleCount)
                    apply(hrvResult, to: existing, keyPath: \DailyRecovery.hrv, countKeyPath: \DailyRecovery.hrvSampleCount)
                    apply(heartRateResult, to: existing, keyPath: \DailyRecovery.restingHeartRate, countKeyPath: \DailyRecovery.restingHeartRateSampleCount)
                    apply(weightResult, to: existing, keyPath: \DailyRecovery.weightKg, countKeyPath: \DailyRecovery.bodyMassSampleCount)
                } else if sleepResult != nil || hrvResult != nil || heartRateResult != nil || weightResult != nil {
                    context.insert(DailyRecovery(
                        date: day,
                        sleepHours: sleepResult?.value ?? 0,
                        hrv: hrvResult?.value ?? 0,
                        restingHeartRate: heartRateResult?.value ?? 0,
                        weightKg: weightResult?.value ?? 0,
                        sleepSampleCount: sleepResult?.sampleCount ?? 0,
                        hrvSampleCount: hrvResult?.sampleCount ?? 0,
                        restingHeartRateSampleCount: heartRateResult?.sampleCount ?? 0,
                        bodyMassSampleCount: weightResult?.sampleCount ?? 0
                    ))
                }
            }
            if validSampleCount == 0 { return .noReadableData }
            try context.save()
            return .synced(validSampleCount: validSampleCount)
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    private static func samples<T: HKSample>(of type: HKSampleType, since start: Date) async throws -> [T] {
        try await withCheckedThrowingContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(withStart: start, end: nil)
            store.execute(HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: samples as? [T] ?? []) }
            })
        }
    }

    private static func dailyReading(_ samples: [HKQuantitySample], on day: Date, unit: HKUnit, metric: HealthKitValidation.Metric) -> HealthKitValidation.Aggregate? {
        let values = samples.filter { calendar.isDate($0.startDate, inSameDayAs: day) }.map { $0.quantity.doubleValue(for: unit) }
        return HealthKitValidation.aggregate(values, for: metric)
    }

    // Same-day only: a day with no scale reading stores no weight rather than carrying
    // the previous day's value forward, so `bodyMassSampleCount == 0` always means
    // "not weighed that day" instead of "repeat of an older reading".
    private static func latestBodyMass(_ samples: [HKQuantitySample], on day: Date) -> HealthKitValidation.Aggregate? {
        let validSamples = samples
            .filter { calendar.isDate($0.startDate, inSameDayAs: day) }
            .compactMap { sample -> (date: Date, value: Double)? in
                let value = sample.quantity.doubleValue(for: .gramUnit(with: .kilo))
                guard HealthKitValidation.isValid(value, for: .bodyMassKg) else { return nil }
                return (sample.startDate, value)
            }
        guard let latest = validSamples.max(by: { $0.date < $1.date }) else { return nil }
        return HealthKitValidation.Aggregate(value: latest.value, sampleCount: validSamples.count)
    }

    private static func asleepHours(from samples: [HKCategorySample]) -> HealthKitValidation.Aggregate? {
        let intervals = samples
            .filter { sample in
                HKCategoryValueSleepAnalysis(rawValue: sample.value).map(HKCategoryValueSleepAnalysis.allAsleepValues.contains) ?? false
            }
            .map { DateInterval(start: $0.startDate, end: $0.endDate) }
            .sorted { $0.start < $1.start }
        guard var current = intervals.first else { return nil }
        var seconds = 0.0
        for interval in intervals.dropFirst() {
            if interval.start <= current.end {
                current = DateInterval(start: current.start, end: max(current.end, interval.end))
            } else {
                seconds += current.duration
                current = interval
            }
        }
        let hours = (seconds + current.duration) / 3600
        guard HealthKitValidation.isValid(hours, for: .sleepHours), hours > 0 else { return nil }
        return HealthKitValidation.Aggregate(value: hours, sampleCount: intervals.count)
    }

    private static func apply(_ aggregate: HealthKitValidation.Aggregate?, to recovery: DailyRecovery, keyPath: ReferenceWritableKeyPath<DailyRecovery, Double>, countKeyPath: ReferenceWritableKeyPath<DailyRecovery, Int>) {
        guard let aggregate else { return }
        recovery[keyPath: keyPath] = aggregate.value
        recovery[keyPath: countKeyPath] = aggregate.sampleCount
    }
}

enum HealthKitSyncStatus: Equatable {
    case unavailable
    case notDetermined
    case synced(validSampleCount: Int)
    case noReadableData
    case failed(String)
}
