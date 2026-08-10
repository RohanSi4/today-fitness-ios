import Foundation
import Testing
@testable import Health_Tracker

/// The widget's `load()` path had no coverage at all. Every existing widget test
/// exercised `makeSnapshot`, the publishing side, so nothing ever asked what the
/// widget shows when the stored payload is a day old, which is its state every
/// single morning before the app is opened.
struct WidgetStalenessTests {
    private static let utc = TimeZone(identifier: "UTC")!

    private func calendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = Self.utc
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 9) -> Date {
        var components = DateComponents()
        components.year = year; components.month = month; components.day = day; components.hour = hour
        return calendar().date(from: components)!
    }

    /// A snapshot stamped with an explicit Monday-to-Sunday plan week, matching
    /// how the coach's plan actually runs rather than the Sunday-start locale week.
    private func snapshot(
        on day: Date,
        weekStart: Date,
        weekEnd: Date,
        miles: Double = 21,
        lifts: Int = 3,
        calendar: Calendar
    ) -> TodayWidgetSnapshot {
        TodayWidgetSnapshot(
            generatedAt: day,
            dateKey: TodayWidgetSnapshot.dayKey(for: day, calendar: calendar),
            phase: .done,
            headline: "Everything done",
            detail: "Nice work",
            symbolName: "checkmark",
            deepLink: URL(string: "today://week")!,
            week: TodayWidgetWeek(
                completedMiles: miles,
                plannedMiles: 35,
                completedRuns: 4,
                completedLifts: lifts
            ),
            weekStartKey: TodayWidgetSnapshot.dayKey(for: weekStart, calendar: calendar),
            weekEndKey: TodayWidgetSnapshot.dayKey(for: weekEnd, calendar: calendar)
        )
    }

    /// The plan week that contains Jul 27 - Aug 2, 2026 (a Monday to a Sunday).
    private var planWeek: (start: Date, end: Date) {
        (date(2026, 7, 27), date(2026, 8, 2))
    }

    @Test func todaysSnapshotIsReturnedUnchanged() {
        let calendar = calendar()
        let today = date(2026, 7, 29)
        let stored = snapshot(on: today, weekStart: planWeek.start, weekEnd: planWeek.end, calendar: calendar)

        let carried = stored.carriedForward(to: today, calendar: calendar)

        #expect(carried == stored)
    }

    @Test func aNewDayKeepsTheWeekAndOnlyResetsTheDailyPrompt() throws {
        // The actual bug: on Thursday morning, before opening the app, the Lock
        // Screen claimed zero miles for a week with 21 in it.
        let calendar = calendar()
        let wednesday = date(2026, 7, 29)
        let thursday = date(2026, 7, 30)
        let stored = snapshot(on: wednesday, weekStart: planWeek.start, weekEnd: planWeek.end, miles: 21, lifts: 3, calendar: calendar)

        let carried = try #require(stored.carriedForward(to: thursday, calendar: calendar))

        #expect(carried.week.completedMiles == 21)
        #expect(carried.week.completedLifts == 3)
        #expect(carried.week.plannedMiles == 35)
        // The daily half is correctly retired.
        #expect(carried.phase == .weight)
        #expect(carried.headline == "Log morning weight")
        #expect(carried.dateKey == TodayWidgetSnapshot.dayKey(for: thursday, calendar: calendar))
        #expect(carried.deepLink.host == "weight")
    }

    @Test func aNewTrainingWeekDropsTheTotalsRatherThanCarryingThemOver() {
        // Monday starts a new week, so last week's 21 miles must not follow it.
        let calendar = calendar()
        let sunday = date(2026, 8, 2)
        let monday = date(2026, 8, 3)
        let stored = snapshot(on: sunday, weekStart: planWeek.start, weekEnd: planWeek.end, miles: 21, calendar: calendar)

        #expect(stored.carriedForward(to: monday, calendar: calendar) == nil)
    }

    @Test func aPayloadFromAnOlderBuildWithNoWeekStampIsNotCarried() {
        // Optional field, so an old cached payload still decodes. It must fail
        // safe: no stamp means no way to know the week, so do not guess.
        let calendar = calendar()
        let wednesday = date(2026, 7, 29)
        var stored = snapshot(on: wednesday, weekStart: planWeek.start, weekEnd: planWeek.end, calendar: calendar)
        stored.weekStartKey = nil
        stored.weekEndKey = nil

        #expect(stored.carriedForward(to: date(2026, 7, 30), calendar: calendar) == nil)
    }

    @Test func aWeekOldPayloadIsNotCarriedEvenOnTheSameWeekday() {
        // Same weekday one week later hashes to a different week start, so this
        // must not sneak through.
        let calendar = calendar()
        let stored = snapshot(on: date(2026, 7, 29), weekStart: planWeek.start, weekEnd: planWeek.end, calendar: calendar)

        #expect(stored.carriedForward(to: date(2026, 8, 5), calendar: calendar) == nil)
    }

    @Test func theBoundaryIsThePlanWeekNotTheLocaleWeek() throws {
        // This is the case that caught the first implementation. The plan week
        // runs Mon Jul 27 to Sun Aug 2, but `Calendar.current` weeks start on
        // Sunday here, so deriving the week inside the widget put Sun Aug 2 and
        // Mon Aug 3 in the same week and carried a finished week's miles into a
        // fresh one.
        let calendar = calendar()
        let stored = snapshot(
            on: date(2026, 7, 29),
            weekStart: planWeek.start,
            weekEnd: planWeek.end,
            calendar: calendar
        )

        // Sunday is the last day of the plan week, so totals still stand.
        let sunday = try #require(stored.carriedForward(to: date(2026, 8, 2), calendar: calendar))
        #expect(sunday.week.completedMiles == 21)

        // Monday begins a new plan week.
        #expect(stored.carriedForward(to: date(2026, 8, 3), calendar: calendar) == nil)
    }

    @Test func aDayBeforeTheStoredWeekIsNotCarried() {
        // Clock moved backwards, or a payload from a future week is somehow
        // present. Either way the totals do not describe today.
        let calendar = calendar()
        let stored = snapshot(
            on: date(2026, 7, 29),
            weekStart: planWeek.start,
            weekEnd: planWeek.end,
            calendar: calendar
        )

        #expect(stored.carriedForward(to: date(2026, 7, 26), calendar: calendar) == nil)
    }

    @Test func theCarriedSnapshotStillSurvivesAnEncodeDecodeRoundTrip() throws {
        let calendar = calendar()
        let stored = snapshot(on: date(2026, 7, 29), weekStart: planWeek.start, weekEnd: planWeek.end, calendar: calendar)

        let data = try JSONEncoder().encode(stored)
        let decoded = try JSONDecoder().decode(TodayWidgetSnapshot.self, from: data)

        #expect(decoded == stored)
        #expect(decoded.weekStartKey == stored.weekStartKey)
    }

    @Test func anOldPayloadWithoutTheWeekStampStillDecodes() throws {
        // Proves the new field did not break the app-group payload written by
        // whatever build is currently installed on his phone.
        let legacy = """
        {"generatedAt":775000000,"dateKey":"2026-07-29","phase":"done",
         "headline":"Everything done","detail":"Nice work","symbolName":"checkmark",
         "deepLink":"today://week",
         "week":{"completedMiles":21,"plannedMiles":35,"completedRuns":4,"completedLifts":3}}
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(TodayWidgetSnapshot.self, from: legacy)

        #expect(decoded.weekStartKey == nil)
        #expect(decoded.week.completedMiles == 21)
    }

    @Test func anUnsafeVersionOnePayloadIsDeletedInsteadOfRenderedAfterUpgrade() throws {
        let suiteName = "TodayWidgetMigrationTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let calendar = calendar()
        var unsafe = snapshot(
            on: date(2026, 7, 29),
            weekStart: planWeek.start,
            weekEnd: planWeek.end,
            calendar: calendar
        )
        unsafe = TodayWidgetSnapshot(
            generatedAt: unsafe.generatedAt,
            dateKey: unsafe.dateKey,
            phase: unsafe.phase,
            headline: "5 mi run + Lower lift",
            detail: "Done: 5 mi in 40m · 1 set",
            symbolName: unsafe.symbolName,
            deepLink: unsafe.deepLink,
            week: unsafe.week,
            weekStartKey: unsafe.weekStartKey,
            weekEndKey: unsafe.weekEndKey
        )
        defaults.set(try JSONEncoder().encode(unsafe), forKey: TodayWidgetSnapshot.legacyDefaultsKey)

        let loaded = TodayWidgetSnapshot.load(from: defaults, now: unsafe.generatedAt, calendar: calendar)

        #expect(loaded == nil)
        #expect(defaults.data(forKey: TodayWidgetSnapshot.legacyDefaultsKey) == nil)
    }

    @Test func aCurrentVersionPayloadStillLoadsNormally() throws {
        let suiteName = "TodayWidgetCurrentPayloadTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let calendar = calendar()
        let stored = snapshot(
            on: date(2026, 7, 29),
            weekStart: planWeek.start,
            weekEnd: planWeek.end,
            calendar: calendar
        )
        defaults.set(try JSONEncoder().encode(stored), forKey: TodayWidgetSnapshot.defaultsKey)

        let loaded = TodayWidgetSnapshot.load(from: defaults, now: stored.generatedAt, calendar: calendar)

        #expect(loaded == stored)
    }
}
