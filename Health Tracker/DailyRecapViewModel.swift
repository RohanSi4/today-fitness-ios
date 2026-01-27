import Foundation

@MainActor
final class DailyRecapViewModel: ObservableObject {
    enum State {
        case idle
        case loading
        case loaded(DailyRecap)
        case error(String)
    }

    @Published private(set) var state: State = .idle

    private let healthKit = HealthKitManager.shared
    private let mainSleepMinimum: TimeInterval = 3 * 3600
    private let recentWindow: TimeInterval = 18 * 3600
    private var targetDate: Date?

    init(targetDate: Date? = nil) {
        self.targetDate = targetDate
    }

    func updateTargetDate(_ date: Date?) async {
        targetDate = date
        state = .idle
        await load()
    }

    func load() async {
        switch state {
        case .loading, .loaded:
            return
        case .idle, .error:
            break
        }

        state = .loading

        do {
            let recap = try await buildRecap()
            state = .loaded(recap)
        } catch {
            state = .error(error.localizedDescription)
        }
    }

    private func buildRecap() async throws -> DailyRecap {
        try await healthKit.requestAuthorization()

        let calendar = Calendar.current
        let now = Date()
        let todayStart = calendar.startOfDay(for: now)
        let movementDate = targetDate ?? calendar.date(byAdding: .day, value: -1, to: todayStart) ?? todayStart
        let movementDayStart = calendar.startOfDay(for: movementDate)
        let rangeEnd = calendar.date(byAdding: .day, value: 1, to: movementDayStart) ?? todayStart
        let rangeStart = calendar.date(byAdding: .day, value: -7, to: rangeEnd) ?? todayStart

        async let stepsDaily = healthKit.fetchDailyCumulativeStatistics(
            for: .stepCount,
            start: rangeStart,
            end: rangeEnd
        )
        async let distanceDaily = healthKit.fetchDailyCumulativeStatistics(
            for: .distanceWalkingRunning,
            start: rangeStart,
            end: rangeEnd
        )
        async let energyDaily = healthKit.fetchDailyCumulativeStatistics(
            for: .activeEnergyBurned,
            start: rangeStart,
            end: rangeEnd
        )

        let sleepRangeStart = calendar.date(byAdding: .day, value: -8, to: now) ?? now
        async let sleepSessions = healthKit.fetchSleepSessions(start: sleepRangeStart, end: now)

        let (stepsMap, distanceMap, energyMap, sessions) = try await (
            stepsDaily,
            distanceDaily,
            energyDaily,
            sleepSessions
        )

        guard let latestSession = selectPrimarySleepSession(from: sessions, now: now) else {
            throw HealthKitError.noSleepData
        }

        let baselineSessions = baselineSleepSessions(from: sessions, excluding: latestSession)
        let sleepBaseline = makeSleepBaseline(from: baselineSessions)

        let wakeMinutes = minutesSinceMidnight(latestSession.end, calendar: calendar)
        let scoreResult = SleepScoreCalculator.score(
            duration: latestSession.asleepDuration,
            inBed: latestSession.inBedDuration,
            wakeTimeMinutes: wakeMinutes,
            avgWakeTimeMinutes: sleepBaseline.avgWakeTimeMinutes
        )

        let sleepSummary = SleepSummary(
            score: scoreResult.score,
            duration: latestSession.asleepDuration,
            inBed: latestSession.inBedDuration,
            efficiency: latestSession.efficiency,
            bedtime: latestSession.start,
            wakeTime: latestSession.end,
            avgDuration: sleepBaseline.avgDuration,
            avgInBed: sleepBaseline.avgInBed,
            avgEfficiency: sleepBaseline.avgEfficiency,
            avgBedtimeMinutes: sleepBaseline.avgBedtimeMinutes,
            avgWakeTimeMinutes: sleepBaseline.avgWakeTimeMinutes
        )

        let stepsMetric = MovementMetric(
            title: "Steps",
            value: stepsMap[movementDayStart] ?? 0,
            average: averageDailyValue(from: stepsMap, days: 7),
            unit: .count
        )

        let distanceMetric = MovementMetric(
            title: "Walking distance",
            value: distanceMap[movementDayStart] ?? 0,
            average: averageDailyValue(from: distanceMap, days: 7),
            unit: .meters
        )

        let energyMetric = MovementMetric(
            title: "Active energy",
            value: energyMap[movementDayStart] ?? 0,
            average: averageDailyValue(from: energyMap, days: 7),
            unit: .kilocalories
        )

        let movement = [stepsMetric, distanceMetric, energyMetric]
        let insight = buildInsight(sleep: sleepSummary, movement: movement)

        await NotificationManager.shared.scheduleSleepHighlight(
            wakeTime: latestSession.end,
            sleepSummary: sleepSummary,
            recapDate: movementDayStart
        )

        return DailyRecap(date: movementDayStart, sleep: sleepSummary, movement: movement, insight: insight)
    }

