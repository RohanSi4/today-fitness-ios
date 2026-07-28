import Foundation
import Testing
@testable import Health_Tracker

struct WeightChartScaleTests {
    /// The two span assertions below originally compared against
    /// `WeightChartScale.minimumSpan` itself, which meant the assertion moved
    /// with the constant and could never fail when the constant changed. Tuning
    /// minimumSpan down to 0.5 silently removed the flat-week protection with
    /// every test still green. Pin the number here so a change to it is a
    /// deliberate edit to this test rather than an invisible regression.
    @Test func theMinimumSpanIsEightPounds() {
        #expect(WeightChartScale.minimumSpan == 8)
    }

    @Test func aMonthOfRealMorningsStaysZoomedIntoTheRange() throws {
        let mornings = [184.4, 184.1, 183.9, 183.2, 182.8, 182.4, 181.9, 181.6, 180.8, 180.2]

        let domain = try #require(WeightChartScale.domain(for: mornings, goal: 175))

        // The bug: Swift Charts anchored this at the origin and rounded out to 200.
        #expect(domain.lowerBound > 100)
        #expect(domain.upperBound < 200)
        #expect(domain.upperBound - domain.lowerBound < 25)
    }

    @Test func theGoalLineIsAlwaysInsideTheDomain() throws {
        let below = try #require(WeightChartScale.domain(for: [184.4, 183.2, 182.0], goal: 175))
        #expect(below.contains(175))
        #expect(below.lowerBound < 175)

        let above = try #require(WeightChartScale.domain(for: [168.0, 167.2, 166.5], goal: 175))
        #expect(above.contains(175))
        #expect(above.upperBound > 175)

        let inside = try #require(WeightChartScale.domain(for: [178.0, 172.0, 175.5], goal: 175))
        #expect(inside.contains(175))
    }

    @Test func aFlatWeekIsNotStretchedIntoMountains() throws {
        let flat = [178.2, 178.5, 178.3, 178.8, 178.4, 178.6, 178.5]

        let domain = try #require(WeightChartScale.domain(for: flat, goal: 178.5))

        #expect(domain.upperBound - domain.lowerBound >= 8)
        #expect(flat.allSatisfy { domain.contains($0) })
    }

    @Test func aFatFingeredEntryDoesNotBlowTheScaleBackOpen() throws {
        var mornings = [184.4, 184.1, 183.9, 183.2, 182.8, 182.4, 181.9, 181.6, 180.8, 180.2]
        mornings.insert(1_780, at: 4)

        let domain = try #require(WeightChartScale.domain(for: mornings, goal: 175))

        #expect(domain.upperBound < 200)
        // The typo is deliberately left outside the domain so its point clips
        // rather than costing a month of readable trend.
        #expect(!domain.contains(1_780))
        #expect(mornings.filter { $0 < 1_000 }.allSatisfy { domain.contains($0) })
    }

    @Test func aRealCutIsNeverMistakenForATypo() throws {
        // Roughly 200 down to 180 across a month is a big but genuine move, and
        // every point of it has to stay on the chart.
        let cut = stride(from: 200.0, through: 180.0, by: -1).map { $0 }

        let domain = try #require(WeightChartScale.domain(for: cut, goal: 175))

        #expect(cut.allSatisfy { domain.contains($0) })
        #expect(domain.contains(175))
    }

    @Test func aSingleEntryStillProducesAUsableWindow() throws {
        let domain = try #require(WeightChartScale.domain(for: [184.4], goal: 184.4))

        #expect(domain.contains(184.4))
        #expect(domain.upperBound - domain.lowerBound >= 8)
        #expect(domain.lowerBound > 150)
    }

    @Test func nothingPlottableProducesNoDomain() {
        #expect(WeightChartScale.domain(for: [], goal: 175) == nil)
        #expect(WeightChartScale.domain(for: [.nan, .infinity, -4, 0], goal: 175) == nil)
    }

    @Test func garbageReadingsAreIgnoredWithoutHidingTheRest() throws {
        let domain = try #require(
            WeightChartScale.domain(for: [184.4, .nan, 183.2, -1, 182.0], goal: 175)
        )

        #expect(domain.contains(184.4))
        #expect(domain.contains(182.0))
        #expect(domain.lowerBound >= 0)
    }

    @Test func boundsAreWholePoundsSoTheAxisLabelsReadCleanly() throws {
        let domain = try #require(WeightChartScale.domain(for: [184.4, 183.15, 181.7], goal: 175))

        #expect(domain.lowerBound == domain.lowerBound.rounded())
        #expect(domain.upperBound == domain.upperBound.rounded())
    }

    @Test func theNewestPointNeverSitsOnTheFrame() throws {
        let mornings = [184.4, 183.2, 182.0]

        let domain = try #require(WeightChartScale.domain(for: mornings, goal: 175))

        #expect(domain.upperBound > 184.4)
        #expect(domain.lowerBound < 175)
    }

    @Test func medianHandlesEvenAndOddCounts() {
        #expect(WeightChartScale.median(of: [1, 2, 3]) == 2)
        #expect(WeightChartScale.median(of: [1, 2, 3, 4]) == 2.5)
        #expect(WeightChartScale.median(of: []) == nil)
    }
}
