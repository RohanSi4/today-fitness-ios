import SwiftUI
import WidgetKit

private struct TodayWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: TodayWidgetSnapshot
}

private struct TodayWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> TodayWidgetEntry {
        TodayWidgetEntry(date: .now, snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (TodayWidgetEntry) -> Void) {
        let snapshot = context.isPreview
            ? TodayWidgetSnapshot.placeholder
            : TodayWidgetSnapshot.load() ?? .fallback
        completion(TodayWidgetEntry(date: .now, snapshot: snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TodayWidgetEntry>) -> Void) {
        let now = Date()
        let snapshot = TodayWidgetSnapshot.load() ?? .fallback
        let entry = TodayWidgetEntry(date: now, snapshot: snapshot)
        completion(Timeline(entries: [entry], policy: .after(nextRefresh(after: now))))
    }

    private func nextRefresh(after date: Date) -> Date {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: date)
        // These are wall-clock times, so they have to be *set*, not added.
        // Adding 510 minutes to midnight preserves elapsed duration rather than
        // clock position, so on the spring-forward day the 08:30 refresh landed
        // at 09:30 and noon landed at 13:00.
        let morning = calendar.date(bySettingHour: 8, minute: 30, second: 0, of: date) ?? date
        let noon = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: date) ?? date
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: start) ?? date.addingTimeInterval(86_400)
        if date < morning { return morning }
        if date < noon { return noon }
        return tomorrow
    }
}

private struct TodayWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: TodayWidgetEntry

    var body: some View {
        Group {
            switch family {
            case .accessoryInline:
                Label(entry.snapshot.headline, systemImage: entry.snapshot.symbolName)
            case .accessoryRectangular:
                rectangular
            case .systemMedium:
                medium
            case .systemLarge:
                large
            default:
                small
            }
        }
        .widgetURL(entry.snapshot.deepLink)
        .containerBackground(.fill.tertiary, for: .widget)
    }

    private var rectangular: some View {
        HStack(spacing: 9) {
            Image(systemName: entry.snapshot.symbolName)
                .font(.title3.weight(.semibold))
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.snapshot.headline)
                    .font(.headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(entry.snapshot.detail)
                    .font(.caption)
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
                    .privacySensitive()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: entry.snapshot.symbolName)
                .font(.title2.weight(.semibold))
                .foregroundStyle(.green)
            Spacer(minLength: 0)
            Text(entry.snapshot.headline)
                .font(.headline)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
            Text(entry.snapshot.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .privacySensitive()
            Divider()
            Text(weeklyLine)
                .font(.caption2.monospacedDigit().weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .privacySensitive()
        }
    }

    private var medium: some View {
        HStack(spacing: 16) {
            statusPanel
                .frame(maxWidth: .infinity, alignment: .leading)

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                weeklyProgress
                quickActions(compact: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var large: some View {
        VStack(alignment: .leading, spacing: 16) {
            statusPanel

            weeklyProgress
                .padding(14)
                .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 18, style: .continuous))

            VStack(alignment: .leading, spacing: 10) {
                Text("Quick open")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                quickActions(compact: false)
            }

            Spacer(minLength: 0)

            Label("Private details stay inside Today", systemImage: "lock.fill")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var statusPanel: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: entry.snapshot.symbolName)
                .font(.title2.weight(.semibold))
                .foregroundStyle(accent)
                .frame(width: 42, height: 42)
                .background(accent.opacity(0.14), in: RoundedRectangle(cornerRadius: 13, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text("Today")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Text(entry.snapshot.headline)
                    .font(.title3.weight(.bold))
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                Text(entry.snapshot.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .privacySensitive()
            }
        }
    }

    private var weeklyProgress: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Text("This week")
                    .font(.subheadline.weight(.semibold))
                Spacer(minLength: 8)
                Text(weeklyMileage)
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.secondary)
                    .privacySensitive()
            }

            ProgressView(value: weeklyRatio)
                .tint(accent)
                .privacySensitive()

            HStack(spacing: 14) {
                Label("\(entry.snapshot.week.completedRuns) runs", systemImage: "figure.run")
                Label("\(entry.snapshot.week.completedLifts) lifts", systemImage: "dumbbell.fill")
            }
            .font(.caption2.weight(.medium))
            .foregroundStyle(.secondary)
            .privacySensitive()
        }
    }

    private func quickActions(compact: Bool) -> some View {
        HStack(spacing: 8) {
            WidgetQuickAction(
                title: compact ? nil : "Weight",
                symbol: "scalemass.fill",
                destination: URL(string: "today://weight")!
            )
            WidgetQuickAction(
                title: compact ? nil : "Plan",
                symbol: "calendar",
                destination: URL(string: "today://")!
            )
            WidgetQuickAction(
                title: compact ? nil : "Workout",
                symbol: "dumbbell.fill",
                destination: URL(string: "today://workout")!
            )
        }
    }

    private var accent: Color {
        switch entry.snapshot.phase {
        case .weight: .orange
        case .plan, .remaining: .green
        case .done: .mint
        case .recovery: .indigo
        case .unavailable: .secondary
        }
    }

    private var weeklyRatio: Double {
        guard entry.snapshot.week.plannedMiles > 0 else { return 0 }
        return min(max(entry.snapshot.week.completedMiles / entry.snapshot.week.plannedMiles, 0), 1)
    }

    private var weeklyMileage: String {
        let completed = entry.snapshot.week.completedMiles.formatted(
            .number.precision(.fractionLength(0...1))
        )
        let planned = entry.snapshot.week.plannedMiles.formatted(
            .number.precision(.fractionLength(0...1))
        )
        return "\(completed) / \(planned) mi"
    }

    private var weeklyLine: String {
        "Week: \(weeklyMileage) · \(entry.snapshot.week.completedLifts) lifts"
    }
}

private struct WidgetQuickAction: View {
    let title: String?
    let symbol: String
    let destination: URL

    var body: some View {
        Link(destination: destination) {
            if let title {
                VStack(spacing: 5) {
                    Image(systemName: symbol)
                        .font(.headline)
                    Text(title)
                        .font(.caption2.weight(.semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
            } else {
                Image(systemName: symbol)
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 32)
            }
        }
        .buttonStyle(.plain)
        .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityLabel(title ?? accessibilityTitle)
    }

    private var accessibilityTitle: String {
        switch destination.host {
        case "weight": "Log weight"
        case "workout": "Start workout"
        default: "Open plan"
        }
    }
}

struct TodayDailyWidget: Widget {
    let kind = TodayWidgetSnapshot.widgetKind

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TodayWidgetProvider()) { entry in
            TodayWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Today")
        .description("Private training status, weekly progress, and quick actions.")
        .supportedFamilies([
            .accessoryInline,
            .accessoryRectangular,
            .systemSmall,
            .systemMedium,
            .systemLarge,
        ])
    }
}

@main
struct TodayWidgetBundle: WidgetBundle {
    var body: some Widget {
        TodayDailyWidget()
    }
}

#Preview(as: .systemSmall) {
    TodayDailyWidget()
} timeline: {
    TodayWidgetEntry(date: .now, snapshot: .placeholder)
}

#Preview(as: .systemMedium) {
    TodayDailyWidget()
} timeline: {
    TodayWidgetEntry(date: .now, snapshot: .placeholder)
}

#Preview(as: .systemLarge) {
    TodayDailyWidget()
} timeline: {
    TodayWidgetEntry(date: .now, snapshot: .placeholder)
}
