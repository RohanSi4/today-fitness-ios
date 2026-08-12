import Foundation

/// A stretch of a day with nothing scheduled in it.
struct FreeWindow: Equatable, Sendable {
    let start: Date
    let end: Date

    var duration: TimeInterval { max(0, end.timeIntervalSince(start)) }
}

/// One thing the coach asked for, and how long it actually costs.
///
/// The distinction that makes this useful: a "45 minute run" is not a 45 minute
/// commitment. Changing, getting out the door, and showering afterwards are the
/// difference between a session that fits a lunch gap and one that does not, and
/// they are exactly what someone underestimates when eyeballing a calendar.
struct SessionNeed: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case run
        case lift
    }

    let kind: Kind
    /// Moving time only.
    let working: TimeInterval
    /// Changing, transit, and showering on either side.
    let overhead: TimeInterval

    var total: TimeInterval { working + overhead }
}

/// Whether the day has room for what was prescribed.
enum DayFit: Equatable, Sendable {
    /// Nothing was prescribed, so there is nothing to fit.
    case rest
    /// No calendar access, or the schedule could not be read.
    case unknown
    /// Everything fits with room to spare.
    case fits(best: FreeWindow)
    /// It fits, but only just. Worth seeing before the day starts.
    case tight(best: FreeWindow)
    /// The prescribed work does not fit in any free window.
    case conflict(largest: FreeWindow?, shortBy: TimeInterval)

    var isConflict: Bool { if case .conflict = self { return true }; return false }
    var isTight: Bool { if case .tight = self { return true }; return false }

    /// The window to point at, when there is one.
    var window: FreeWindow? {
        switch self {
        case .fits(let window), .tight(let window):
            return window
        case .conflict(let largest, _):
            return largest
        case .rest, .unknown:
            return nil
        }
    }
}

enum TrainingWindowPlanner {
    // MARK: Tuning

    /// The hours a session could plausibly start and end within.
    ///
    /// Not "awake" hours and not the whole day. A 5am window is technically free
    /// and offering it as the answer to a booked Thursday is how a feature stops
    /// being believed. Widened only when the day genuinely has nothing else.
    static let defaultDayStartHour = 6
    static let defaultDayEndHour = 22

    /// Fallback pace when there is no recent run to learn from, in seconds per
    /// mile. Deliberately a slow easy pace: overestimating the time a run needs
    /// produces a warning that turns out to be unnecessary, while underestimating
    /// produces a session that runs into a meeting.
    static let fallbackPaceSecondsPerMile: Double = 600

    /// Guard rails on learned pace. A treadmill walk-back or a GPS dropout can
    /// produce a "pace" of 25 minutes or 3 minutes per mile, and either one
    /// poisons every estimate for the week if taken at face value.
    static let minimumLearnedPace: Double = 300
    static let maximumLearnedPace: Double = 900

    /// Getting changed, out the door, and showered afterwards.
    static let runOverhead: TimeInterval = 30 * 60
    static let liftOverhead: TimeInterval = 25 * 60

    /// A lift is prescribed as a kind, never a duration, so it gets a flat
    /// estimate from how long these sessions actually take.
    static let liftWorkingTime: TimeInterval = 55 * 60

    /// Slack above the estimate before a day stops counting as comfortable.
    static let comfortableSlack: TimeInterval = 25 * 60

    // MARK: Intervals

    /// Collapse overlapping and touching busy blocks into a clean list.
    ///
    /// Back-to-back meetings arrive as separate events and must not leave a
    /// zero-length "free window" between them for a session to be offered in.
    static func merge(_ intervals: [BusyInterval]) -> [BusyInterval] {
        let sorted = intervals.filter { $0.duration > 0 }.sorted { $0.start < $1.start }
        var merged: [BusyInterval] = []
        for interval in sorted {
            if let last = merged.last, interval.start <= last.end {
                if interval.end > last.end {
                    merged[merged.count - 1] = BusyInterval(start: last.start, end: interval.end)
                }
            } else {
                merged.append(interval)
            }
        }
        return merged
    }