    private func baselineSleepSessions(from sessions: [SleepSession], excluding latest: SleepSession) -> [SleepSession] {
        let prior = sessions
            .filter { $0.end < latest.end && $0.asleepDuration >= mainSleepMinimum }
            .sorted { $0.end < $1.end }
        if prior.isEmpty {
            return Array(sessions.sorted { $0.end < $1.end }.suffix(7))
        }
        return Array(prior.suffix(7))
    }

    private func selectPrimarySleepSession(from sessions: [SleepSession], now: Date) -> SleepSession? {
        guard !sessions.isEmpty else { return nil }

        let recentCutoff = now.addingTimeInterval(-recentWindow)
        let recentCandidates = sessions.filter {
            $0.end >= recentCutoff && $0.asleepDuration >= mainSleepMinimum
        }

        if let bestRecent = recentCandidates.max(by: { $0.asleepDuration < $1.asleepDuration }) {
            return bestRecent
        }

        let mainCandidates = sessions.filter { $0.asleepDuration >= mainSleepMinimum }
        if let bestMain = mainCandidates.max(by: { $0.end < $1.end }) {
            return bestMain
        }

        return sessions.max(by: { $0.end < $1.end })
    }

    private func makeSleepBaseline(from sessions: [SleepSession]) -> SleepBaseline {
        guard !sessions.isEmpty else {
            return SleepBaseline(
                avgDuration: 0,
                avgInBed: 0,
                avgEfficiency: 0,
                avgBedtimeMinutes: nil,
                avgWakeTimeMinutes: nil
            )
        }

        let count = Double(sessions.count)
        let avgDuration = sessions.map { $0.asleepDuration }.reduce(0, +) / count
        let avgInBed = sessions.map { $0.inBedDuration }.reduce(0, +) / count
        let avgEfficiency = sessions.map { $0.efficiency }.reduce(0, +) / count

        let bedtimes = sessions.map { minutesSinceMidnight($0.start, calendar: Calendar.current) }
        let wakeTimes = sessions.map { minutesSinceMidnight($0.end, calendar: Calendar.current) }

        let avgBedtimeMinutes = bedtimes.reduce(0, +) / count
        let avgWakeTimeMinutes = wakeTimes.reduce(0, +) / count

        return SleepBaseline(
            avgDuration: avgDuration,
            avgInBed: avgInBed,
            avgEfficiency: avgEfficiency,
            avgBedtimeMinutes: avgBedtimeMinutes,
            avgWakeTimeMinutes: avgWakeTimeMinutes
        )
    }

    private func averageDailyValue(from map: [Date: Double], days: Int) -> Double {
        guard days > 0 else { return 0 }
        let total = map.values.reduce(0, +)
        return total / Double(days)
    }

    private func minutesSinceMidnight(_ date: Date, calendar: Calendar) -> Double {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        let hour = components.hour ?? 0
        let minute = components.minute ?? 0
        return Double(hour * 60 + minute)
    }

    private func buildInsight(sleep: SleepSummary, movement: [MovementMetric]) -> String {
        let sleepDeltaPercent = percentDelta(current: sleep.duration, average: sleep.avgDuration)

        let steps = movement.first { $0.title == "Steps" }
        let distance = movement.first { $0.title == "Walking distance" }
        let energy = movement.first { $0.title == "Active energy" }

        let stepsDelta = percentDelta(current: steps?.value, average: steps?.average)
        let distanceDelta = percentDelta(current: distance?.value, average: distance?.average)
        let energyDelta = percentDelta(current: energy?.value, average: energy?.average)

        let sleepUp = sleepDeltaPercent > 0.05
        let sleepDown = sleepDeltaPercent < -0.05

        let movementUp = max(stepsDelta, distanceDelta, energyDelta) > 0.08
        let movementDown = min(stepsDelta, distanceDelta, energyDelta) < -0.08

        if sleepDown && movementUp {
            return "Sleep was down, but movement was above average."
        }
        if sleepUp && movementDown {
            return "You slept more, but moved less than usual."
        }
        if sleepDown && movementDown {
            return "Sleep and movement were both below average."
        }
        if sleepUp && movementUp {
            return "Strong day: sleep and movement were above average."
        }
        if movementUp {
            return "Movement was above average yesterday."
        }
        if movementDown {
            return "Movement was below average yesterday."
        }
        return "Yesterday was close to your typical day."
    }

    private func percentDelta(current: Double?, average: Double?) -> Double {
        guard let current, let average, average > 0 else { return 0 }
        return (current - average) / average
    }
}

private struct SleepBaseline {
    let avgDuration: TimeInterval
    let avgInBed: TimeInterval
    let avgEfficiency: Double
    let avgBedtimeMinutes: Double?
    let avgWakeTimeMinutes: Double?
}
