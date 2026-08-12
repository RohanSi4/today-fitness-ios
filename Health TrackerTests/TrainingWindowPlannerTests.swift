import Foundation
import Testing
@testable import Health_Tracker

// The point of this feature is telling him on Sunday that Thursday's long run
// has nowhere to go. These tests are about the cases where a naive version
// would say the wrong thing confidently.

private let utc = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}()

private let day = utc.date(from: DateComponents(year: 2026, month: 8, day: 13))!

private func at(_ hour: Int, _ minute: Int = 0) -> Date {
    utc.date(bySettingHour: hour, minute: minute, second: 0, of: day)!
}

private func busy(_ startHour: Int, _ endHour: Int) -> BusyInterval {
    BusyInterval(start: at(startHour), end: at(endHour))
}

struct TrainingWindowIntervalTests {
    @Test func backToBackMeetingsCollapseIntoOneBlock() {
        // Two meetings that touch arrive as separate events. Left unmerged they
        // leave a zero-length gap that a session could be "offered" in.
        let merged = TrainingWindowPlanner.merge([busy(9, 10), busy(10, 11)])

        #expect(merged == [busy(9, 11)])
    }

    @Test func anEventInsideAnotherDoesNotShortenTheBlock() {
        // A 30-minute call inside a 3-hour block must not truncate the block to
        // its own end time and invent a free afternoon.
        let merged = TrainingWindowPlanner.merge([busy(9, 12), busy(10, 11)])

        #expect(merged == [busy(9, 12)])
    }

    @Test func freeWindowsAreTheGapsBetweenBusyBlocks() {
        let windows = TrainingWindowPlanner.freeWindows(
            busy: [busy(9, 11), busy(14, 15)],
            within: FreeWindow(start: at(6), end: at(22))
        )

        #expect(windows == [
            FreeWindow(start: at(6), end: at(9)),
            FreeWindow(start: at(11), end: at(14)),
            FreeWindow(start: at(15), end: at(22)),
        ])
    }

    @Test func anEventRunningPastTheDayBoundIsClippedNotDropped() {
        // An evening event ending at 11pm still blocks the 8pm-10pm window. If
        // out-of-bounds events were skipped entirely the night would read free.
        let windows = TrainingWindowPlanner.freeWindows(
            busy: [busy(20, 23)],
            within: FreeWindow(start: at(6), end: at(22))
        )

        #expect(windows == [FreeWindow(start: at(6), end: at(20))])
    }

    @Test func aFullyBookedDayHasNoWindows() {
        let windows = TrainingWindowPlanner.freeWindows(
            busy: [busy(5, 23)],
            within: FreeWindow(start: at(6), end: at(22))
        )

        #expect(windows.isEmpty)
    }
}

struct TrainingWindowPaceTests {
    @Test func paceIsLearnedFromRecentRuns() {
        let runs = [run(miles: 5, seconds: 5 * 480), run(miles: 4, seconds: 4 * 500)]

        #expect(TrainingWindowPlanner.learnedPace(from: runs) == 500)
    }

    @Test func aGarbagePaceIsIgnoredRatherThanAveragedIn() {
        // A GPS dropout or a walked cooldown produces a pace no estimate should
        // ever be built on. One of these in the window would otherwise skew
        // every day of the week.
        let runs = [
            run(miles: 5, seconds: 5 * 480),
            run(miles: 1, seconds: 1 * 60),      // 1:00/mi, impossible
            run(miles: 1, seconds: 1 * 1_800),   // 30:00/mi, a walk
        ]

        #expect(TrainingWindowPlanner.learnedPace(from: runs) == 480)
    }

    @Test func noUsableRunsFallsBackToASlowPace() {
        // Overestimating produces a warning that turns out to be unnecessary.
        // Underestimating puts a run into a meeting.
        #expect(
            TrainingWindowPlanner.learnedPace(from: [])
                == TrainingWindowPlanner.fallbackPaceSecondsPerMile
        )
    }

    private func run(miles: Double, seconds: Double) -> RunningWorkoutSummary {
        RunningWorkoutSummary(
            id: UUID(),
            startedAt: day,
            endedAt: day.addingTimeInterval(seconds),
            miles: miles,
            duration: seconds
        )
    }
}

