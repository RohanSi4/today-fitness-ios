import Foundation
import Testing
@testable import Health_Tracker

private let utc = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}()

private let day = utc.date(from: DateComponents(year: 2026, month: 8, day: 13))!

private func at(_ hour: Int, _ minute: Int = 0) -> Date {
    utc.date(bySettingHour: hour, minute: minute, second: 0, of: day)!
}

private func snapshot(_ days: [WeeklyDaySnapshot]) -> WeeklyTrainingSnapshot {
    WeeklyTrainingSnapshot(
        startDate: day,
        endDate: utc.date(byAdding: .day, value: 6, to: day)!,
        prescribedMiles: 40,
        days: days
    )
}

private func planned(
    _ offset: Int,
    label: String,
    miles: Double? = nil,
    lift: WorkoutKind? = nil,
    fit: DayFit
) -> WeeklyDaySnapshot {
    let date = utc.date(byAdding: .day, value: offset, to: day)!
    var snapshot = WeeklyDaySnapshot(
        date: date,
        dateKey: label,
        dayLabel: label,
        plannedRunMiles: miles,
        plannedLift: lift,
        plannedOther: nil,
        isKeyDay: false,
        run: nil,
        lift: nil,
        extraLift: nil
    )
    snapshot.fit = fit
    return snapshot
}

struct TrainingBriefTodayTests {
    @Test func aRestDaySaysNothingAboutTime() {
        #expect(TrainingBrief.today(.rest, calendar: utc) == nil)
    }

    @Test func noCalendarAccessSaysNothingRatherThanSayingYouAreFree() {
        // The failure this guards against is the one the run week already had:
        // an unread source rendering as a confident zero.
        #expect(TrainingBrief.today(.unknown, calendar: utc) == nil)
    }

    @Test func aClearDayNamesTheWindow() {
        let line = TrainingBrief.today(
            .fits(best: FreeWindow(start: at(17), end: at(20))),
            calendar: utc
        )

        #expect(line?.contains("Best window") == true)
    }

    @Test func aTightDaySaysSoBeforeNamingTheWindow() {
        let line = TrainingBrief.today(
            .tight(best: FreeWindow(start: at(12), end: at(13))),
            calendar: utc
        )

        #expect(line?.hasPrefix("Tight today") == true)
    }

    @Test func aConflictLeadsWithHowShortTheDayIs() {
        let line = TrainingBrief.today(
            .conflict(largest: FreeWindow(start: at(12), end: at(12, 45)), shortBy: 65 * 60),
            calendar: utc
        )

        #expect(line?.contains("Short 1h 5m") == true)
    }

    @Test func aFullyBookedDayStillSaysSomethingUseful() {
        // No window to name must not produce a sentence with a blank in it.
        let line = TrainingBrief.today(.conflict(largest: nil, shortBy: 0), calendar: utc)

        #expect(line == "No room on the calendar today")
    }
}

struct TrainingBriefWeekTests {
    @Test func aClearWeekShowsNoBanner() {
        // A banner that appears every day stops being read on the day it matters.
        let week = snapshot([
            planned(0, label: "Thu", miles: 6, fit: .fits(best: FreeWindow(start: at(6), end: at(22)))),
            planned(1, label: "Fri", fit: .rest),
        ])

        #expect(TrainingBrief.week(week, calendar: utc) == nil)
    }

    @Test func oneBadDayIsNamedWithWhatDoesNotFit() {
        let week = snapshot([
            planned(0, label: "Thu", miles: 8, fit: .conflict(largest: nil, shortBy: 3_600)),
            planned(1, label: "Fri", miles: 4, fit: .fits(best: FreeWindow(start: at(6), end: at(22)))),
        ])

        #expect(TrainingBrief.week(week, calendar: utc) == "Thu has no room for 8 mi")
    }

    @Test func severalBadDaysAreCountedAndListed() {
        let week = snapshot([
            planned(0, label: "Thu", miles: 8, fit: .conflict(largest: nil, shortBy: 3_600)),
            planned(1, label: "Fri", lift: .upper, fit: .conflict(largest: nil, shortBy: 1_800)),
        ])

        #expect(TrainingBrief.week(week, calendar: utc) == "2 days have no room: Thu, Fri")
    }

    @Test func aConflictOutsideTheDeclaredWeekIsNotCounted() {
        // The builder pads days around the plan. A conflict on a day the coach
        // never prescribed is not a conflict worth a banner.
        let week = WeeklyTrainingSnapshot(
            startDate: day,
            endDate: day,
            prescribedMiles: 6,
            days: [
                planned(0, label: "Thu", miles: 6, fit: .fits(best: FreeWindow(start: at(6), end: at(22)))),
                planned(3, label: "Sun", miles: 12, fit: .conflict(largest: nil, shortBy: 3_600)),
            ]
        )

        #expect(TrainingBrief.week(week, calendar: utc) == nil)
    }

    @Test func aRunAndALiftAreBothNamed() {
        let week = snapshot([
            planned(0, label: "Thu", miles: 5, lift: .upper, fit: .conflict(largest: nil, shortBy: 60)),
        ])

        #expect(TrainingBrief.week(week, calendar: utc) == "Thu has no room for 5 mi and a lift")
    }
}

struct TrainingBriefFormattingTests {
    @Test func shortfallRoundsUpSoItIsNeverOptimistic() {
        // 44.6 minutes reported as 44 invites him to try to make it work.
        #expect(TrainingBrief.minutes(44.6 * 60) == "45m")
        #expect(TrainingBrief.minutes(60 * 60) == "1h")
        #expect(TrainingBrief.minutes(95 * 60) == "1h 35m")
    }

    @Test func aTinyShortfallStillReadsAsAMinute() {
        // "0m short" is a sentence that makes the feature look broken.
        #expect(TrainingBrief.minutes(5) == "1m")
    }
}
