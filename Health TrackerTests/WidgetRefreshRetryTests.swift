import Foundation
import Testing
@testable import Health_Tracker

/// The publish path had a guard with no recovery behind it.
///
/// `DataSafetyTests.anUnreadableStoreIsNeverPublishedToTheWidget` proves the
/// refusal, which is the right half of the behaviour. Nothing proved what
/// happens *next*, and the answer was nothing at all: the run that woke the app
/// was reported to HealthKit as handled, the widget's own timeline books its
/// next refresh for tomorrow, and the Lock Screen went on asking for a run that
/// was already in the bank.
@MainActor
struct WidgetRefreshRetryTests {
    /// Stands in for the whole read-and-publish, so these tests are about the
    /// retry policy rather than about HealthKit or file protection.
    private final class Publisher {
        var succeeds = false
        private(set) var attempts = 0

        func publish() -> Bool {
            attempts += 1
            return succeeds
        }
    }

    private func makeRefresh(
        _ publisher: Publisher,
        center: NotificationCenter,
        unlock: Notification.Name
    ) -> TodayWidgetRefresh {
        let refresh = TodayWidgetRefresh()
        refresh.start(center: center, unlockNotification: unlock) { publisher.publish() }
        return refresh
    }

    private var unlock: Notification.Name { Notification.Name("test.protected-data-available") }

    @Test func aPublishThatCouldNotBeWrittenIsRemembered() {
        let publisher = Publisher()
        let refresh = makeRefresh(publisher, center: NotificationCenter(), unlock: unlock)
        defer { refresh.stop() }

        refresh.run()

        #expect(publisher.attempts == 1)
        #expect(refresh.isPending)
    }

    @Test func aPublishThatLandedOwesNothing() {
        let publisher = Publisher()
        publisher.succeeds = true
        let refresh = makeRefresh(publisher, center: NotificationCenter(), unlock: unlock)
        defer { refresh.stop() }

        refresh.run()

        #expect(!refresh.isPending)
    }

    /// The whole point. The run landed while the phone was locked, the store was
    /// unreadable, and the first unlock is the moment that stops being true.
    @Test func theFirstUnlockRepublishesTheRunThatWasLostToALockedStore() {
        let publisher = Publisher()
        let center = NotificationCenter()
        let refresh = makeRefresh(publisher, center: center, unlock: unlock)
        defer { refresh.stop() }

        refresh.run()
        #expect(refresh.isPending)

        publisher.succeeds = true
        center.post(name: unlock, object: nil)

        #expect(publisher.attempts == 2)
        #expect(!refresh.isPending)
    }

    /// An unlock happens dozens of times a day and a widget reload is budgeted.
    /// Restating a Lock Screen that is already right is the cheapest way to run
    /// out of the reloads the mid-lift rest clock actually needs.
    @Test func anUnlockWithNothingOwedSpendsNoReload() {
        let publisher = Publisher()
        publisher.succeeds = true
        let center = NotificationCenter()
        let refresh = makeRefresh(publisher, center: center, unlock: unlock)
        defer { refresh.stop() }

        refresh.run()
        center.post(name: unlock, object: nil)
        center.post(name: unlock, object: nil)

        #expect(publisher.attempts == 1)
    }

    /// A phone that is unlocked but whose store is still broken keeps the debt
    /// rather than quietly writing it off.
    @Test func anUnlockThatStillCannotPublishStaysArmed() {
        let publisher = Publisher()
        let center = NotificationCenter()
        let refresh = makeRefresh(publisher, center: center, unlock: unlock)
        defer { refresh.stop() }

        refresh.run()
        center.post(name: unlock, object: nil)

        #expect(publisher.attempts == 2)
        #expect(refresh.isPending)
    }

    /// The foreground path publishes from a store it knows is readable, so it
    /// settles the debt directly instead of leaving the unlock hook to fire on
    /// every unlock for the rest of the day.
    @Test func theForegroundPublishSettlesAPendingRetry() {
        let publisher = Publisher()
        let center = NotificationCenter()
        let refresh = makeRefresh(publisher, center: center, unlock: unlock)
        defer { refresh.stop() }

        refresh.run()
        #expect(refresh.isPending)

        refresh.clearPending()
        center.post(name: unlock, object: nil)

        #expect(publisher.attempts == 1)
        #expect(!refresh.isPending)
    }

    /// `start` is called once from `App.init`, but nothing stops a future caller
    /// from calling it again. Two observers on one notification means two
    /// reloads per unlock, which is the budget failure above with extra steps.
    @Test func startingTwiceDoesNotDoubleTheUnlockHook() {
        let publisher = Publisher()
        let center = NotificationCenter()
        let refresh = makeRefresh(publisher, center: center, unlock: unlock)
        defer { refresh.stop() }
        refresh.start(center: center, unlockNotification: unlock) { publisher.publish() }

        refresh.run()
        center.post(name: unlock, object: nil)

        #expect(publisher.attempts == 2)
    }
}
