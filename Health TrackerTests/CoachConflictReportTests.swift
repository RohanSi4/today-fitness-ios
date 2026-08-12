import Foundation
import Testing
@testable import Health_Tracker

// This text is pasted into the session that changes the training plan, so the
// things it must never contain matter as much as the things it says.

private let utc = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}()

private let weekStart = utc.date(from: DateComponents(year: 2026, month: 8, day: 13))!

private func at(_ offset: Int, _ hour: Int, _ minute: Int = 0) -> Date {
    let day = utc.date(byAdding: .day, value: offset, to: weekStart)!
    return utc.date(bySettingHour: hour, minute: minute, second: 0, of: day)!
}

private func day(
    _ offset: Int,
    miles: Double? = nil,
    lift: WorkoutKind? = nil,
    fit: DayFit
) -> WeeklyDaySnapshot {
    let date = utc.date(byAdding: .day, value: offset, to: weekStart)!
    var snapshot = WeeklyDaySnapshot(
        date: date,
        dateKey: "d\(offset)",
        dayLabel: date.formatted(.dateTime.weekday(.abbreviated)),
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

private func week(_ days: [WeeklyDaySnapshot]) -> WeeklyTrainingSnapshot {
    WeeklyTrainingSnapshot(
        startDate: weekStart,
        endDate: utc.date(byAdding: .day, value: 6, to: weekStart)!,
        prescribedMiles: 40,
        days: days
    )
}

private let clearDay = DayFit.fits(best: FreeWindow(start: at(0, 6), end: at(0, 22)))

struct CoachConflictReportTests {
    @Test func aClearWeekProducesNothingToSend() {
        // No conflicts means the UI has nothing to offer and no reason to appear.
        let snapshot = week([
            day(0, miles: 6, fit: clearDay),
            day(1, lift: .upper, fit: clearDay),
        ])

        #expect(CoachConflictReport.text(for: snapshot, calendar: utc) == nil)
    }

    @Test func aConflictNamesTheDayTheWorkAndTheShortfall() throws {
        let snapshot = week([
            day(0, miles: 6, fit: clearDay),
            day(3, miles: 8, fit: .conflict(
                largest: FreeWindow(start: at(3, 12), end: at(3, 12, 45)),
                shortBy: 65 * 60
            )),
        ])
        let text = try #require(CoachConflictReport.text(for: snapshot, calendar: utc))

        #expect(text.contains("8 mi prescribed"))
        #expect(text.contains("short by 1h 5m"))
        // The coaching session needs the date, not just a weekday, to place it
        // against the training block.
        #expect(text.contains("Aug 16"))
    }

    @Test func aFullyBookedDaySaysSoWithoutAWindow() throws {
        // "Longest free window , short by 0m" would be a broken sentence.
        let snapshot = week([
            day(0, miles: 6, fit: clearDay),
            day(2, lift: .upper, fit: .conflict(largest: nil, shortBy: 0)),
        ])
        let text = try #require(CoachConflictReport.text(for: snapshot, calendar: utc))

        #expect(text.contains("Nothing free in the day."))
        #expect(!text.contains("short by"))
    }

    @Test func theReportSaysWhatElseInTheWeekIsFine() throws {
        // Without this the coach cannot tell whether moving a session has
        // anywhere to go.
        let snapshot = week([
            day(0, miles: 6, fit: clearDay),
            day(1, miles: 4, fit: clearDay),
            day(3, miles: 8, fit: .conflict(largest: nil, shortBy: 3_600)),
        ])
        let text = try #require(CoachConflictReport.text(for: snapshot, calendar: utc))

        #expect(text.contains("The other 2 prescribed days fit."))
    }

    @Test func aWeekWithNoRoomAnywhereSaysThatPlainly() throws {
        let snapshot = week([
            day(0, miles: 6, fit: .conflict(largest: nil, shortBy: 3_600)),
            day(3, miles: 8, fit: .conflict(largest: nil, shortBy: 3_600)),
        ])
        let text = try #require(CoachConflictReport.text(for: snapshot, calendar: utc))

        #expect(text.contains("No other prescribed day in this week has room either."))
    }

    @Test func restDaysAreNotCountedAsDaysThatFit() throws {
        // A rest day "fitting" is meaningless and would inflate the count the
        // coach uses to decide whether a session can be moved.
        let snapshot = week([
            day(0, miles: 6, fit: clearDay),
            day(1, fit: .rest),
            day(3, miles: 8, fit: .conflict(largest: nil, shortBy: 3_600)),
        ])
        let text = try #require(CoachConflictReport.text(for: snapshot, calendar: utc))

        #expect(text.contains("The other 1 prescribed day fits."))
    }

    @Test func theReportStatesItsOwnAssumptions() throws {
        // The coaching session should not have to guess what "free window"
        // meant, or assume more precision than the estimate has.
        let snapshot = week([
            day(3, miles: 8, fit: .conflict(largest: nil, shortBy: 3_600)),
        ])
        let text = try #require(CoachConflictReport.text(for: snapshot, calendar: utc))

        #expect(text.contains("6am and 10pm"))
        #expect(text.contains("changing and showering"))
        #expect(text.contains("Event details are not included."))
    }

    @Test func aConflictOutsideTheDeclaredWeekIsNotReported() {
        // The builder pads days around the plan. A conflict on a day the coach
        // never prescribed is not something to hand back to the coach.
        let snapshot = WeeklyTrainingSnapshot(
            startDate: weekStart,
            endDate: weekStart,
            prescribedMiles: 6,
            days: [
                day(0, miles: 6, fit: clearDay),
                day(4, miles: 12, fit: .conflict(largest: nil, shortBy: 3_600)),
            ]
        )

        #expect(CoachConflictReport.text(for: snapshot, calendar: utc) == nil)
    }
}
