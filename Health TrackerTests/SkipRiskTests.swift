import Foundation
import Testing
@testable import Health_Tracker

// This sentence is about today, so it is read as being about a decision. That
// makes the thresholds stricter than the retrospective's, not looser.

private let utc = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}()

private let day = utc.date(from: DateComponents(year: 2026, month: 8, day: 13))!

private func history(_ entries: [(minutes: Double, trained: Bool)]) -> [ScheduleLoadDay] {
    entries.enumerated().map { index, entry in
        ScheduleLoadDay(
            date: utc.date(byAdding: .day, value: -(index + 1), to: day)!,
            busyMinutes: entry.minutes,
            trained: entry.trained
        )
    }
}

private func days(_ count: Int, minutes: Double, trained: Int) -> [(Double, Bool)] {
    (0..<count).map { (minutes, $0 < trained) }
}

struct SkipRiskGateTests {
    @Test func tooFewComparableDaysSaysNothing() {
        // Seven similar days is not a base rate worth acting on.
        let past = history(days(7, minutes: 300, trained: 1).map { (minutes: $0.0, trained: $0.1) })

        #expect(SkipRisk.outlook(forBusyMinutes: 300, history: past) == nil)
    }

    @Test func daysThatLookNothingLikeTodayAreNotComparable() {
        // A calendar full of empty days says nothing about a seven-hour one.
        let past = history(days(20, minutes: 10, trained: 18).map { (minutes: $0.0, trained: $0.1) })

        #expect(SkipRisk.outlook(forBusyMinutes: 420, history: past) == nil)
    }

    @Test func theComparableWindowIsAWindowNotABoundary() throws {
        // 179 and 181 minutes must not be treated as different kinds of day.
        let past = history(days(10, minutes: 179, trained: 2).map { (minutes: $0.0, trained: $0.1) })
        let outlook = try #require(SkipRisk.outlook(forBusyMinutes: 181, history: past))

        #expect(outlook.comparableDays == 10)
    }
}

struct SkipRiskOutlookTests {
    @Test func aLeaningHistoryIsWorthSaying() throws {
        let past = history(days(12, minutes: 400, trained: 3).map { (minutes: $0.0, trained: $0.1) })
        let outlook = try #require(SkipRisk.outlook(forBusyMinutes: 400, history: past))

        #expect(outlook.comparableDays == 12)
        #expect(outlook.trainedDays == 3)
        #expect(outlook.isNoteworthy)
    }

    @Test func aCoinFlipIsNotWorthSaying() throws {
        // Presenting a 50/50 split as insight is how the feature earns being
        // ignored on the day it has something.
        let past = history(days(12, minutes: 400, trained: 6).map { (minutes: $0.0, trained: $0.1) })
        let outlook = try #require(SkipRisk.outlook(forBusyMinutes: 400, history: past))

        #expect(!outlook.isNoteworthy)
    }

    @Test func aStronglyPositiveHistoryIsAlsoWorthSaying() throws {
        // The feature is not only a warning. "You always get this done" is a
        // true and useful thing to know on a day that looks intimidating.
        let past = history(days(10, minutes: 60, trained: 10).map { (minutes: $0.0, trained: $0.1) })
        let outlook = try #require(SkipRisk.outlook(forBusyMinutes: 60, history: past))

        #expect(outlook.isNoteworthy)
    }

    @Test func theSentenceIsHistoryNotForecast() throws {
        let past = history(days(12, minutes: 400, trained: 3).map { (minutes: $0.0, trained: $0.1) })
        let outlook = try #require(SkipRisk.outlook(forBusyMinutes: 400, history: past))
        let sentence = SkipRisk.sentence(outlook)

        #expect(sentence.contains("12 past days"))
        #expect(sentence.contains("you trained 3"))
        // No probability, no risk score. Either would be believed well past
        // what this sample can carry.
        #expect(!sentence.contains("%"))
        #expect(!sentence.lowercased().contains("likely"))
        #expect(!sentence.lowercased().contains("risk"))
    }
}

struct SkipRiskMeasureTests {
    @Test func todayIsMeasuredTheSameWayHistoryWas() {
        // A day compared against a differently-defined version of itself would
        // make every comparison quietly wrong.
        let busy = BusyInterval(
            start: utc.date(bySettingHour: 9, minute: 0, second: 0, of: day)!,
            end: utc.date(bySettingHour: 12, minute: 0, second: 0, of: day)!
        )
        let calendarDay = CalendarDay(date: day, busy: [busy], allDayCount: 0)

        let direct = SkipRisk.busyMinutes(today: calendarDay, date: day, calendar: utc)

        // The retrospective path, run over the same day, must agree.
        let viaHistory = ScheduleLoadAnalysis.days(
            calendarDays: [calendarDay],
            runs: [],
            lifts: [],
            now: utc.date(byAdding: .day, value: 1, to: day)!,
            calendar: utc
        )

        #expect(direct == 180)
        #expect(viaHistory.first?.busyMinutes == direct)
    }

    @Test func lateNightCommitmentsDoNotCountAsLoad() {
        let busy = BusyInterval(
            start: utc.date(bySettingHour: 22, minute: 30, second: 0, of: day)!,
            end: utc.date(bySettingHour: 23, minute: 30, second: 0, of: day)!
        )

        let minutes = SkipRisk.busyMinutes(
            today: CalendarDay(date: day, busy: [busy], allDayCount: 0),
            date: day,
            calendar: utc
        )

        #expect(minutes == 0)
    }
}
