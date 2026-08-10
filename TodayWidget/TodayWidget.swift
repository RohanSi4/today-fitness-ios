import ActivityKit
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
            case .accessoryCircular:
                Gauge(value: weeklyRatio) {
                    Image(systemName: entry.snapshot.symbolName)
                } currentValueLabel: {
                    Image(systemName: entry.snapshot.symbolName)
                }
                .gaugeStyle(.accessoryCircularCapacity)
            case .accessoryRectangular:
                rectangular
            default:
                rectangular
            }
        }
        .widgetURL(entry.snapshot.deepLink)
        .containerBackground(.fill.tertiary, for: .widget)
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 7) {
                Image(systemName: entry.snapshot.symbolName)
                    .font(.headline.weight(.semibold))
                Text(entry.snapshot.headline)
                    .font(.headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Spacer(minLength: 5)
                Text(weeklyMileage)
                    .font(.caption2.monospacedDigit().weight(.semibold))
                    .lineLimit(1)
                    .privacySensitive()
            }
            Text(entry.snapshot.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .privacySensitive()
            ProgressView(value: weeklyRatio)
                .privacySensitive()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
}

struct TodayDailyWidget: Widget {
    let kind = TodayWidgetSnapshot.widgetKind

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TodayWidgetProvider()) { entry in
            TodayWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Today")
        .description("Training status and weekly progress for your Lock Screen.")
        .supportedFamilies([
            .accessoryInline,
            .accessoryCircular,
            .accessoryRectangular,
        ])
    }
}

private struct TodayLiveActivityView: View {
    let state: TodaySessionAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 10) {
                Image(systemName: state.symbolName)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(accent)
                    .frame(width: 34, height: 34)
                    .background(accent.opacity(0.16), in: RoundedRectangle(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 1) {
                    Text(state.headline)
                        .font(.headline.weight(.bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    Text(state.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 6)
                Text(weeklyPercent)
                    .font(.caption.monospacedDigit().weight(.bold))
                    .foregroundStyle(accent)
            }

            if !state.tasks.isEmpty {
                HStack(spacing: 8) {
                    ForEach(state.tasks, id: \.title) { task in
                        Label(task.title, systemImage: task.isComplete ? "checkmark.circle.fill" : task.symbolName)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(task.isComplete ? .green : .primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 6)
                            .background(.fill.quaternary, in: Capsule())
                    }
                }
                .privacySensitive()
            }

            ProgressView(value: weeklyRatio)
                .tint(accent)
                .privacySensitive()
        }
        .padding(14)
        .activityBackgroundTint(Color(.secondarySystemBackground))
        .activitySystemActionForegroundColor(accent)
        .widgetURL(URL(string: "today://")!)
    }

    private var accent: Color {
        switch state.phase {
        case .weight: .orange
        case .plan, .remaining: .green
        case .done: .mint
        case .recovery: .indigo
        case .unavailable: .secondary
        }
    }

    private var weeklyRatio: Double {
        guard state.plannedMiles > 0 else { return 0 }
        return min(max(state.completedMiles / state.plannedMiles, 0), 1)
    }

    private var weeklyPercent: String {
        guard state.plannedMiles > 0 else { return "This week" }
        return weeklyRatio.formatted(.percent.precision(.fractionLength(0)))
    }
}

struct TodaySessionLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TodaySessionAttributes.self) { context in
            TodayLiveActivityView(state: context.state)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label("Today", systemImage: context.state.symbolName)
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.green)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(weeklyPercent(for: context.state))
                        .font(.caption.monospacedDigit().weight(.bold))
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 7) {
                        Text(context.state.headline)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        HStack(spacing: 12) {
                            ForEach(context.state.tasks.prefix(2), id: \.title) { task in
                                Label(
                                    task.title,
                                    systemImage: task.isComplete ? "checkmark.circle.fill" : task.symbolName
                                )
                                .font(.caption2.weight(.semibold))
                                .lineLimit(1)
                            }
                        }
                        .privacySensitive()
                    }
                }
            } compactLeading: {
                Image(systemName: context.state.symbolName)
                    .foregroundStyle(.green)
            } compactTrailing: {
                Text(weeklyPercent(for: context.state))
                    .font(.caption2.monospacedDigit().weight(.bold))
            } minimal: {
                Image(systemName: context.state.symbolName)
                    .foregroundStyle(.green)
            }
            .widgetURL(URL(string: "today://")!)
            .keylineTint(.green)
        }
    }

    private func weeklyPercent(for state: TodaySessionAttributes.ContentState) -> String {
        guard state.plannedMiles > 0 else { return "Today" }
        let ratio = min(max(state.completedMiles / state.plannedMiles, 0), 1)
        return ratio.formatted(.percent.precision(.fractionLength(0)))
    }
}

@main
struct TodayWidgetBundle: WidgetBundle {
    var body: some Widget {
        TodayDailyWidget()
        TodaySessionLiveActivity()
    }
}

#Preview(as: .accessoryCircular) {
    TodayDailyWidget()
} timeline: {
    TodayWidgetEntry(date: .now, snapshot: .placeholder)
}

#Preview(as: .accessoryRectangular) {
    TodayDailyWidget()
} timeline: {
    TodayWidgetEntry(date: .now, snapshot: .placeholder)
}
