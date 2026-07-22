import Foundation

enum TodayWidgetPhase: String, Codable {
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
    static let defaultsKey = "today-widget-snapshot-v1"
    static let widgetKind = "TodayDailyWidget"

    let generatedAt: Date
    let dateKey: String
    let phase: TodayWidgetPhase
    let headline: String
    let detail: String
    let symbolName: String
    let deepLink: URL
    let week: TodayWidgetWeek

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

    static func load() -> TodayWidgetSnapshot? {
        guard let defaults = UserDefaults(suiteName: appGroupIdentifier),
              let data = defaults.data(forKey: defaultsKey),
              let snapshot = try? JSONDecoder().decode(TodayWidgetSnapshot.self, from: data),
              snapshot.dateKey == dayKey(for: .now) else {
            return nil
        }
        return snapshot
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
