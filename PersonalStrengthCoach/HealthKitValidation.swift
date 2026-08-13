import Foundation

enum HealthKitValidation {
    // MARK: - Physiologically plausible ranges (inclusive)

    static let restingHeartRateRange: ClosedRange<Double> = 30...120   // bpm
    static let hrvSDNNRange: ClosedRange<Double> = 1...200             // ms
    static let sleepHoursRange: ClosedRange<Double> = 0...16           // per attributed day
    static let bodyMassKgRange: ClosedRange<Double> = 20...300         // kg

    enum Metric {
        case restingHeartRate, hrvSDNN, sleepHours, bodyMassKg

        var range: ClosedRange<Double> {
            switch self {
            case .restingHeartRate: HealthKitValidation.restingHeartRateRange
            case .hrvSDNN: HealthKitValidation.hrvSDNNRange
            case .sleepHours: HealthKitValidation.sleepHoursRange
            case .bodyMassKg: HealthKitValidation.bodyMassKgRange
            }
        }
    }

    // MARK: - Validation

    static func isValid(_ value: Double, for metric: Metric) -> Bool {
        !value.isNaN && !value.isInfinite && metric.range.contains(value)
    }

    static func filterValid(_ values: [Double], for metric: Metric) -> [Double] {
        values.filter { isValid($0, for: metric) }
    }

    // MARK: - Robust aggregation

    /// Returns the median of a non-empty array, or `nil` for empty input.
    /// For even counts the two middle values are averaged.
    static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[mid - 1] + sorted[mid]) / 2
        }
        return sorted[mid]
    }

    /// Trimmed mean that drops `floor(count * trimFraction)` values from each tail.
    /// Falls back to arithmetic mean if trimming would empty the list. Returns `nil` for empty input.
    static func trimmedMean(_ values: [Double], trimFraction: Double = 0.2) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let trimCount = Int(Double(sorted.count) * trimFraction)
        let trimmed = trimCount > 0 && trimCount * 2 < sorted.count
            ? Array(sorted[trimCount ..< (sorted.count - trimCount)])
            : sorted
        return trimmed.reduce(0, +) / Double(trimmed.count)
    }

    // MARK: - Aggregate result

    struct Aggregate {
        let value: Double
        let sampleCount: Int
    }

    /// Filters invalid values, then returns the median of the valid ones plus the valid sample count.
    /// Returns `nil` when no valid samples remain.
    static func aggregate(_ values: [Double], for metric: Metric) -> Aggregate? {
        let valid = filterValid(values, for: metric)
        guard let med = median(valid) else { return nil }
        return Aggregate(value: med, sampleCount: valid.count)
    }
}
