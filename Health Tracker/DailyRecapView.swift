import SwiftUI

struct DailyRecapView: View {
    let targetDate: Date?

    @StateObject private var viewModel: DailyRecapViewModel

    init(targetDate: Date? = nil) {
        self.targetDate = targetDate
        _viewModel = StateObject(wrappedValue: DailyRecapViewModel(targetDate: targetDate))
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Daily Recap")
        }
        .task {
            await viewModel.load()
        }
        .onChange(of: targetDate) { newValue in
            Task {
                await viewModel.updateTargetDate(newValue)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle, .loading:
            VStack(spacing: 16) {
                ProgressView()
                Text("Loading your recap...")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .error(let message):
            VStack(spacing: 12) {
                Text("Unable to load")
                    .font(.headline)
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Text("Check Health permissions in Settings → Privacy & Security → Health.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Try Again") {
                    Task {
                        await viewModel.load()
                    }
                }
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .loaded(let recap):
            DailyRecapContentView(recap: recap)
        }
    }
}

struct DailyRecapContentView: View {
    let recap: DailyRecap

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text(formattedDate(recap.date))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                sleepSection(recap.sleep)
                movementSection(recap.movement)
                insightSection(recap.insight)
            }
            .padding()
        }
    }

    private func sleepSection(_ sleep: SleepSummary) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Sleep")
                .font(.title2)
                .bold()

            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Sleep Score")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("\(sleep.score)")
                        .font(.system(size: 40, weight: .bold))
                }
                Spacer()
            }

            MetricRow(
                title: "Time asleep",
                value: formattedDuration(sleep.duration),
                detail: formattedDurationDetail(current: sleep.duration, average: sleep.avgDuration)
            )

            MetricRow(
                title: "Time in bed",
                value: formattedDuration(sleep.inBed),
                detail: formattedDurationDetail(current: sleep.inBed, average: sleep.avgInBed)
            )

            MetricRow(
                title: "Efficiency",
                value: formattedPercent(sleep.efficiency),
                detail: formattedPercentDetail(current: sleep.efficiency, average: sleep.avgEfficiency)
            )

            MetricRow(
                title: "Bedtime",
                value: formattedTime(sleep.bedtime),
                detail: formattedTimeDetail(actual: sleep.bedtime, avgMinutes: sleep.avgBedtimeMinutes)
            )

            MetricRow(
                title: "Wake time",
                value: formattedTime(sleep.wakeTime),
                detail: formattedTimeDetail(actual: sleep.wakeTime, avgMinutes: sleep.avgWakeTimeMinutes)
            )
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func movementSection(_ movement: [MovementMetric]) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Movement")
                .font(.title2)
                .bold()

            ForEach(movement) { metric in
                MetricRow(
                    title: metric.title,
                    value: formattedMovementValue(metric.value, unit: metric.unit),
                    detail: formattedMovementDetail(current: metric.value, average: metric.average, unit: metric.unit)
                )
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func insightSection(_ insight: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Insight")
                .font(.title3)
                .bold()
            Text(insight)
                .font(.body)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    private func formattedTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: date)
    }

    private func formattedDuration(_ seconds: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: seconds) ?? "--"
    }

    private func formattedDurationDetail(current: TimeInterval, average: TimeInterval) -> String {
        guard average > 0 else { return "Avg --" }
        let delta = current - average
        return "Avg \(formattedDuration(average)) (\(formattedDurationDelta(delta)))"
    }

    private func formattedDurationDelta(_ delta: TimeInterval) -> String {
        let sign = delta >= 0 ? "+" : "-"
        let formatted = formattedDuration(abs(delta))
        return "\(sign)\(formatted) vs avg"
    }

    private func formattedPercent(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .percent
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? "--"
    }

    private func formattedPercentDetail(current: Double, average: Double) -> String {
        guard average > 0 else { return "Avg --" }
        let delta = current - average
        let sign = delta >= 0 ? "+" : "-"
        let deltaText = formattedPercent(abs(delta))
        return "Avg \(formattedPercent(average)) (\(sign)\(deltaText) vs avg)"
    }

    private func formattedTimeDetail(actual: Date, avgMinutes: Double?) -> String {
        guard let avgMinutes else { return "Avg --" }
        let avgDate = dateForMinutes(avgMinutes)
        let avgString = formattedTime(avgDate)
        let actualMinutes = minutesSinceMidnight(actual)
        let diff = actualMinutes - avgMinutes

        if abs(diff) < 1 {
            return "Avg \(avgString) (on time)"
        }

        let direction = diff > 0 ? "later" : "earlier"
        let diffMinutes = Int(abs(diff).rounded())
        return "Avg \(avgString) (\(diffMinutes)m \(direction))"
    }

    private func minutesSinceMidnight(_ date: Date) -> Double {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.hour, .minute], from: date)
        let hour = components.hour ?? 0
        let minute = components.minute ?? 0
        return Double(hour * 60 + minute)
    }

    private func dateForMinutes(_ minutes: Double) -> Date {
        let calendar = Calendar.current
        let totalMinutes = Int(minutes.rounded())
        let hour = max(0, min(23, totalMinutes / 60))
        let minute = max(0, min(59, totalMinutes % 60))
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: Date()) ?? Date()
    }

    private func formattedMovementValue(_ value: Double, unit: MovementUnit) -> String {
        switch unit {
        case .count:
            return formattedNumber(value)
        case .meters:
            return formattedDistance(value)
        case .kilocalories:
            return "\(formattedNumber(value)) kcal"
        }
    }

    private func formattedMovementDetail(current: Double, average: Double, unit: MovementUnit) -> String {
        guard average > 0 else { return "Avg --" }
        let delta = current - average
        let sign = delta >= 0 ? "+" : "-"
        let deltaText = formattedMovementValue(abs(delta), unit: unit)
        return "Avg \(formattedMovementValue(average, unit: unit)) (\(sign)\(deltaText) vs avg)"
    }

    private func formattedNumber(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? "--"
    }

    private func formattedDistance(_ meters: Double) -> String {
        let useMetric = Locale.current.usesMetricSystem
        let unit = useMetric ? UnitLength.kilometers : UnitLength.miles
        let measurement = Measurement(value: meters, unit: UnitLength.meters).converted(to: unit)

        let formatter = MeasurementFormatter()
        formatter.unitOptions = .providedUnit
        formatter.unitStyle = .short
        formatter.numberFormatter.maximumFractionDigits = 1

        return formatter.string(from: measurement)
    }
}

private struct MetricRow: View {
    let title: String
    let value: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.subheadline)
                Spacer()
                Text(value)
                    .font(.subheadline)
                    .bold()
            }
            Text(detail)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    DailyRecapContentView(recap: .mock())
}
