import Foundation
import Testing
@testable import Health_Tracker

// The morning prompt exists to catch the scale inside a routine. Moving it is
// only ever worth doing when he has to be somewhere before it would have fired.

private let utc = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}()

private let day = utc.date(from: DateComponents(year: 2026, month: 8, day: 13))!

private func at(_ hour: Int, _ minute: Int = 0) -> Date {
    utc.date(bySettingHour: hour, minute: minute, second: 0, of: day)!
}

private func reminder(firstCommitment: Date?) -> DateComponents {
    NotificationManager.morningReminder(
        on: day,
        firstCommitment: firstCommitment,
        calendar: utc
    )
}

struct MorningReminderTimingTests {
    @Test func anEmptyCalendarKeepsTheUsualTime() {
        let time = reminder(firstCommitment: nil)

        #expect(time.hour == NotificationManager.defaultMorningHour)
        #expect(time.minute == NotificationManager.defaultMorningMinute)
    }

    @Test func anEarlyMeetingPullsThePromptForward() {
        // 8:00 start, 45 minutes of lead, so 7:15.
        let time = reminder(firstCommitment: at(8))

        #expect(time.hour == 7)
        #expect(time.minute == 15)
    }

    @Test func aLateFirstMeetingDoesNotDelayTheWeighIn() {
        // The reminder is about the morning routine, not the meeting. A 4pm
        // first commitment must not push the weigh-in to the afternoon.
        let time = reminder(firstCommitment: at(16))

        #expect(time.hour == NotificationManager.defaultMorningHour)
        #expect(time.minute == NotificationManager.defaultMorningMinute)
    }

    @Test func aMeetingJustAfterTheDefaultChangesNothing() {
        // 9:30 minus lead is 8:45, later than 8:30, so there is nothing to fix.
        let time = reminder(firstCommitment: at(9, 30))

        #expect(time.hour == NotificationManager.defaultMorningHour)
        #expect(time.minute == NotificationManager.defaultMorningMinute)
    }

    @Test func aDawnFlightDoesNotProduceADawnNotification() {
        // 6:30 minus lead is 5:45. Firing then is how someone turns
        // notifications off for good, so the floor wins.
        let time = reminder(firstCommitment: at(6, 30))

        #expect(time.hour == NotificationManager.earliestMorningHour)
        #expect(time.minute == 0)
    }

    @Test func aCommitmentOnAnotherDayIsIgnored() {
        // The map is keyed by day, but a stale or mismatched entry must not
        // reschedule a different morning.
        let tomorrow = utc.date(byAdding: .day, value: 1, to: at(7))!

        let time = reminder(firstCommitment: tomorrow)

        #expect(time.hour == NotificationManager.defaultMorningHour)
        #expect(time.minute == NotificationManager.defaultMorningMinute)
    }
}
