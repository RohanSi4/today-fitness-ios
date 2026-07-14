import Combine
import Foundation

@MainActor
final class DailyRecapViewModel: ObservableObject {
    enum State {
        case idle
        case loading
        case loaded(DailyRecap, source: RecapDataSource)
        case error(String)
    }

    @Published private(set) var state: State = .idle

    var isShowingHealthData: Bool {
        if case .loaded(_, source: .healthKit) = state { return true }
        return false
    }

    private let healthData: HealthDataProviding
    private let notifications: RecapNotificationScheduling
    private let calendar: Calendar

    init(
        healthData: HealthDataProviding = HealthKitManager.shared,
        notifications: RecapNotificationScheduling = NotificationManager.shared,
        calendar: Calendar = .current
    ) {
        self.healthData = healthData
        self.notifications = notifications
        self.calendar = calendar
    }

    func load(targetDate: Date?, useSampleData: Bool) async {
        state = .loading

        if useSampleData || !healthData.isHealthDataAvailable {
            let date = recapDate(from: targetDate)
            let reason = healthData.isHealthDataAvailable
                ? "Previewing a deterministic demo day"
                : "HealthKit is unavailable in Simulator"
            state = .loaded(.mock(for: date), source: .sample(reason: reason))
            return
        }

        do {
            let recap = try await DailyRecapBuilder(
                healthData: healthData,
                calendar: calendar
            ).build(targetDate: targetDate)

            guard !Task.isCancelled else { return }
            state = .loaded(recap, source: .healthKit)
            await notifications.scheduleSleepHighlightIfAuthorized(
                wakeTime: recap.sleep.wakeTime,
                sleepSummary: recap.sleep,
                recapDate: recap.date
            )
        } catch is CancellationError {
            return
        } catch {
            state = .error(error.localizedDescription)
        }
    }

    func enableMorningReminders() async -> Bool {
        let granted = await notifications.requestAuthorization()
        guard granted,
              case .loaded(let recap, source: .healthKit) = state else {
            return granted
        }

        await notifications.scheduleSleepHighlightIfAuthorized(
            wakeTime: recap.sleep.wakeTime,
            sleepSummary: recap.sleep,
            recapDate: recap.date
        )
        return true
    }

    private func recapDate(from targetDate: Date?) -> Date {
        if let targetDate { return calendar.startOfDay(for: targetDate) }
        let today = calendar.startOfDay(for: Date())
        return calendar.date(byAdding: .day, value: -1, to: today) ?? today
    }
}

struct DailyRecapBuilder {
    private let healthData: HealthDataProviding
    private let calendar: Calendar
    private let now: () -> Date
    private let mainSleepMinimum: TimeInterval = 3 * 3600
    private let recentWindow: TimeInterval = 18 * 3600

    init(
        healthData: HealthDataProviding,
        calendar: Calendar = .current,
        now: @escaping () -> Date = Date.init
    ) {
        self.healthData = healthData
        self.calendar = calendar
        self.now = now
    }

