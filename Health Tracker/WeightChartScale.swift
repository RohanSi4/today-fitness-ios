import Foundation

/// The y-axis domain for the body weight trend chart.
///
/// Swift Charts' automatic numeric domain is anchored at the origin: it unions the
/// data range with zero and then rounds outward to a round number. A month of
/// 178-186 lb mornings therefore renders as 0...200, so every real day-to-day
/// change is squeezed into the top tenth of a 135 pt card and reads as a flat
/// line. Nothing was wrong with the data; the chart simply never asked for a
/// domain. This type computes one.
///
/// Kept out of the view body on purpose so the rules below can be asserted
/// directly instead of eyeballed in a screenshot.
enum WeightChartScale {
    /// The narrowest window the chart will ever show. A week that only moves from
    /// 178.2 to 178.8 is a flat week, and it should read as one rather than being
    /// stretched into a mountain range by a domain that hugs the data.
    static let minimumSpan: Double = 8

    /// Headroom above and below, as a fraction of the span, so the newest point
    /// and the dashed goal line never sit exactly on the frame.
    static let paddingFraction: Double = 0.12

    /// How far a reading may sit from the median before it is treated as a typo
    /// and excluded from the domain, as a multiple of the median absolute
    /// deviation.
    static let outlierTolerance: Double = 6

    /// Floor under the median absolute deviation. Without it a genuinely flat
    /// week has a near-zero deviation and would start rejecting its own perfectly
    /// good half-pound spread. Combined with `outlierTolerance` this means a
    /// reading is never excluded unless it is more than 24 lb from the median.
    static let minimumDeviation: Double = minimumSpan / 2

    /// The domain to hand to `.chartYScale(domain:)`.
    ///
    /// - Parameters:
    ///   - pounds: Every weight that will be plotted.
    ///   - goal: The goal weight, which is drawn as a `RuleMark` in the same
    ///     coordinate space. A domain that excludes it drops the dashed line off
    ///     the edge with no warning, so it is always folded in.
    /// - Returns: `nil` when there is nothing plottable, in which case the caller
    ///   should not draw a chart at all.
    static func domain(for pounds: [Double], goal: Double? = nil) -> ClosedRange<Double>? {
        let values = pounds.filter { $0.isFinite && $0 > 0 }
        guard !values.isEmpty else { return nil }

        let plotted = typicalValues(in: values)
        var lower = plotted.min() ?? 0
        var upper = plotted.max() ?? 0

        if let goal, goal.isFinite, goal > 0 {
            lower = min(lower, goal)
            upper = max(upper, goal)
        }

        let padding = max((upper - lower) * paddingFraction, 0.5)
        lower -= padding
        upper += padding

        if upper - lower < minimumSpan {
            let growth = (minimumSpan - (upper - lower)) / 2
            lower -= growth
            upper += growth
        }

        // Nobody weighs a negative number, and a domain that dips below zero
        // wastes half the card.
        if lower < 0 {
            lower = 0
            upper = max(upper, minimumSpan)
        }

        // Whole pounds so the axis labels come out as round numbers.
        return lower.rounded(.down)...upper.rounded(.up)
    }

    /// The readings a domain should be built from, with likely typos dropped.
    ///
    /// A fat-fingered 1780 for 178.0 would otherwise re-open the scale to exactly
    /// the useless range this whole type exists to avoid, and one bad tap should
    /// not cost a month of readable trend. The excluded reading is *not* deleted
    /// or hidden from any total: it is only left out of the domain calculation,
    /// so its point clips off the top of the plot where it is obvious something
    /// is wrong, and re-logging that day fixes it.
    ///
    /// Median absolute deviation is used rather than an interquartile fence
    /// because it still behaves on the three or four readings a fresh week has,
    /// where quartiles are mostly interpolation noise.
    static func typicalValues(in values: [Double]) -> [Double] {
        guard values.count >= 3, let center = median(of: values) else { return values }
        let deviations = values.map { abs($0 - center) }
        let spread = max(median(of: deviations) ?? 0, minimumDeviation)
        let kept = values.filter { abs($0 - center) <= outlierTolerance * spread }
        return kept.isEmpty ? values : kept
    }

    static func median(of values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[middle - 1] + sorted[middle]) / 2
        }
        return sorted[middle]
    }
}
