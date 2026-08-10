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
        let today = Self.dayKey(for: now, calendar: calendar)
        if dateKey == today { return self }

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
            weekEndKey: weekEndKey
        )
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