    func build(targetDate: Date?) async throws -> DailyRecap {
        try await healthData.requestAuthorization()

        let currentDate = now()
        let todayStart = calendar.startOfDay(for: currentDate)
        let fallbackDate = calendar.date(byAdding: .day, value: -1, to: todayStart) ?? todayStart
        let movementDayStart = calendar.startOfDay(for: targetDate ?? fallbackDate)
        let rangeStart = calendar.date(byAdding: .day, value: -7, to: movementDayStart) ?? movementDayStart
        let rangeEnd = calendar.date(byAdding: .day, value: 1, to: movementDayStart) ?? movementDayStart

        async let stepsDaily = healthData.fetchDailyCumulativeStatistics(
            for: .steps,
            start: rangeStart,
            end: rangeEnd
        )
        async let distanceDaily = healthData.fetchDailyCumulativeStatistics(
            for: .distance,
            start: rangeStart,
            end: rangeEnd
        )
        async let energyDaily = healthData.fetchDailyCumulativeStatistics(
            for: .activeEnergy,
            start: rangeStart,
            end: rangeEnd
        )

        let sleepQueryEnd = min(
            currentDate,
            calendar.date(byAdding: .hour, value: 36, to: movementDayStart) ?? currentDate
        )
        let sleepRangeStart = calendar.date(byAdding: .day, value: -8, to: sleepQueryEnd) ?? sleepQueryEnd
        async let sleepSessions = healthData.fetchSleepSessions(start: sleepRangeStart, end: sleepQueryEnd)

        let (stepsMap, distanceMap, energyMap, sessions) = try await (
            stepsDaily,
            distanceDaily,
            energyDaily,
            sleepSessions
        )

        guard let primarySleep = selectPrimarySleepSession(from: sessions, referenceDate: sleepQueryEnd) else {
            throw HealthKitError.noSleepData
        }

        let baseline = makeSleepBaseline(
            from: baselineSleepSessions(from: sessions, excluding: primarySleep)
        )
        let wakeMinutes = CircularClock.minutesSinceMidnight(primarySleep.end, calendar: calendar)
        let scoreResult = SleepScoreCalculator.score(
            duration: primarySleep.asleepDuration,
            inBed: primarySleep.inBedDuration,
            wakeTimeMinutes: wakeMinutes,
            avgWakeTimeMinutes: baseline.avgWakeTimeMinutes
        )

        let sleepSummary = SleepSummary(
            score: scoreResult.score,
            duration: primarySleep.asleepDuration,
            inBed: primarySleep.inBedDuration,
            efficiency: primarySleep.efficiency,
            bedtime: primarySleep.start,
            wakeTime: primarySleep.end,
            avgDuration: baseline.avgDuration,
            avgInBed: baseline.avgInBed,
            avgEfficiency: baseline.avgEfficiency,
            avgBedtimeMinutes: baseline.avgBedtimeMinutes,
            avgWakeTimeMinutes: baseline.avgWakeTimeMinutes
        )

        let movement = [
            makeMetric(kind: .steps, unit: .count, map: stepsMap, date: movementDayStart),
            makeMetric(kind: .distance, unit: .meters, map: distanceMap, date: movementDayStart),
            makeMetric(kind: .activeEnergy, unit: .kilocalories, map: energyMap, date: movementDayStart)
        ]

        return DailyRecap(
            date: movementDayStart,
            sleep: sleepSummary,
            movement: movement,
            insight: DailyRecapInsight.make(sleep: sleepSummary, movement: movement)
        )
    }

    private func makeMetric(
        kind: MovementKind,
        unit: MovementUnit,
        map: [Date: Double],
        date: Date
    ) -> MovementMetric {
        MovementMetric(
            kind: kind,
            value: map[date] ?? 0,
            average: Self.averageDailyValue(
                from: map,
                before: date,
                days: 7,
                calendar: calendar
            ),
            unit: unit
        )
    }

    static func averageDailyValue(
        from map: [Date: Double],
        before date: Date,
        days: Int,
        calendar: Calendar
    ) -> Double {
        guard days > 0 else { return 0 }
        let total = (1...days).reduce(0.0) { partial, offset in
            let day = calendar.date(byAdding: .day, value: -offset, to: date) ?? date
            return partial + (map[calendar.startOfDay(for: day)] ?? 0)
        }
        return total / Double(days)
    }

    private func baselineSleepSessions(
        from sessions: [SleepSession],
        excluding latest: SleepSession
    ) -> [SleepSession] {
        let prior = sessions
            .filter { $0.end < latest.end && $0.asleepDuration >= mainSleepMinimum }
            .sorted { $0.end < $1.end }
        return Array(prior.suffix(7))
    }

    private func selectPrimarySleepSession(
        from sessions: [SleepSession],
        referenceDate: Date
    ) -> SleepSession? {
        let recentCutoff = referenceDate.addingTimeInterval(-recentWindow)
        let recent = sessions.filter {
            $0.end <= referenceDate &&
            $0.end >= recentCutoff &&
            $0.asleepDuration >= mainSleepMinimum
        }

        if let longestRecent = recent.max(by: { $0.asleepDuration < $1.asleepDuration }) {
            return longestRecent
        }

        return sessions
            .filter { $0.end <= referenceDate && $0.asleepDuration >= mainSleepMinimum }
            .max(by: { $0.end < $1.end })
    }

