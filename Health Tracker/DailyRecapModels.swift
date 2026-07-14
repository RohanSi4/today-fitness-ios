import Foundation

struct SleepSession: Equatable, Sendable {
    let start: Date
    let end: Date
    let asleepDuration: TimeInterval
    let inBedDuration: TimeInterval

    var efficiency: Double {
        guard inBedDuration > 0 else { return 0 }
        return min(1, max(0, asleepDuration / inBedDuration))
    }
}

enum MovementKind: String, CaseIterable, Identifiable, Sendable {
    case steps
    case distance
    case activeEnergy

    var id: Self { self }

    var title: String {
        switch self {
        case .steps: "Steps"
        case .distance: "Walking distance"
        case .activeEnergy: "Active energy"
        }
    }

    var symbolName: String {
        switch self {
        case .steps: "figure.walk"
        case .distance: "map"
        case .activeEnergy: "flame.fill"
        }
    }
}

enum MovementUnit: Sendable {
    case count
    case meters
    case kilocalories
}

struct MovementMetric: Identifiable, Equatable, Sendable {
    let kind: MovementKind
    let value: Double
    let average: Double
    let unit: MovementUnit

    var id: MovementKind { kind }
    var title: String { kind.title }
    var delta: Double { value - average }
}

struct SleepSummary: Equatable, Sendable {
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

    var durationDelta: TimeInterval { duration - avgDuration }
    var inBedDelta: TimeInterval { inBed - avgInBed }
    var efficiencyDelta: Double { efficiency - avgEfficiency }
}

struct DailyRecap: Equatable, Sendable {
    let date: Date
    let sleep: SleepSummary
    let movement: [MovementMetric]
    let insight: String
}

enum RecapDataSource: Equatable, Sendable {
    case healthKit
    case sample(reason: String)

    var isSample: Bool {
        if case .sample = self { return true }
        return false
    }
}

extension DailyRecap {
    static func mock() -> DailyRecap {
        mock(for: Date())
    }

    static func mock(for date: Date) -> DailyRecap {
        let calendar = Calendar(identifier: .gregorian)
        let recapDate = calendar.startOfDay(for: date)
        let wakeDate = calendar.date(byAdding: .day, value: 1, to: recapDate) ?? recapDate
        let wakeTime = calendar.date(bySettingHour: 7, minute: 10, second: 0, of: wakeDate) ?? wakeDate
        let bedtime = calendar.date(byAdding: .minute, value: -(7 * 60 + 18), to: wakeTime) ?? wakeTime

        let sleep = SleepSummary(
            score: 86,
            duration: 7.05 * 3600,
            inBed: 7.3 * 3600,
            efficiency: 0.97,
            bedtime: bedtime,
            wakeTime: wakeTime,
            avgDuration: 6.7 * 3600,
            avgInBed: 7.2 * 3600,
            avgEfficiency: 0.93,
            avgBedtimeMinutes: 23 * 60 + 5,
            avgWakeTimeMinutes: 7 * 60 + 20
        )

        let movement = [
            MovementMetric(kind: .steps, value: 9_830, average: 8_590, unit: .count),
            MovementMetric(kind: .distance, value: 7_420, average: 6_800, unit: .meters),
            MovementMetric(kind: .activeEnergy, value: 520, average: 480, unit: .kilocalories)
        ]

        return DailyRecap(
            date: recapDate,
            sleep: sleep,
            movement: movement,
            insight: "Your sleep was more efficient than usual, and you paired it with an above-average movement day."
        )
    }
}
