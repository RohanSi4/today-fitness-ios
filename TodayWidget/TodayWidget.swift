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
        let morning = calendar.date(byAdding: .minute, value: 8 * 60 + 30, to: start) ?? date
        let noon = calendar.date(byAdding: .hour, value: 12, to: start) ?? date
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
            Divider()
            Text(weeklyLine)
                .font(.caption2.monospacedDigit().weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private var weeklyLine: String {
        let completed = entry.snapshot.week.completedMiles.formatted(
            .number.precision(.fractionLength(0...1))
        )
        let planned = entry.snapshot.week.plannedMiles.formatted(
            .number.precision(.fractionLength(0...1))
        )
        return "Week: \(completed)/\(planned) mi · \(entry.snapshot.week.completedLifts) lifts"
    }
}

struct TodayDailyWidget: Widget {
    let kind = TodayWidgetSnapshot.widgetKind

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TodayWidgetProvider()) { entry in
            TodayWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Today")
        .description("Morning weight, today’s plan, and what you have finished.")
        .supportedFamilies([.accessoryInline, .accessoryRectangular, .systemSmall])
    }
}

@main
struct TodayWidgetBundle: WidgetBundle {
    var body: some Widget {
        TodayDailyWidget()
    }
}
