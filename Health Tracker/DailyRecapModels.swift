import Foundation

struct SleepSession {
    let start: Date
    let end: Date
    let asleepDuration: TimeInterval
    let inBedDuration: TimeInterval

    var efficiency: Double {
        guard inBedDuration > 0 else { return 0 }
        return asleepDuration / inBedDuration
    }
}

enum MovementUnit {
    case count
    case meters
    case kilocalories
}

struct MovementMetric: Identifiable {
    let id = UUID()
    let title: String
    let value: Double
    let average: Double
    let unit: MovementUnit

    var delta: Double {
        value - average
    }
}

struct SleepSummary {
    let score: Int
    let duration: TimeInterval
    let inBed: TimeInterval
    let efficiency: Double
    let bedtime: Date
    let wakeTime: Date
    let avgDuration: TimeInterval
    let avgInBed: TimeInterval
    let avgEfficiency: Double
    let avgBedtimeMinutes: Double?
    let avgWakeTimeMinutes: Double?

    var durationDelta: TimeInterval {
        duration - avgDuration
    }

    var inBedDelta: TimeInterval {
        inBed - avgInBed
    }

    var efficiencyDelta: Double {
        efficiency - avgEfficiency
    }
}

struct DailyRecap {
    let date: Date
    let sleep: SleepSummary
    let movement: [MovementMetric]
    let insight: String
}

extension DailyRecap {
    static func mock() -> DailyRecap {
        let now = Date()
        let sleep = SleepSummary(
            score: 82,
            duration: 6.5 * 3600,
            inBed: 7.3 * 3600,
            efficiency: 0.89,
            bedtime: Calendar.current.date(byAdding: .hour, value: -8, to: now) ?? now,
            wakeTime: now,
            avgDuration: 7.2 * 3600,
            avgInBed: 7.8 * 3600,
            avgEfficiency: 0.91,
            avgBedtimeMinutes: 22 * 60 + 45,
            avgWakeTimeMinutes: 6 * 60 + 50
        )

        let movement = [
            MovementMetric(title: "Steps", value: 9830, average: 8590, unit: .count),
            MovementMetric(title: "Walking distance", value: 7420, average: 6800, unit: .meters),
            MovementMetric(title: "Active energy", value: 520, average: 480, unit: .kilocalories)
        ]

        return DailyRecap(
            date: Calendar.current.date(byAdding: .day, value: -1, to: now) ?? now,
            sleep: sleep,
            movement: movement,
            insight: "Sleep was down, but steps were above average."
        )
    }
}
