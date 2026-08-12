import Combine
import EventKit
import Foundation

/// A block of time the calendar says is spoken for.
///
/// **There is deliberately no title, location, notes, organiser, or identifier
/// on this type, and there must never be one.** Everything downstream of this
/// service — the week model, the morning brief, the App Group widget snapshot,
/// the coach sync payload — is built from `BusyInterval`, so making the type
/// incapable of carrying an event name is what keeps a name off the Lock Screen
/// and out of `rohansingh04.com`. A reviewer cannot forget to strip a field that
/// does not exist. `DataSafetyTests` asserts the shape rather than trusting it.
///
/// This matters more here than in most apps: a calendar during a job search is
/// full of interview titles, and the Lock Screen renders without unlocking.
struct BusyInterval: Equatable, Sendable {
    let start: Date
    let end: Date

    var duration: TimeInterval { max(0, end.timeIntervalSince(start)) }

    func overlaps(_ other: BusyInterval) -> Bool {
        start < other.end && other.start < end
    }
}

/// What a day's calendar looks like once titles are gone.
struct CalendarDay: Equatable, Sendable {
    let date: Date
    let busy: [BusyInterval]
    /// All-day entries are counted, never treated as busy time. See
    /// `EventKitCalendarProvider` for why.
    let allDayCount: Int
}

/// Everything the app reads from a calendar event, and nothing else.
///
/// This is the boundary type: `EKEvent` is converted to one of these the moment
/// it is seen, and every rule below operates on facts rather than on events.
/// Two things fall out of that. The title has no representation past this point,
/// and the exclusion rules become testable without constructing EventKit objects
/// — which matters, because an `EKEvent` with no calendar attached silently
/// ignores `isAllDay` and reports `availability` as `.notSupported`, so tests
/// built on one would assert against EventKit's object graph rather than ours.
struct CalendarEventFacts: Equatable, Sendable {
    let start: Date
    let end: Date
    let isAllDay: Bool
    /// False when the event is marked free, which is the user saying it does
    /// not hold their time.
    let holdsTime: Bool
    /// False when cancelled or declined. Neither is a commitment.
    let isCommitment: Bool
}

protocol CalendarEventProviding: Sendable {
    var isCalendarAvailable: Bool { get }
    func authorizationState() -> CalendarAuthorization
    func requestAccess() async throws -> Bool
    func fetchBusy(start: Date, end: Date, calendar: Calendar) async throws -> [CalendarDay]
}

enum CalendarAuthorization: Equatable, Sendable {
    case notDetermined
    case denied
    case authorized
}

// MARK: - EventKit

/// Reads the local EventKit store.
///
/// **This is why the app has no Google OAuth.** A Google account added in iOS
/// Settings surfaces through EventKit like any other calendar, so reading the
/// system store gets Google, iCloud, and school calendars at once with a single
/// system permission prompt, no client secret, no refresh token, no network
/// call, and no behaviour to maintain when an API version turns over. It also
/// keeps us away from the Keychain, where a missing `application-identifier`
/// entitlement returns `errSecMissingEntitlement (-34018)` on any machine
/// building with `CODE_SIGNING_ALLOWED=NO` — see AGENTS.md.
///
/// The tradeoff is freshness: iOS does not sync Google in real time, so an event
/// added on the web can lag by minutes. For a morning brief and a week look
/// ahead that is an acceptable trade, and it is the reason nothing here presents
/// itself as a live view of the calendar.
struct EventKitCalendarProvider: CalendarEventProviding {
    static let shared = EventKitCalendarProvider()

    /// Never held across the actor boundary; EKEventStore is not Sendable.
    private func makeStore() -> EKEventStore { EKEventStore() }

    var isCalendarAvailable: Bool { true }