    /// The gaps left in `bounds` once every busy block is removed.
    static func freeWindows(busy: [BusyInterval], within bounds: FreeWindow) -> [FreeWindow] {
        guard bounds.duration > 0 else { return [] }
        var windows: [FreeWindow] = []
        var cursor = bounds.start

        for interval in merge(busy) {
            guard interval.end > bounds.start, interval.start < bounds.end else { continue }
            let blockStart = max(interval.start, bounds.start)
            if blockStart > cursor {
                windows.append(FreeWindow(start: cursor, end: blockStart))
            }
            cursor = max(cursor, min(interval.end, bounds.end))
        }
        if cursor < bounds.end {
            windows.append(FreeWindow(start: cursor, end: bounds.end))
        }
        return windows.filter { $0.duration > 0 }
    }

    static func bounds(for date: Date, calendar: Calendar = .current) -> FreeWindow {
        let start = calendar.date(bySettingHour: defaultDayStartHour, minute: 0, second: 0, of: date)
            ?? calendar.startOfDay(for: date)
        let end = calendar.date(bySettingHour: defaultDayEndHour, minute: 0, second: 0, of: date)
            ?? date
        return FreeWindow(start: start, end: end)
    }

    // MARK: Demand

    /// Learn a usable pace from recent runs, or admit there isn't one.
    ///
    /// Median rather than mean: one 5K time trial or one walk-heavy recovery run
    /// should not move the estimate for the rest of the week.
    static func learnedPace(from runs: [RunningWorkoutSummary]) -> Double {
        let paces = runs
            .compactMap(\.paceSecondsPerMile)
            .filter { $0 >= minimumLearnedPace && $0 <= maximumLearnedPace }
            .sorted()
        guard !paces.isEmpty else { return fallbackPaceSecondsPerMile }
        return paces[paces.count / 2]
    }

    static func needs(
        plannedRunMiles: Double?,
        plannedLift: WorkoutKind?,
        paceSecondsPerMile: Double
    ) -> [SessionNeed] {
        var needs: [SessionNeed] = []
        if let miles = plannedRunMiles, miles > 0 {
            needs.append(
                SessionNeed(kind: .run, working: miles * paceSecondsPerMile, overhead: runOverhead)
            )
        }
        if plannedLift != nil {
            needs.append(SessionNeed(kind: .lift, working: liftWorkingTime, overhead: liftOverhead))
        }
        return needs
    }

    // MARK: Fit

    /// Place every prescribed session into the day's free windows.
    ///
    /// Sessions are placed largest first into the roomiest window that still
    /// holds them, and a window that takes one session has its remaining
    /// capacity reduced rather than being reused whole. A run and a lift on the
    /// same day are two commitments, and a single three-hour gap can host both
    /// while two separate one-hour gaps cannot host the long run alone.
    static func fit(needs: [SessionNeed], windows: [FreeWindow]) -> DayFit {
        guard !needs.isEmpty else { return .rest }

        let largest = windows.max { $0.duration < $1.duration }
        var remaining = windows.map(\.duration).sorted(by: >)
        var worstSlack = TimeInterval.greatestFiniteMagnitude

        for need in needs.sorted(by: { $0.total > $1.total }) {
            guard let index = remaining.firstIndex(where: { $0 >= need.total }) else {
                let biggest = remaining.max() ?? 0
                return .conflict(largest: largest, shortBy: need.total - biggest)
            }
            worstSlack = min(worstSlack, remaining[index] - need.total)
            remaining[index] -= need.total
            remaining.sort(by: >)
        }

        guard let best = largest else { return .conflict(largest: nil, shortBy: 0) }
        return worstSlack >= comfortableSlack ? .fits(best: best) : .tight(best: best)
    }

    /// The whole calculation for one day.
    static func fit(
        plannedRunMiles: Double?,
        plannedLift: WorkoutKind?,
        calendarDay: CalendarDay?,
        date: Date,
        paceSecondsPerMile: Double,
        calendar: Calendar = .current
    ) -> DayFit {
        let needs = needs(
            plannedRunMiles: plannedRunMiles,
            plannedLift: plannedLift,
            paceSecondsPerMile: paceSecondsPerMile
        )
        guard !needs.isEmpty else { return .rest }
        guard let calendarDay else { return .unknown }

        let windows = freeWindows(busy: calendarDay.busy, within: bounds(for: date, calendar: calendar))
        return fit(needs: needs, windows: windows)
    }
}