struct TrainingWindowFitTests {
    @Test func aRestDayNeverReportsAConflict() {
        let fit = TrainingWindowPlanner.fit(
            plannedRunMiles: nil,
            plannedLift: nil,
            calendarDay: CalendarDay(date: day, busy: [busy(6, 22)], allDayCount: 0),
            date: day,
            paceSecondsPerMile: 600,
            calendar: utc
        )

        #expect(fit == .rest)
    }

    @Test func aPrescribedDayWithNoCalendarIsUnknownNotFine() {
        // Missing calendar access must not render as "everything fits." That is
        // the failure the run week already had with an unread Health store.
        let fit = TrainingWindowPlanner.fit(
            plannedRunMiles: 6,
            plannedLift: nil,
            calendarDay: nil,
            date: day,
            paceSecondsPerMile: 600,
            calendar: utc
        )

        #expect(fit == .unknown)
    }

    @Test func anEmptyDayFitsTheLongRun() {
        let fit = TrainingWindowPlanner.fit(
            plannedRunMiles: 10,
            plannedLift: nil,
            calendarDay: CalendarDay(date: day, busy: [], allDayCount: 0),
            date: day,
            paceSecondsPerMile: 600,
            calendar: utc
        )

        #expect(fit == .fits(best: FreeWindow(start: at(6), end: at(22))))
    }

    @Test func aBookedDayReportsHowFarShortItIs() {
        // 8 miles at 10:00/mi is 80 minutes of running plus 30 of overhead, so
        // 110 minutes are needed. The largest gap is 45.
        let fit = TrainingWindowPlanner.fit(
            plannedRunMiles: 8,
            plannedLift: nil,
            calendarDay: CalendarDay(
                date: day,
                busy: [busy(6, 12), BusyInterval(start: at(12, 45), end: at(22))],
                allDayCount: 0
            ),
            date: day,
            paceSecondsPerMile: 600,
            calendar: utc
        )

        #expect(fit.isConflict)
        if case .conflict(_, let shortBy) = fit {
            #expect(shortBy == 65 * 60)
        }
    }

    @Test func overheadIsWhatDecidesATightDay() {
        // 30 minutes of running into a 45-minute gap looks fine until changing
        // and showering are counted. This is the case the feature exists for.
        let needs = TrainingWindowPlanner.needs(
            plannedRunMiles: 3,
            plannedLift: nil,
            paceSecondsPerMile: 600
        )
        let gap = [FreeWindow(start: at(12), end: at(12, 45))]

        // Typed explicitly: an untyped literal against [TimeInterval] compiles
        // locally and is ambiguous on the CI toolchain.
        let expectedWorking: [TimeInterval] = [30 * 60]

        #expect(needs.map(\.working) == expectedWorking)
        #expect(TrainingWindowPlanner.fit(needs: needs, windows: gap).isConflict)
    }

    @Test func aRunAndALiftNeedTwoSeparateHomes() {
        // A run is 70 minutes all-in and a lift is 80. Two 90-minute gaps hold
        // one each. A single 90-minute gap holds either alone and neither
        // together, which is the case a "largest free window" check gets wrong.
        let needs = TrainingWindowPlanner.needs(
            plannedRunMiles: 4,
            plannedLift: .upper,
            paceSecondsPerMile: 600
        )

        let two = [
            FreeWindow(start: at(6), end: at(7, 30)),
            FreeWindow(start: at(17), end: at(18, 30)),
        ]
        let one = [FreeWindow(start: at(6), end: at(7, 30))]

        #expect(!TrainingWindowPlanner.fit(needs: needs, windows: two).isConflict)
        #expect(TrainingWindowPlanner.fit(needs: needs, windows: one).isConflict)
    }

    @Test func aSessionThatOnlyJustFitsIsFlaggedTight() {
        // 4 miles at 10:00/mi plus overhead is 70 minutes. A 75-minute gap
        // technically holds it, and saying "fits" would be misleading.
        let needs = TrainingWindowPlanner.needs(
            plannedRunMiles: 4,
            plannedLift: nil,
            paceSecondsPerMile: 600
        )
        let fit = TrainingWindowPlanner.fit(
            needs: needs,
            windows: [FreeWindow(start: at(12), end: at(13, 15))]
        )

        #expect(fit.isTight)
    }
}
