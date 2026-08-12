import Foundation

/// The one line about time that belongs next to the morning plan.
///
/// Written as pure formatting over `DayFit` so what it says can be tested
/// without a calendar, a simulator, or a granted permission.
///
/// Two rules shape every sentence here:
///
/// - **Never name an event.** The brief can say the afternoon is gone; it can
///   never say what took it. `BusyInterval` makes that structurally true, and
///   this type is the last place it would be tempting to reach for a title.
/// - **Never imply certainty the calendar cannot support.** Missing access and
///   an empty day produce different sentences. Collapsing them into "you're
///   free" is the same failure as an unread Health store rendering as a week of
///   zero miles.
enum TrainingBrief {
    /// The line under today's plan.
    static func today(_ fit: DayFit, now: Date = .now, calendar: Calendar = .current) -> String? {
        switch fit {
        case .rest:
            return nil
        case .unknown:
            return nil
        case .fits(let window):
            return "Best window \(range(window, calendar: calendar))"
        case .tight(let window):
            return "Tight today, best window \(range(window, calendar: calendar))"
        case .conflict(let largest, let shortBy):
            guard let largest else { return "No room on the calendar today" }
            return "Short \(minutes(shortBy)) today, longest gap \(range(largest, calendar: calendar))"
        }
    }

    /// The week-level warning, or nil when there is nothing worth saying.
    ///
    /// Deliberately silent when the week is clear. A banner that appears every
    /// day stops being read on the day it matters.
    static func week(_ snapshot: WeeklyTrainingSnapshot, calendar: Calendar = .current) -> String? {
        let conflicts = snapshot.scheduleConflicts
        guard !conflicts.isEmpty else { return nil }
        if conflicts.count == 1, let day = conflicts.first {
            return "\(day.dayLabel) has no room for \(describe(day))"
        }
        let labels = conflicts.map(\.dayLabel).joined(separator: ", ")
        return "\(conflicts.count) days have no room: \(labels)"
    }

    /// What the day was asked to do, in the fewest words that stay accurate.
    static func describe(_ day: WeeklyDaySnapshot) -> String {
        var parts: [String] = []
        if let miles = day.plannedRunMiles, miles > 0 {
            parts.append(miles == miles.rounded() ? "\(Int(miles)) mi" : String(format: "%.1f mi", miles))
        }
        if day.plannedLift != nil {
            parts.append("a lift")
        }
        return parts.isEmpty ? "training" : parts.joined(separator: " and ")
    }

    static func range(_ window: FreeWindow, calendar: Calendar = .current) -> String {
        "\(clock(window.start, calendar: calendar))-\(clock(window.end, calendar: calendar))"
    }

    /// Times are rendered in the user's own 12/24-hour setting rather than a
    /// hardcoded format, since this sits beside system-formatted plan text.
    static func clock(_ date: Date, calendar: Calendar = .current) -> String {
        var formatter = Date.FormatStyle.dateTime.hour().minute()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        return date.formatted(formatter)
    }

    /// Round up. Telling someone they are 44 minutes short when they are 44.6
    /// invites them to try to make it work.
    static func minutes(_ interval: TimeInterval) -> String {
        let total = Int((interval / 60).rounded(.up))
        guard total >= 60 else { return "\(max(total, 1))m" }
        let hours = total / 60
        let remainder = total % 60
        return remainder == 0 ? "\(hours)h" : "\(hours)h \(remainder)m"
    }
}
