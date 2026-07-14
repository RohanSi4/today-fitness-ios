import Foundation
import Testing
@testable import Health_Tracker

struct SleepScoreTests {
    @Test func idealSleepCanEarnAHighScore() {
        let result = SleepScoreCalculator.score(
            duration: 8 * 3600,
            inBed: 8.3 * 3600,
            wakeTimeMinutes: 430,
            avgWakeTimeMinutes: 420
        )

        #expect(result.score >= 90)
        #expect(result.durationSubscore == 1)
        #expect(result.consistencySubscore == 1)
    }

    @Test func weakSubscoreCapsScoreBelowNinety() {
        let result = SleepScoreCalculator.score(
            duration: 8 * 3600,
            inBed: 8.1 * 3600,
            wakeTimeMinutes: 540,
            avgWakeTimeMinutes: 420
        )

        #expect(result.score <= 89)
        #expect(result.consistencySubscore < 0.85)
    }

    @Test func wakeConsistencyHandlesMidnight() {
        let result = SleepScoreCalculator.score(
            duration: 8 * 3600,
            inBed: 8.25 * 3600,
            wakeTimeMinutes: 10,
            avgWakeTimeMinutes: 23 * 60 + 50
        )

        #expect(result.consistencySubscore == 1)
    }

    @Test func efficiencyNeverExceedsOne() {
        let session = SleepSession(
            start: .now,
            end: .now.addingTimeInterval(3600),
            asleepDuration: 4000,
            inBedDuration: 3600
        )
        #expect(session.efficiency == 1)
    }
}

struct SleepSessionAssemblerTests {
    @Test func overlappingStagesAreCountedOnce() throws {
        let start = Date(timeIntervalSince1970: 0)
        let intervals = [
            SleepInterval(start: start, end: start.addingTimeInterval(8 * 3600), kind: .inBed),
            SleepInterval(start: start.addingTimeInterval(1800), end: start.addingTimeInterval(3 * 3600), kind: .asleep),
            SleepInterval(start: start.addingTimeInterval(2 * 3600), end: start.addingTimeInterval(5 * 3600), kind: .asleep),
            SleepInterval(start: start.addingTimeInterval(5 * 3600), end: start.addingTimeInterval(7.5 * 3600), kind: .asleep)
        ]

        let session = try #require(SleepSessionAssembler().sessions(from: intervals).first)

        #expect(session.asleepDuration == Double(7 * 3600))
        #expect(session.inBedDuration == Double(8 * 3600))
    }

    @Test func longGapsCreateSeparateSessions() {
        let start = Date(timeIntervalSince1970: 0)
        let intervals = [
            SleepInterval(start: start, end: start.addingTimeInterval(3600), kind: .asleep),
            SleepInterval(start: start.addingTimeInterval(3 * 3600), end: start.addingTimeInterval(4 * 3600), kind: .asleep)
        ]

        #expect(SleepSessionAssembler().sessions(from: intervals).count == 2)
    }
}

struct RecapMathTests {
    @Test func circularAverageHandlesMidnight() throws {
        let average = try #require(CircularClock.averageMinutes([23 * 60 + 50, 10]))
        #expect(average < 1 || average > 1_439)
    }

    @Test func clockDifferenceTakesShortestRoute() {
        let difference = CircularClock.signedDifference(from: 23 * 60 + 50, to: 10)
        #expect(difference == 20)
    }

    @Test func sevenDayAverageExcludesRecapDay() {
        let calendar = utcCalendar
        let recapDay = Date(timeIntervalSince1970: 10 * 86_400)
        var map: [Date: Double] = [calendar.startOfDay(for: recapDay): 10_000]
        for offset in 1...7 {
            let day = calendar.date(byAdding: .day, value: -offset, to: recapDay)!
            map[calendar.startOfDay(for: day)] = 1_000
        }

        let average = DailyRecapBuilder.averageDailyValue(
            from: map,
            before: recapDay,
            days: 7,
            calendar: calendar
        )
        #expect(average == 1_000)
    }

    @Test func sampleRecapIsDeterministicForDate() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        #expect(DailyRecap.mock(for: date) == DailyRecap.mock(for: date))
        #expect(DailyRecap.mock(for: date).movement.map(\.id) == MovementKind.allCases)
    }

    private var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }
}

@MainActor
struct DailyRecapViewModelTests {
    @Test func unavailableHealthKitAutomaticallyUsesSampleData() async {
        let healthData = StubHealthData(isHealthDataAvailable: false)
        let notifications = StubNotifications()
        let viewModel = DailyRecapViewModel(
            healthData: healthData,
            notifications: notifications,
            calendar: Calendar(identifier: .gregorian)
        )

        await viewModel.load(targetDate: Date(timeIntervalSince1970: 0), useSampleData: false)

        guard case .loaded(_, let source) = viewModel.state else {
            Issue.record("Expected sample recap to load")
            return
        }
        #expect(source.isSample)
        #expect(healthData.authorizationRequests == 0)
    }
}

private final class StubHealthData: HealthDataProviding {
    let isHealthDataAvailable: Bool
    private(set) var authorizationRequests = 0

    init(isHealthDataAvailable: Bool) {
        self.isHealthDataAvailable = isHealthDataAvailable
    }

    func requestAuthorization() async throws {
        authorizationRequests += 1
    }

    func fetchSleepSessions(start: Date, end: Date) async throws -> [SleepSession] { [] }

    func fetchDailyCumulativeStatistics(
        for kind: MovementKind,
        start: Date,
        end: Date
    ) async throws -> [Date: Double] { [:] }
}

private final class StubNotifications: RecapNotificationScheduling {
    func requestAuthorization() async -> Bool { true }

    func scheduleSleepHighlightIfAuthorized(
        wakeTime: Date,
        sleepSummary: SleepSummary,
        recapDate: Date
    ) async {}
}