    private func makeSleepBaseline(from sessions: [SleepSession]) -> SleepBaseline {
        guard !sessions.isEmpty else { return .empty }

        let count = Double(sessions.count)
        return SleepBaseline(
            avgDuration: sessions.map(\.asleepDuration).reduce(0, +) / count,
            avgInBed: sessions.map(\.inBedDuration).reduce(0, +) / count,
            avgEfficiency: sessions.map(\.efficiency).reduce(0, +) / count,
            avgBedtimeMinutes: CircularClock.averageMinutes(
                sessions.map { CircularClock.minutesSinceMidnight($0.start, calendar: calendar) }
            ),
            avgWakeTimeMinutes: CircularClock.averageMinutes(
                sessions.map { CircularClock.minutesSinceMidnight($0.end, calendar: calendar) }
            )
        )
    }
}

enum CircularClock {
    static func minutesSinceMidnight(_ date: Date, calendar: Calendar) -> Double {
        let components = calendar.dateComponents([.hour, .minute, .second], from: date)
        return Double((components.hour ?? 0) * 60 + (components.minute ?? 0))
            + Double(components.second ?? 0) / 60
    }

    static func averageMinutes(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let radians = values.map { $0 / 1_440 * 2 * Double.pi }
        let sine = radians.map(sin).reduce(0, +) / Double(radians.count)
        let cosine = radians.map(cos).reduce(0, +) / Double(radians.count)
        var angle = atan2(sine, cosine)
        if angle < 0 { angle += 2 * Double.pi }
        return angle / (2 * Double.pi) * 1_440
    }

    static func signedDifference(from average: Double, to actual: Double) -> Double {
        var difference = (actual - average).truncatingRemainder(dividingBy: 1_440)
        if difference > 720 { difference -= 1_440 }
        if difference < -720 { difference += 1_440 }
        return difference
    }
}

enum DailyRecapInsight {
    static func make(sleep: SleepSummary, movement: [MovementMetric]) -> String {
        let sleepDelta = percentDelta(current: sleep.duration, average: sleep.avgDuration)
        let movementDeltas = movement.map { percentDelta(current: $0.value, average: $0.average) }
        let strongestMovement = movementDeltas.max() ?? 0
        let weakestMovement = movementDeltas.min() ?? 0

        switch (sleepDelta, strongestMovement, weakestMovement) {
        case (..<(-0.05), 0.08..., _):
            return "Sleep was lighter than usual, but your movement still finished above average."
        case (0.05..., _, ..<(-0.08)):
            return "You slept more than usual; a lighter movement day may have helped recovery."
        case (..<(-0.05), _, ..<(-0.08)):
            return "Sleep and movement were both below baseline, so consider an easier recovery day."
        case (0.05..., 0.08..., _):
            return "Strong balance: both sleep and movement finished above your recent baseline."
        case (_, 0.08..., _):
            return "Movement was the standout, finishing above your seven-day baseline."
        case (_, _, ..<(-0.08)):
            return "Movement was below your recent baseline; a short walk could reset today."
        default:
            return "Your sleep and movement stayed close to their seven-day baselines."
        }
    }

    private static func percentDelta(current: Double, average: Double) -> Double {
        guard average > 0 else { return 0 }
        return (current - average) / average
    }
}

private struct SleepBaseline {
    let avgDuration: TimeInterval
    let avgInBed: TimeInterval
    let avgEfficiency: Double
    let avgBedtimeMinutes: Double?
    let avgWakeTimeMinutes: Double?

    static let empty = SleepBaseline(
        avgDuration: 0,
        avgInBed: 0,
        avgEfficiency: 0,
        avgBedtimeMinutes: nil,
        avgWakeTimeMinutes: nil
    )
}
