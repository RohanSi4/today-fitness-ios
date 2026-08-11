import Foundation

enum TodayWidgetPhase: String, Codable, Hashable {
    case weight
    case plan
    case remaining
    case done
    case recovery
    case unavailable
}

struct TodayWidgetWeek: Codable, Equatable {
    let completedMiles: Double
    let plannedMiles: Double
    let completedRuns: Int
    let completedLifts: Int
}

/// The part of an in-progress lift the Lock Screen is allowed to show.
///
/// `lastSetAt` is a timestamp rather than a pre-rendered "1:42" on purpose. A
/// widget only re-draws on a timeline reload, and nothing can push one every
/// second, so a baked duration is wrong within a second of arriving. The widget
/// hands this date to `Text(_:style:.timer)`, which the system ticks with no
/// reload at all - that is the only way a rest clock out here can stay honest.
struct TodayWidgetWorkout: Codable, Equatable {
    let title: String
    let startedAt: Date
    /// When the last working set was checked off, or nil before the first one.
    let lastSetAt: Date?
    /// The first movement still holding an unfinished set. Nil once they are all
    /// down, which is the signal to say "last set in" rather than name nothing.
    let nextExercise: String?
    let completedSets: Int
    let plannedSets: Int

    /// The clock the rest timer counts up from: the last set if there is one,
    /// otherwise the start of the session, so a workout with nothing logged yet
    /// still shows a moving number instead of a dash.
    var restAnchor: Date { lastSetAt ?? startedAt }

    var setRatio: Double {
        guard plannedSets > 0 else { return 0 }
        return min(max(Double(completedSets) / Double(plannedSets), 0), 1)
    }

    /// How long this can sit on the Lock Screen without another push from the
    /// app before it stops being believable.
    ///
    /// Needed because the app is the only thing that ever clears this field, and
    /// it cannot do that if it was killed mid-session or he simply forgot to hit
    /// finish. Six hours is far past his longest logged session (92 minutes) and
    /// far short of a rest clock reading nine hours, which is the failure this
    /// guards against.
    static let staleAfter: TimeInterval = 6 * 60 * 60

    func isStale(at now: Date) -> Bool {
        now.timeIntervalSince(restAnchor) > Self.staleAfter
    }
}

struct TodayWidgetSnapshot: Codable, Equatable {
    static let appGroupIdentifier = "group.rohansingh.today"
    static let defaultsKey = "today-widget-snapshot-v2"
    static let legacyDefaultsKey = "today-widget-snapshot-v1"
    static let widgetKind = "TodayDailyWidget"

    let generatedAt: Date
    let dateKey: String
    let phase: TodayWidgetPhase
    let headline: String
    let detail: String
    let symbolName: String
    let deepLink: URL
    let week: TodayWidgetWeek

    /// The span the `week` totals describe, as inclusive `yyyy-MM-dd` bounds.
    ///
    /// Carried on the payload rather than recomputed, because the widget cannot
    /// recompute it correctly: the training week comes from the coach's plan and
    /// runs Monday to Sunday, while `Calendar.current` weeks start on Sunday in
    /// this locale. Deriving the week inside the extension made Sunday and the
    /// following Monday - different plan weeks - look like the same week.
    ///
    /// Optional so a payload written by an older build still decodes; those lose
    /// the week on a stale day exactly as before and self-heal on the next publish.
    var weekStartKey: String?
    var weekEndKey: String?

    /// Set only while a lift is open. Optional for the same reason as the week
    /// keys: a payload written by an older build has to keep decoding.
    var workout: TodayWidgetWorkout?

    static var placeholder: TodayWidgetSnapshot {
        TodayWidgetSnapshot(
            generatedAt: .now,
            dateKey: dayKey(for: .now),
            phase: .weight,
            headline: "Log morning weight",
            detail: "Then see what is on for today",
            symbolName: "scalemass.fill",
            deepLink: URL(string: "today://weight")!,
            week: TodayWidgetWeek(
                completedMiles: 12,
                plannedMiles: 35,
                completedRuns: 3,
                completedLifts: 1
            )
        )
    }

