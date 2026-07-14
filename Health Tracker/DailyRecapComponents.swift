import SwiftUI

enum RecapPalette {
    static let accent = Color.indigo
    static let sleep = Color.blue
    static let positive = Color.green
    static let warm = Color.orange

    static func color(for kind: MovementKind) -> Color {
        switch kind {
        case .steps: .teal
        case .distance: .indigo
        case .activeEnergy: .orange
        }
    }
}

struct RecapSourceBanner: View {
    let source: RecapDataSource

    var body: some View {
        if case .sample(let reason) = source {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "sparkles")
                    .foregroundStyle(RecapPalette.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Sample data")
                        .font(.subheadline.weight(.semibold))
                    Text(reason)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .background(RecapPalette.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
            .accessibilityElement(children: .combine)
        }
    }
}

struct RecapHeroCard: View {
    let recap: DailyRecap

    private var scoreLabel: String {
        switch recap.sleep.score {
        case 85...: "Well recovered"
        case 70...: "Solid foundation"
        default: "Prioritize recovery"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("DAILY RECAP")
                        .font(.caption.weight(.bold))
                        .tracking(1.2)
                        .foregroundStyle(.white.opacity(0.72))
                    Text(DailyRecapFormatting.date(recap.date))
                        .font(.headline)
                        .foregroundStyle(.white)
                }
                Spacer()
                Image(systemName: "moon.stars.fill")
                    .font(.title2)
                    .foregroundStyle(.white.opacity(0.88))
                    .accessibilityHidden(true)
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 22) {
                    SleepScoreRing(score: recap.sleep.score)
                    heroSummary
                }
                VStack(alignment: .leading, spacing: 18) {
                    SleepScoreRing(score: recap.sleep.score)
                    heroSummary
                }
            }
        }
        .padding(22)
        .background(
            LinearGradient(
                colors: [Color.indigo, Color.blue.opacity(0.82)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 26, style: .continuous)
        )
        .shadow(color: Color.indigo.opacity(0.18), radius: 18, y: 9)
    }

    private var heroSummary: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(scoreLabel)
                .font(.title3.weight(.bold))
                .foregroundStyle(.white)
            Text("You slept \(DailyRecapFormatting.duration(recap.sleep.duration)) with \(DailyRecapFormatting.percent(recap.sleep.efficiency)) efficiency.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.84))
                .fixedSize(horizontal: false, vertical: true)
            Label(
                DailyRecapFormatting.durationComparison(
                    current: recap.sleep.duration,
                    average: recap.sleep.avgDuration
                ),
                systemImage: recap.sleep.durationDelta >= 0 ? "arrow.up.right" : "arrow.down.right"
            )
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct SleepScoreRing: View {
    let score: Int

    var body: some View {
        ZStack {
            Circle()
                .stroke(.white.opacity(0.18), lineWidth: 10)
            Circle()
                .trim(from: 0, to: min(1, max(0, Double(score) / 100)))
                .stroke(.white, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text("\(score)")
                    .font(.system(.title, design: .rounded, weight: .bold))
                Text("SCORE")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(0.8)
                    .opacity(0.72)
            }
            .foregroundStyle(.white)
        }
        .frame(width: 104, height: 104)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Sleep score")
        .accessibilityValue("\(score) out of 100")
    }
}

struct RecapInsightCard: View {
    let insight: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "lightbulb.max.fill")
                .font(.title3)
                .foregroundStyle(RecapPalette.warm)
                .frame(width: 38, height: 38)
                .background(RecapPalette.warm.opacity(0.12), in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text("Today’s takeaway")
                    .font(.headline)
                Text(insight)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .recapCard()
        .accessibilityElement(children: .combine)
    }
}

struct SleepDetailsCard: View {
    let sleep: SleepSummary

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var columns: [GridItem] {
        if dynamicTypeSize.isAccessibilitySize {
            return [GridItem(.flexible())]
        }
        return [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeading(title: "Sleep details", symbol: "bed.double.fill", tint: RecapPalette.sleep)
            LazyVGrid(columns: columns, spacing: 12) {
                SleepMetricTile(
                    title: "Time asleep",
                    value: DailyRecapFormatting.duration(sleep.duration),
                    baseline: DailyRecapFormatting.baselineDuration(sleep.avgDuration),
                    symbol: "moon.zzz.fill"
                )
                SleepMetricTile(
                    title: "Efficiency",
                    value: DailyRecapFormatting.percent(sleep.efficiency),
                    baseline: DailyRecapFormatting.baselinePercent(sleep.avgEfficiency),
                    symbol: "gauge.with.dots.needle.67percent"
                )
                SleepMetricTile(
                    title: "Bedtime",
                    value: DailyRecapFormatting.time(sleep.bedtime),
                    baseline: DailyRecapFormatting.timeComparison(
                        actual: sleep.bedtime,
                        averageMinutes: sleep.avgBedtimeMinutes
                    ),
                    symbol: "bed.double.fill"
                )
                SleepMetricTile(
                    title: "Wake time",
                    value: DailyRecapFormatting.time(sleep.wakeTime),
                    baseline: DailyRecapFormatting.timeComparison(
                        actual: sleep.wakeTime,
                        averageMinutes: sleep.avgWakeTimeMinutes
                    ),
                    symbol: "sunrise.fill"
                )
            }

            HStack {
                Label("Time in bed", systemImage: "clock")
                    .foregroundStyle(.secondary)
                Spacer()
                Text(DailyRecapFormatting.duration(sleep.inBed))
                    .fontWeight(.semibold)
            }
            .font(.subheadline)
            .accessibilityElement(children: .combine)
        }
        .padding(18)
        .recapCard()
    }
}

private struct SleepMetricTile: View {
    let title: String
    let value: String
    let baseline: String
    let symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Image(systemName: symbol)
                .foregroundStyle(RecapPalette.sleep)
                .accessibilityHidden(true)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.bold))
            Text(baseline)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
        .padding(14)
        .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine)
    }
}

struct MovementSection: View {
    let movement: [MovementMetric]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeading(title: "Movement", symbol: "figure.run", tint: .teal)
            ForEach(movement) { metric in
                MovementMetricCard(metric: metric)
            }
        }
    }
}

private struct MovementMetricCard: View {
    let metric: MovementMetric

    private var tint: Color { RecapPalette.color(for: metric.kind) }

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: metric.kind.symbolName)
                .font(.title3)
                .foregroundStyle(tint)
                .frame(width: 44, height: 44)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 13))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(metric.title)
                    .font(.subheadline.weight(.semibold))
                Text(DailyRecapFormatting.movementComparison(
                    current: metric.value,
                    average: metric.average,
                    unit: metric.unit
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 3) {
                Text(DailyRecapFormatting.movementValue(metric.value, unit: metric.unit))
                    .font(.headline.monospacedDigit())
                Text(DailyRecapFormatting.baselineMovement(metric.average, unit: metric.unit))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .recapCard()
        .accessibilityElement(children: .combine)
    }
}

private struct SectionHeading: View {
    let title: String
    let symbol: String
    let tint: Color

    var body: some View {
        Label(title, systemImage: symbol)
            .font(.title3.weight(.bold))
            .foregroundStyle(.primary)
            .symbolRenderingMode(.hierarchical)
            .tint(tint)
    }
}

private extension View {
    func recapCard() -> some View {
        background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.primary.opacity(0.055), lineWidth: 1)
            }
    }
}
