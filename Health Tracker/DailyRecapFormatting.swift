import Foundation

enum DailyRecapFormatting {
    static func date(_ date: Date) -> String {
        date.formatted(date: .complete, time: .omitted)
    }

    static func time(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    static func duration(_ seconds: TimeInterval) -> String {
        let totalMinutes = max(0, Int((seconds / 60).rounded()))
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours == 0 { return "\(minutes)m" }
        if minutes == 0 { return "\(hours)h" }
        return "\(hours)h \(minutes)m"
    }

    static func percent(_ value: Double) -> String {
        value.formatted(.percent.precision(.fractionLength(0)))
    }

    static func number(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0)))
    }

    static func movementValue(_ value: Double, unit: MovementUnit) -> String {
        switch unit {
        case .count:
            number(value)
        case .meters:
            distance(value)
        case .kilocalories:
            "\(number(value)) kcal"
        }
    }

    static func durationComparison(current: TimeInterval, average: TimeInterval) -> String {
        guard average > 0 else { return "Not enough baseline data" }
        return comparison(delta: current - average, formattedDelta: duration(abs(current - average)))
    }

    static func percentComparison(current: Double, average: Double) -> String {
        guard average > 0 else { return "Not enough baseline data" }
        return comparison(delta: current - average, formattedDelta: percent(abs(current - average)))
    }

    static func movementComparison(current: Double, average: Double, unit: MovementUnit) -> String {
        guard average > 0 else { return "Not enough baseline data" }
        let delta = current - average
        return comparison(delta: delta, formattedDelta: movementValue(abs(delta), unit: unit))
    }

    static func timeComparison(actual: Date, averageMinutes: Double?) -> String {
        guard let averageMinutes else { return "Not enough baseline data" }
        let actualMinutes = CircularClock.minutesSinceMidnight(actual, calendar: .current)
        let difference = CircularClock.signedDifference(from: averageMinutes, to: actualMinutes)
        if abs(difference) < 1 { return "Right on your average" }
        let direction = difference > 0 ? "later" : "earlier"
        return "\(Int(abs(difference).rounded()))m \(direction) than average"
    }

    static func baselineDuration(_ value: TimeInterval) -> String {
        value > 0 ? "7-day avg \(duration(value))" : "Baseline building"
    }

    static func baselinePercent(_ value: Double) -> String {
        value > 0 ? "7-day avg \(percent(value))" : "Baseline building"
    }

    static func baselineMovement(_ value: Double, unit: MovementUnit) -> String {
        value > 0 ? "7-day avg \(movementValue(value, unit: unit))" : "Baseline building"
    }

    private static func comparison(delta: Double, formattedDelta: String) -> String {
        if abs(delta) < 0.0001 { return "Matches your average" }
        return "\(formattedDelta) \(delta > 0 ? "above" : "below") average"
    }

    private static func distance(_ meters: Double) -> String {
        let unit: UnitLength = Locale.current.measurementSystem == .metric ? .kilometers : .miles
        let measurement = Measurement(value: meters, unit: UnitLength.meters).converted(to: unit)
        let formatter = MeasurementFormatter()
        formatter.unitOptions = .providedUnit
        formatter.unitStyle = .short
        formatter.numberFormatter.maximumFractionDigits = 1
        return formatter.string(from: measurement)
    }
}