    /// Mid-lift, for the preview canvas. The rest clock only looks right when
    /// the anchor is in the past, so it is offset rather than `.now`.
    static var workoutPlaceholder: TodayWidgetSnapshot {
        var snapshot = placeholder
        snapshot.workout = TodayWidgetWorkout(
            title: "Upper A workout",
            startedAt: .now.addingTimeInterval(-2_700),
            lastSetAt: .now.addingTimeInterval(-102),
            nextExercise: "Pec deck",
            completedSets: 8,
            plannedSets: 17
        )
        return snapshot
    }

    static var fallback: TodayWidgetSnapshot {
        TodayWidgetSnapshot(
            generatedAt: .now,
            dateKey: dayKey(for: .now),
            phase: .weight,
            headline: "Log morning weight",
            detail: "Open Today to refresh",
            symbolName: "scalemass.fill",
            deepLink: URL(string: "today://weight")!,
            week: TodayWidgetWeek(
                completedMiles: 0,
                plannedMiles: 0,
                completedRuns: 0,
                completedLifts: 0
            )
        )
    }

    static func load(now: Date = .now, calendar: Calendar = .current) -> TodayWidgetSnapshot? {
        guard let defaults = UserDefaults(suiteName: appGroupIdentifier) else {
            return nil
        }
        return load(from: defaults, now: now, calendar: calendar)
    }

    static func load(
        from defaults: UserDefaults,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> TodayWidgetSnapshot? {
        // Version 1 allowed exact daily plan/completion copy. Never render it
        // after an upgrade, even if the host app has not launched to publish v2.
        defaults.removeObject(forKey: legacyDefaultsKey)

        guard let data = defaults.data(forKey: defaultsKey),
              let snapshot = try? JSONDecoder().decode(TodayWidgetSnapshot.self, from: data) else {
            return nil
        }
        return snapshot.carriedForward(to: now, calendar: calendar)
    }

    /// What a stored snapshot still means at `now`.
    ///
    /// The day guard used to throw the whole payload away once the date rolled
    /// over, which was right for the daily prompt and wrong for everything else:
    /// the week totals went with it, so on any new morning before the app was
    /// opened the Lock Screen read "Week: 0/0 mi, 0 lifts" for a week with real
    /// miles in it. Stale data is forgivable; a confident zero is not, because
    /// nothing distinguishes it from a genuine rest week.
    ///
    /// The two ages are now tracked separately. A new day only retires the daily
    /// prompt. Only a new training week retires the totals.
    func carriedForward(to now: Date, calendar: Calendar = .current) -> TodayWidgetSnapshot? {
        // An open lift outlives its own payload. Only the app clears this field,
        // and it cannot do that from a Lock Screen he never unlocked, so the
        // widget has to retire a stale one itself rather than tick a rest clock
        // into the hours.
        let live = workout.flatMap { $0.isStale(at: now) ? nil : $0 }

        let today = Self.dayKey(for: now, calendar: calendar)
        if dateKey == today {
            return live == workout ? self : withWorkout(live)
        }

        // A lift that crossed midnight is still the same lift. Everything below
        // rewrites the daily prompt for the new day; the session rides through
        // untouched, because "in progress" did not stop being true at 00:00.

        // `yyyy-MM-dd` is zero-padded and fixed-width, so lexicographic order is
        // chronological order and no date arithmetic is needed here.
        guard let weekStartKey, let weekEndKey,
              today >= weekStartKey, today <= weekEndKey else {
            return nil
        }

        // Same week, new day: keep the totals, reset the prompt to the first
        // thing he does every morning.
        return TodayWidgetSnapshot(
            generatedAt: generatedAt,
            dateKey: today,
            phase: .weight,
            headline: "Log morning weight",
            detail: "Then see what is on for today",
            symbolName: "scalemass.fill",
            deepLink: URL(string: "today://weight")!,
            week: week,
            weekStartKey: weekStartKey,
            weekEndKey: weekEndKey,
            workout: live
        )
    }

    private func withWorkout(_ workout: TodayWidgetWorkout?) -> TodayWidgetSnapshot {
        var copy = self
        copy.workout = workout
        return copy
    }

    static func dayKey(for date: Date, calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }
}
