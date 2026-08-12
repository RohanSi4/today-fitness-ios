import Foundation

/// The handoff from the app to the coaching conversation.
///
/// **Why this is text he carries rather than something the app publishes.**
/// Coach sync writes to `rohansingh04.com`, and the published fitness schema is
/// deliberately narrow. Calendar-derived data has no business widening it, even
/// reduced to minutes: the whole design of `BusyInterval` is that the calendar
/// never leaves the phone, and quietly posting a digest of it would undo that
/// while technically leaking no titles. So this produces a block he chooses to
/// share, once, into the session where the plan actually gets changed.
///
/// It also keeps judgment in the right place. The app knows Thursday has no room
/// for eight miles; it does not know whether the right answer is to move the run
/// to Wednesday, shorten it, swap it with Friday's easy day, or leave it and
/// accept the miss. That is a coaching decision with the training block in view,
/// and the chat-first architecture exists precisely so the app does not make it.
///
/// Built only from `DayFit` and prescribed work, so there is no path by which an
/// event name could reach the output — the report has no access to one.
enum CoachConflictReport {
    /// Nil when the week has no conflicts, so the UI has nothing to offer and
    /// no reason to appear.
    static func text(
        for snapshot: WeeklyTrainingSnapshot,
        calendar: Calendar = .current
    ) -> String? {
        let conflicts = snapshot.scheduleConflicts
        guard !conflicts.isEmpty else { return nil }

        var lines = [
            "Calendar conflicts for \(range(snapshot, calendar: calendar)):",
            "",
        ]

        for day in conflicts {
            lines.append("- \(dayLabel(day, calendar: calendar)): "
                + "\(TrainingBrief.describe(day)) prescribed. \(shortfall(day, calendar: calendar))")
        }

        let clear = snapshot.days.filter {
            snapshot.containsInDeclaredWeek($0.date) && !$0.fit.isConflict
                && ($0.plannedRunMiles != nil || $0.plannedLift != nil)
        }
        lines.append("")
        if clear.isEmpty {
            lines.append("No other prescribed day in this week has room either.")
        } else {
            lines.append("The other \(clear.count) prescribed "
                + "\(clear.count == 1 ? "day fits" : "days fit").")
        }
        // Says what the numbers are and are not, so the coaching session does
        // not have to ask, and does not assume more precision than there is.
        lines.append(
            "Windows are free time between 6am and 10pm, with about 30 minutes "
            + "allowed either side of a run for changing and showering. "
            + "Event details are not included."
        )
        return lines.joined(separator: "\n")
    }

    static func shortfall(_ day: WeeklyDaySnapshot, calendar: Calendar = .current) -> String {
        guard case .conflict(let largest, let shortBy) = day.fit else { return "" }
        guard let largest else { return "Nothing free in the day." }
        return "Longest free window \(TrainingBrief.range(largest, calendar: calendar)), "
            + "short by \(TrainingBrief.minutes(shortBy))."
    }

    static func dayLabel(_ day: WeeklyDaySnapshot, calendar: Calendar = .current) -> String {
        var style = Date.FormatStyle.dateTime.weekday(.abbreviated).month(.abbreviated).day()
        style.calendar = calendar
        style.timeZone = calendar.timeZone
        return day.date.formatted(style)
    }

    static func range(_ snapshot: WeeklyTrainingSnapshot, calendar: Calendar = .current) -> String {
        var style = Date.FormatStyle.dateTime.month(.abbreviated).day()
        style.calendar = calendar
        style.timeZone = calendar.timeZone
        return "\(snapshot.startDate.formatted(style)) to \(snapshot.endDate.formatted(style))"
    }
}
