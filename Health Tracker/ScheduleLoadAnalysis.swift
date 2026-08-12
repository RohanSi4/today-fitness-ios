import Foundation

/// One past day, reduced to the two things this analysis joins.
struct ScheduleLoadDay: Equatable, Sendable {
    let date: Date
    /// Committed minutes inside the hours a session could have happened in.
    /// Time outside that band is not load, because it was never available.
    let busyMinutes: Double
    /// Whether any training happened, run or lift.
    let trained: Bool
}

/// Whether a heavier calendar goes with less training.
///
/// **This is an association over a small sample, and the wording it produces is
/// deliberately built so it cannot be read as anything else.** It reports counts
/// rather than rates, never a percentage, never a p-value, and never a claim
/// that the calendar *caused* a missed session. The obvious confound is
/// unmanaged and unmanageable here: a week that is busy at work is usually also
/// a week that is stressful, under-slept, and travelled.
///
/// It is a prompt to look, not a finding.
///
/// The sample gates matter more than the arithmetic. Apple Health is read 14
/// days back, so the join is thin by construction, and a 3-of-4 split on four
/// days is noise that reads like a result. Nothing is reported until there are
/// enough days on both sides for the comparison to be worth a sentence.
enum ScheduleLoadAnalysis {
    /// Days needed before any comparison is offered.
    static let minimumDays = 21
    /// Days needed on each side of the split.
    static let minimumPerGroup = 7
    /// The two halves must actually differ. Comparing a 3h median against a 3h
    /// median produces a sentence with no content.
    static let minimumSeparationMinutes: Double = 45

    struct Finding: Equatable, Sendable {
        let busierDays: Int
        let busierTrained: Int
        let lighterDays: Int
        let lighterTrained: Int
        /// Median committed minutes in each half, kept so the sentence can say
        /// what "busier" actually meant rather than leaving it abstract.
        let busierMedianMinutes: Double
        let lighterMedianMinutes: Double

        /// True when he trained less often on the busier half. The analysis is
        /// reported either way — "no difference" is a real answer and hiding it
        /// would make the feature look like it only ever confirms a hunch.
        var trainedLessWhenBusier: Bool {
            guard busierDays > 0, lighterDays > 0 else { return false }
            return Double(busierTrained) / Double(busierDays)
                < Double(lighterTrained) / Double(lighterDays)
        }
    }

    /// Split the window at its median load and compare. Nil whenever the sample
    /// cannot carry a claim.
    static func finding(from days: [ScheduleLoadDay]) -> Finding? {
        guard days.count >= minimumDays else { return nil }

        let sorted = days.sorted { $0.busyMinutes < $1.busyMinutes }
        let half = sorted.count / 2
        let lighter = Array(sorted[..<half])
        // The median day itself goes to the busier side on an odd count, which
        // only ever makes the busier group harder to distinguish, never easier.
        let busier = Array(sorted[half...])

        guard lighter.count >= minimumPerGroup, busier.count >= minimumPerGroup else { return nil }

        let lighterMedian = median(lighter.map(\.busyMinutes))
        let busierMedian = median(busier.map(\.busyMinutes))
        guard busierMedian - lighterMedian >= minimumSeparationMinutes else { return nil }

        return Finding(
            busierDays: busier.count,
            busierTrained: busier.filter(\.trained).count,
            lighterDays: lighter.count,
            lighterTrained: lighter.filter(\.trained).count,
            busierMedianMinutes: busierMedian,
            lighterMedianMinutes: lighterMedian
        )
    }

    /// The sentence.
    ///
    /// Counts on both sides, so the sample is visible in the claim itself. No
    /// percentage, because a percentage invites comparison against a number it
    /// was never powerful enough to support.
    static func sentence(_ finding: Finding) -> String {
        let busier = "On your \(finding.busierDays) busiest days "
            + "(\(hours(finding.busierMedianMinutes)) booked, typically) "
            + "you trained \(finding.busierTrained) times."
        let lighter = " On the \(finding.lighterDays) lightest "
            + "(\(hours(finding.lighterMedianMinutes))), \(finding.lighterTrained)."
        return busier + lighter
    }

    /// What the sentence is and is not, shown next to it rather than buried.
    static let caveat = "An association across \(minimumDays)+ days, not a cause. "
        + "Busy weeks are usually also short-sleep weeks."

    static func hours(_ minutes: Double) -> String {
        let rounded = Int(minutes.rounded())
        guard rounded >= 60 else { return "\(rounded)m" }
        let h = rounded / 60
        let m = rounded % 60
        return m == 0 ? "\(h)h" : "\(h)h \(m)m"
    }

    static func median(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[middle - 1] + sorted[middle]) / 2
        }
        return sorted[middle]
    }

    // MARK: Building the input

    /// Reduce calendar days and training history to the join.
    ///
    /// Only days strictly before today are used. Today is still in progress:
    /// counting it as "did not train" at 9am would drag every comparison toward
    /// the busy side, since a day with meetings already on it is exactly the
    /// kind of day that has not been trained yet.
    static func days(
        calendarDays: [CalendarDay],
        runs: [RunningWorkoutSummary],
        lifts: [WorkoutSession],
        now: Date = .now,
        calendar: Calendar = .current
    ) -> [ScheduleLoadDay] {
        let today = calendar.startOfDay(for: now)
        return calendarDays.compactMap { day -> ScheduleLoadDay? in
            let start = calendar.startOfDay(for: day.date)
            guard start < today else { return nil }

            let bounds = TrainingWindowPlanner.bounds(for: day.date, calendar: calendar)
            let committed = TrainingWindowPlanner.merge(day.busy).reduce(0.0) { total, interval in
                let overlapStart = max(interval.start, bounds.start)
                let overlapEnd = min(interval.end, bounds.end)
                return total + max(0, overlapEnd.timeIntervalSince(overlapStart))
            }

            let ran = runs.contains { calendar.isDate($0.startedAt, inSameDayAs: start) }
            let lifted = lifts.contains {
                calendar.isDate($0.endedAt ?? $0.startedAt, inSameDayAs: start)
            }

            return ScheduleLoadDay(
                date: start,
                busyMinutes: committed / 60,
                trained: ran || lifted
            )
        }
    }
}