    func authorizationState() -> CalendarAuthorization {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess:
            return .authorized
        case .notDetermined:
            return .notDetermined
        default:
            // .denied, .restricted, and .writeOnly all mean the same thing to us:
            // we cannot read the day. .writeOnly in particular looks like a
            // grant and is not one, so it must not fall through to authorized.
            return .denied
        }
    }

    func requestAccess() async throws -> Bool {
        try await makeStore().requestFullAccessToEvents()
    }

    func fetchBusy(start: Date, end: Date, calendar: Calendar) async throws -> [CalendarDay] {
        let store = makeStore()
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        let events = store.events(matching: predicate)
        return Self.days(from: events, start: start, end: end, calendar: calendar)
    }

    /// Read the only fields we care about off an event, dropping everything
    /// else — title, location, notes, organiser, identifier — right here.
    static func facts(from event: EKEvent) -> CalendarEventFacts? {
        guard let start = event.startDate, let end = event.endDate else { return nil }
        return CalendarEventFacts(
            start: start,
            end: end,
            isAllDay: event.isAllDay,
            holdsTime: event.availability != .free,
            isCommitment: event.status != .canceled && !isDeclined(event)
        )
    }

    static func days(
        from events: [EKEvent],
        start: Date,
        end: Date,
        calendar: Calendar
    ) -> [CalendarDay] {
        days(from: events.compactMap(facts(from:)), start: start, end: end, calendar: calendar)
    }

    /// Turn facts into busy time.
    ///
    /// Three classes of event are excluded on purpose:
    ///
    /// - **All-day events do not block time.** The birthdays calendar alone
    ///   would otherwise mark most of the year unavailable, and a day-long
    ///   "Conference" still has a morning in it. They are counted so the brief
    ///   can say the day has something on it without pretending to know how long.
    /// - **Events marked free** are already the user saying "this does not hold
    ///   my time." Honouring busy and tentative while ignoring free is the whole
    ///   point of that field existing.
    /// - **Declined and cancelled events** are not commitments. Counting a
    ///   meeting you turned down as a training conflict is the fastest way to
    ///   make the feature untrustworthy.
    static func days(
        from facts: [CalendarEventFacts],
        start: Date,
        end: Date,
        calendar: Calendar
    ) -> [CalendarDay] {
        var busyByDay: [Date: [BusyInterval]] = [:]
        var allDayByDay: [Date: Int] = [:]

        for fact in facts where fact.isCommitment {
            let day = calendar.startOfDay(for: fact.start)
            if fact.isAllDay {
                allDayByDay[day, default: 0] += 1
                continue
            }
            guard fact.holdsTime, fact.end > fact.start else { continue }
            busyByDay[day, default: []].append(BusyInterval(start: fact.start, end: fact.end))
        }

        let dayCount = calendar.dateComponents([.day], from: calendar.startOfDay(for: start),
                                               to: calendar.startOfDay(for: end)).day ?? 0
        let days = (0...max(0, dayCount)).compactMap {
            calendar.date(byAdding: .day, value: $0, to: calendar.startOfDay(for: start))
        }
        return days.map { day in
            CalendarDay(
                date: day,
                busy: (busyByDay[day] ?? []).sorted { $0.start < $1.start },
                allDayCount: allDayByDay[day] ?? 0
            )
        }
    }

    private static func isDeclined(_ event: EKEvent) -> Bool {
        event.attendees?.contains { $0.isCurrentUser && $0.participantStatus == .declined } ?? false
    }
}

// MARK: - Service

@MainActor
final class CalendarService: ObservableObject {
    static let shared = CalendarService()

    @Published private(set) var days: [CalendarDay] = []
    @Published private(set) var authorization: CalendarAuthorization = .notDetermined
    @Published private(set) var lastUpdated: Date?

    /// True when the last read failed outright.
    ///
    /// Kept separate from `authorization` because the two produce different
    /// sentences: a refused calendar should offer to ask again, while a failed
    /// read should say the schedule is stale. Collapsing them is how the run
    /// week ended up showing a confident "0 of 26.1 miles" for an unread store.
    @Published private(set) var lastReadFailed = false

    private let provider: any CalendarEventProviding

    /// Deliberately does **not** touch EventKit.
    ///
    /// Reading authorization here meant that merely constructing `TodayView`
    /// reached the calendar daemon. On a CI simulator that has never had a
    /// calendar, that call does not return quickly and it does not fail — the
    /// test run hung for 24 minutes after compiling and was killed by the job
    /// timeout, with no test having reported. Authorization is now read inside
    /// `refresh`, which every caller already treats as async and skippable.
    init(provider: any CalendarEventProviding = EventKitCalendarProvider.shared) {
        self.provider = provider
    }

    var hasTrustworthySchedule: Bool {
        authorization == .authorized && !(lastReadFailed && lastUpdated == nil)
    }

    /// Refresh without ever prompting. Safe to call on every foreground.
    func refresh(now: Date = .now, calendar: Calendar = .current) async {
        guard Self.isCalendarUsable else { return }
        authorization = provider.authorizationState()
        guard authorization == .authorized else { return }
        await load(now: now, calendar: calendar)
    }

    /// Prompt once, then load. Only call from an explicit user action.
    func requestAccessAndLoad(now: Date = .now, calendar: Calendar = .current) async {
        guard Self.isCalendarUsable else { return }
        do {
            let granted = try await provider.requestAccess()
            authorization = granted ? .authorized : .denied
            guard granted else { return }
            await load(now: now, calendar: calendar)
        } catch {
            authorization = provider.authorizationState()
            lastReadFailed = true
        }
    }

    private func load(now: Date, calendar: Calendar) async {
        let start = calendar.startOfDay(for: now)
        let end = calendar.date(byAdding: .day, value: Self.lookaheadDays, to: start) ?? start
        do {
            days = try await provider.fetchBusy(start: start, end: end, calendar: calendar)
            lastUpdated = .now
            lastReadFailed = false
        } catch {
            // Keep the last good schedule. A stale window is more useful than an
            // empty one that reads as "your whole week is free."
            lastReadFailed = true
        }
    }

    func day(for date: Date, calendar: Calendar = .current) -> CalendarDay? {
        days.first { calendar.isDate($0.date, inSameDayAs: date) }
    }

    /// One training week plus today, which is all the week strip can show.
    static let lookaheadDays = 8

    /// False whenever the calendar must not be touched at all.
    ///
    /// Covers the mock-data launch the UI tests use and any XCTest host. Both
    /// run on simulators with no calendar store, where EventKit blocks rather
    /// than returning empty, and neither has anything to learn from a real one.
    static var isCalendarUsable: Bool {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-useMockData") { return false }
        let environment = ProcessInfo.processInfo.environment
        if environment["XCTestConfigurationFilePath"] != nil { return false }
        if environment["XCTestBundlePath"] != nil { return false }
        return true
    }
}
