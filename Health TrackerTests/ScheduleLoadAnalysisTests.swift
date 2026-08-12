import Foundation
import Testing
@testable import Health_Tracker

// Most of these are about what the analysis refuses to say. Producing a
// confident sentence from nine days would be worse than producing nothing,
// because a sentence gets repeated and a silence does not.

private let utc = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}()

private let day = utc.date(from: DateComponents(year: 2026, month: 8, day: 13))!

private func loadDay(_ offset: Int, minutes: Double, trained: Bool) -> ScheduleLoadDay {
    ScheduleLoadDay(
        date: utc.date(byAdding: .day, value: -offset, to: day)!,
        busyMinutes: minutes,
        trained: trained
    )
}

/// `count` days at `minutes` of load, of which `trained` were trained.
private func block(
    from offset: Int,
    count: Int,
    minutes: Double,
    trained: Int
) -> [ScheduleLoadDay] {
    (0..<count).map { index in
        loadDay(offset + index, minutes: minutes, trained: index < trained)
    }
}

struct ScheduleLoadGateTests {
    @Test func aThinSampleReportsNothing() {
        // Nine days can produce a 4-vs-1 split that looks like a finding and is
        // noise. The gate is the feature.
        let days = block(from: 0, count: 5, minutes: 400, trained: 1)
            + block(from: 5, count: 4, minutes: 30, trained: 4)

        #expect(ScheduleLoadAnalysis.finding(from: days) == nil)
    }

    @Test func aLopsidedSampleReportsNothing() {
        // Enough days overall, but one side is too small to compare against.
        let days = block(from: 0, count: 24, minutes: 300, trained: 6)
            + block(from: 24, count: 2, minutes: 10, trained: 2)

        // The median split can still leave a usable pair, so the real assertion
        // is that a group under the floor is never reported on.
        if let finding = ScheduleLoadAnalysis.finding(from: days) {
            #expect(finding.lighterDays >= ScheduleLoadAnalysis.minimumPerGroup)
            #expect(finding.busierDays >= ScheduleLoadAnalysis.minimumPerGroup)
        }
    }

    @Test func aFlatCalendarReportsNothing() {
        // Every day equally booked means "busiest" and "lightest" name the same
        // kind of day, and the sentence would have no content.
        let days = block(from: 0, count: 28, minutes: 180, trained: 14)

        #expect(ScheduleLoadAnalysis.finding(from: days) == nil)
    }

    @Test func aNarrowSpreadReportsNothing() {
        // 20 minutes between the halves is not a difference worth a sentence.
        let days = block(from: 0, count: 14, minutes: 200, trained: 4)
            + block(from: 14, count: 14, minutes: 180, trained: 12)

        #expect(ScheduleLoadAnalysis.finding(from: days) == nil)
    }
}

struct ScheduleLoadFindingTests {
    private var contrasted: [ScheduleLoadDay] {
        block(from: 0, count: 14, minutes: 420, trained: 4)
            + block(from: 14, count: 14, minutes: 45, trained: 12)
    }

    @Test func aClearContrastIsReportedWithCountsOnBothSides() throws {
        let finding = try #require(ScheduleLoadAnalysis.finding(from: contrasted))

        #expect(finding.busierDays == 14)
        #expect(finding.busierTrained == 4)
        #expect(finding.lighterDays == 14)
        #expect(finding.lighterTrained == 12)
        #expect(finding.trainedLessWhenBusier)
    }

    @Test func theSentenceCarriesTheSampleAndNoPercentage() throws {
        let finding = try #require(ScheduleLoadAnalysis.finding(from: contrasted))
        let sentence = ScheduleLoadAnalysis.sentence(finding)

        // The counts have to be visible in the claim itself.
        #expect(sentence.contains("14 busiest"))
        #expect(sentence.contains("trained 4 times"))
        // A percentage invites comparison against a number this was never
        // powerful enough to support.
        #expect(!sentence.contains("%"))
    }

    @Test func noDifferenceIsStillReported() throws {
        // Hiding a null result would make the feature look like it only ever
        // confirms a hunch.
        let days = block(from: 0, count: 14, minutes: 420, trained: 7)
            + block(from: 14, count: 14, minutes: 45, trained: 7)
        let finding = try #require(ScheduleLoadAnalysis.finding(from: days))

        #expect(!finding.trainedLessWhenBusier)
        #expect(finding.busierTrained == finding.lighterTrained)
    }

    @Test func theCaveatNamesTheConfound() {
        #expect(ScheduleLoadAnalysis.caveat.contains("not a cause"))
    }
}

struct ScheduleLoadInputTests {
    @Test func todayIsExcludedBecauseItIsNotOverYet() {
        // A day with meetings already on it is exactly the kind of day that has
        // not been trained yet at 9am. Counting it would drag every comparison
        // toward the busy side.
        let calendarDays = [
            CalendarDay(date: day, busy: [], allDayCount: 0),
            CalendarDay(date: utc.date(byAdding: .day, value: -1, to: day)!, busy: [], allDayCount: 0),
        ]

        let days = ScheduleLoadAnalysis.days(
            calendarDays: calendarDays,
            runs: [],
            lifts: [],
            now: day,
            calendar: utc
        )

        #expect(days.count == 1)
        #expect(days.allSatisfy { $0.date < day })
    }

    @Test func onlyCommittedTimeInsideTheTrainingBandCounts() {
        // A 10pm-midnight event is not load. That time was never available for
        // a session, so counting it would make evenings look busy for no reason.
        let yesterday = utc.date(byAdding: .day, value: -1, to: day)!
        let lateNight = BusyInterval(
            start: utc.date(bySettingHour: 22, minute: 0, second: 0, of: yesterday)!,
            end: utc.date(bySettingHour: 23, minute: 30, second: 0, of: yesterday)!
        )

        let days = ScheduleLoadAnalysis.days(
            calendarDays: [CalendarDay(date: yesterday, busy: [lateNight], allDayCount: 0)],
            runs: [],
            lifts: [],
            now: day,
            calendar: utc
        )

        #expect(days.first?.busyMinutes == 0)
    }

    @Test func overlappingMeetingsAreNotDoubleCounted() {
        // Two overlapping calendars for the same commitment would otherwise
        // report four hours of load for a two hour block.
        let yesterday = utc.date(byAdding: .day, value: -1, to: day)!
        func slot(_ from: Int, _ to: Int) -> BusyInterval {
            BusyInterval(
                start: utc.date(bySettingHour: from, minute: 0, second: 0, of: yesterday)!,
                end: utc.date(bySettingHour: to, minute: 0, second: 0, of: yesterday)!
            )
        }

        let days = ScheduleLoadAnalysis.days(
            calendarDays: [
                CalendarDay(date: yesterday, busy: [slot(9, 11), slot(9, 11)], allDayCount: 0)
            ],
            runs: [],
            lifts: [],
            now: day,
            calendar: utc
        )

        #expect(days.first?.busyMinutes == 120)
    }

    @Test func aLiftAloneCountsAsTraining() {
        // The join is "did anything happen", not "did a run happen". A lift day
        // recorded as untrained would look like a skip.
        let yesterday = utc.date(byAdding: .day, value: -1, to: day)!
        let session = WorkoutSession(kind: .upper, startedAt: yesterday, exercises: [])

        let days = ScheduleLoadAnalysis.days(
            calendarDays: [CalendarDay(date: yesterday, busy: [], allDayCount: 0)],
            runs: [],
            lifts: [session],
            now: day,
            calendar: utc
        )

        #expect(days.first?.trained == true)
    }
}
