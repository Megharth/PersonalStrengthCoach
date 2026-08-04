import HealthKit
import SwiftData

@MainActor
enum HealthKitService {
    private static let store = HKHealthStore()
    private static let calendar = Calendar.current

    static func sync(context: ModelContext) async throws {
        guard HKHealthStore.isHealthDataAvailable() else { return }

        let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!
        let hrvType = HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN)!
        let restingHeartRateType = HKObjectType.quantityType(forIdentifier: .restingHeartRate)!
        let bodyMassType = HKObjectType.quantityType(forIdentifier: .bodyMass)!
        try await store.requestAuthorization(toShare: [], read: [sleepType, hrvType, restingHeartRateType, bodyMassType])

        let start = calendar.date(byAdding: .day, value: -15, to: calendar.startOfDay(for: .now))!
        async let sleepSamples: [HKCategorySample] = samples(of: sleepType, since: start)
        async let hrvSamples: [HKQuantitySample] = samples(of: hrvType, since: start)
        async let heartRateSamples: [HKQuantitySample] = samples(of: restingHeartRateType, since: start)
        async let massSamples: [HKQuantitySample] = samples(of: bodyMassType, since: start)
        let (sleep, hrv, heartRate, mass) = try await (sleepSamples, hrvSamples, heartRateSamples, massSamples)

        let stored = try context.fetch(FetchDescriptor<DailyRecovery>())
        for offset in 0..<15 {
            let day = calendar.date(byAdding: .day, value: -offset, to: calendar.startOfDay(for: .now))!
            let nextDay = calendar.date(byAdding: .day, value: 1, to: day)!
            // Attribute overnight sleep to the day it ends (the user's wake-up day).
            let sleepHours = asleepHours(from: sleep.filter { calendar.isDate($0.endDate, inSameDayAs: day) })
            let dailyHRV = average(hrv, on: day, unit: .secondUnit(with: .milli))
            let dailyHeartRate = average(heartRate, on: day, unit: .count().unitDivided(by: .minute()))
            let weight = mass.filter { $0.startDate < nextDay }.max(by: { $0.startDate < $1.startDate })?.quantity.doubleValue(for: .gramUnit(with: .kilo)) ?? 0

            if let existing = stored.first(where: { calendar.isDate($0.date, inSameDayAs: day) }) {
                if sleepHours > 0 { existing.sleepHours = sleepHours }
                if dailyHRV > 0 { existing.hrv = dailyHRV }
                if dailyHeartRate > 0 { existing.restingHeartRate = dailyHeartRate }
                if weight > 0 { existing.weightKg = weight }
            } else if sleepHours > 0 || dailyHRV > 0 || dailyHeartRate > 0 || weight > 0 {
                context.insert(DailyRecovery(date: day, sleepHours: sleepHours, hrv: dailyHRV, restingHeartRate: dailyHeartRate, weightKg: weight))
            }
        }
        try context.save()
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

    private static func average(_ samples: [HKQuantitySample], on day: Date, unit: HKUnit) -> Double {
        let values = samples.filter { calendar.isDate($0.startDate, inSameDayAs: day) }.map { $0.quantity.doubleValue(for: unit) }
        return values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)
    }

    private static func asleepHours(from samples: [HKCategorySample]) -> Double {
        let intervals = samples
            .filter { sample in
                HKCategoryValueSleepAnalysis(rawValue: sample.value).map(HKCategoryValueSleepAnalysis.allAsleepValues.contains) ?? false
            }
            .map { DateInterval(start: $0.startDate, end: $0.endDate) }
            .sorted { $0.start < $1.start }
        guard var current = intervals.first else { return 0 }
        var seconds = 0.0
        for interval in intervals.dropFirst() {
            if interval.start <= current.end {
                current = DateInterval(start: current.start, end: max(current.end, interval.end))
            } else {
                seconds += current.duration
                current = interval
            }
        }
        return (seconds + current.duration) / 3600
    }
}
