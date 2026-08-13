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
        var entries = [TodayWidgetEntry(date: now, snapshot: snapshot)]

        // The midnight entry is pre-rendered rather than left to the reload.
        //
        // A one-entry timeline plus `.after(midnight)` puts the whole day
        // rollover behind a refresh the system is free to defer, and when it
        // defers, the Lock Screen spends the morning insisting yesterday's lift
        // is the news. WidgetKit swaps to an entry it already holds without
        // waking the extension at all, so booking the rolled-over day in advance
        // makes the rollover happen on time whatever the refresh budget is doing.
        //
        // `carriedForward` is the same function the load path uses, so the
        // pre-rendered day cannot drift from the one a live reload would build.
        if let midnight = Calendar.current.nextDate(
            after: now,
            matching: DateComponents(hour: 0, minute: 0, second: 0),
            matchingPolicy: .nextTime
        ), let rolled = snapshot.carriedForward(to: midnight) {
            entries.append(TodayWidgetEntry(date: midnight, snapshot: rolled))
        }

        completion(Timeline(entries: entries, policy: .after(refreshDate(for: snapshot, after: now))))
    }

    /// While a lift is open the app pushes a reload on every checked set, so the
    /// only reload the timeline itself has to book is the one that retires a
    /// session he never finished. Scheduling it for the exact staleness deadline
    /// costs one extra refresh instead of the dozens a polling cadence would.
    private func refreshDate(for snapshot: TodayWidgetSnapshot, after date: Date) -> Date {
        let scheduled = nextRefresh(after: date)
        guard let workout = snapshot.workout else { return scheduled }
        let expiry = workout.restAnchor.addingTimeInterval(TodayWidgetWorkout.staleAfter)
        return min(scheduled, max(expiry, date.addingTimeInterval(60)))
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
                inline
            case .accessoryCircular:
                circular
            case .accessoryRectangular:
                rectangular
            case .systemSmall:
                systemSmall
            case .systemMedium:
                systemMedium
            default:
                rectangular
            }
        }
        .widgetURL(entry.snapshot.deepLink)
        .containerBackground(.fill.tertiary, for: .widget)
    }

    private var workout: TodayWidgetWorkout? { entry.snapshot.workout }
    private var recap: TodayWidgetRecap? { entry.snapshot.recap }

    /// What this says when no lift is open — which, in the car, is always.
    ///
    /// Priority is deliberate: what he has already done outranks what is
    /// planned, because once the session is logged the plan line is the less
    /// interesting of the two and he has just asked the widget "how did that
    /// go". Both beat the old "Open Today for the private plan", which said
    /// nothing at all on a dashboard he cannot unlock.
    private var idleHeadline: String {
        recap.map { "\($0.title) done" } ?? entry.snapshot.headline
    }

    private var idleDetail: String {
        recap?.summary ?? entry.snapshot.planLine ?? entry.snapshot.detail
    }

    private var idleSymbol: String {
        recap == nil ? entry.snapshot.symbolName : "checkmark.circle.fill"
    }

    /// The inline family has no redaction of its own, so it never names a
    /// movement - only the clock, which gives nothing away.
    @ViewBuilder
    private var inline: some View {
        if let workout {
            Label {
                Text(workout.restAnchor, style: .timer)
            } icon: {
                Image(systemName: "timer")
            }
        } else {
            Label(idleHeadline, systemImage: idleSymbol)
        }
    }

    /// Mid-lift the circular gauge tracks sets rather than weekly miles: during
    /// a session the question is how much of *this* is left.
    private var circular: some View {
        Gauge(value: workout?.setRatio ?? weeklyRatio) {
            Image(systemName: symbolName)
        } currentValueLabel: {
            if let workout {
                Text("\(workout.completedSets)")
                    .font(.system(.body, design: .rounded).weight(.bold))
                    .privacySensitive()
            } else {
                Image(systemName: symbolName)
            }
        }
        .gaugeStyle(.accessoryCircularCapacity)
    }

    private var symbolName: String {
        workout == nil ? idleSymbol : "timer"
    }

    @ViewBuilder
    private var rectangular: some View {
        if let workout {
            workoutRectangular(workout)
        } else {
            planRectangular
        }
    }

    /// Rest clock, what is up next, and how far through the session he is.
    ///
    /// The clock is a `.timer` text rather than a number this extension
    /// computed: the system re-draws that one on its own every second, which is
    /// the only thing here that survives the phone staying locked.
    private func workoutRectangular(_ workout: TodayWidgetWorkout) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 7) {
                Image(systemName: "timer")
                    .font(.headline.weight(.semibold))
                Text(workout.restAnchor, style: .timer)
                    .font(.headline.monospacedDigit())
                    .lineLimit(1)
                Spacer(minLength: 5)
                // Sets alone cannot say how much is left: 8 of 17 is a different
                // session with two movements to go than with five.
                Text(workout.exercisePosition.map { "\(workout.completedSets)/\(workout.plannedSets) · \($0)" }
                    ?? "\(workout.completedSets)/\(workout.plannedSets)")
                    .font(.caption2.monospacedDigit().weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .privacySensitive()
            }
            Text(nextLine(for: workout))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .privacySensitive()
            ProgressView(value: workout.setRatio)
                .privacySensitive()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func nextLine(for workout: TodayWidgetWorkout) -> String {
        guard let next = workout.nextExercise else {
            return workout.completedSets == 0 ? workout.title : "Last set in"
        }
        return "Next: \(next)"
    }

    private var planRectangular: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 7) {
                Image(systemName: entry.snapshot.symbolName)
                    .font(.headline.weight(.semibold))
                Text(idleHeadline)
                    .font(.headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Spacer(minLength: 5)
                Text(weeklyMileage)
                    .font(.caption2.monospacedDigit().weight(.semibold))
                    .lineLimit(1)
                    .privacySensitive()
            }
            HStack(spacing: 6) {
                Text(idleDetail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Spacer(minLength: 4)
                Text("\(entry.snapshot.week.completedRuns)r · \(entry.snapshot.week.completedLifts)l")
                    .font(.caption2.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .privacySensitive()
            ProgressView(value: weeklyRatio)
                .privacySensitive()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The Home Screen and CarPlay square. Sized for a glance from arm's length,
    /// so the clock is the biggest thing on it during a lift.
    private var systemSmall: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: symbolName)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tint)
                Text(workout != nil ? "REST" : (recap == nil ? "TODAY" : "DONE"))
                    .font(.caption2.weight(.bold))
                    .tracking(0.8)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }

            Spacer(minLength: 4)

            if let workout {
                Text(workout.restAnchor, style: .timer)
                    .font(.system(size: 34, weight: .bold, design: .rounded).monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Text(nextLine(for: workout))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .privacySensitive()
            } else {
                Text(idleHeadline)
                    .font(.headline)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                Text(idleDetail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .minimumScaleFactor(0.8)
                    .privacySensitive()
            }

            Spacer(minLength: 6)

            Text(footnote)
                .font(.caption2.monospacedDigit().weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .privacySensitive()
            ProgressView(value: workout?.setRatio ?? weeklyRatio)
                .tint(.green)
                .privacySensitive()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    /// The wide one: the session on the left, the training week on the right,
    /// because in the car the week is the part he cannot get at a glance
    /// anywhere else.
    private var systemMedium: some View {
        HStack(alignment: .top, spacing: 14) {
            systemSmall
            Divider()
            VStack(alignment: .leading, spacing: 6) {
                Text("THIS WEEK")
                    .font(.caption2.weight(.bold))
                    .tracking(0.8)
                    .foregroundStyle(.secondary)
                Text(weeklyMileage)
                    .font(.title3.monospacedDigit().weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .privacySensitive()
                Label("\(entry.snapshot.week.completedRuns) runs", systemImage: "figure.run")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .privacySensitive()
                Label("\(entry.snapshot.week.completedLifts) lifts", systemImage: "dumbbell.fill")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .privacySensitive()
                Spacer(minLength: 0)
                ProgressView(value: weeklyRatio)
                    .tint(.green)
                    .privacySensitive()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    /// The bottom line of the square: how far through the session, or how far
    /// through the training week.
    private var footnote: String {
        guard let workout else { return weeklyMileage }
        guard let position = workout.exercisePosition else {
            return "\(workout.completedSets)/\(workout.plannedSets) sets"
        }
        return "\(workout.completedSets)/\(workout.plannedSets) sets · \(position)"
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
            // The Home Screen families are also what CarPlay's dashboard offers:
            // it lists any widget already on the iPhone, and needs no CarPlay
            // entitlement to do it — which matters, because Apple grants those
            // only to Audio, Communication, EV Charging, Navigation, Parking and
            // Quick Food Ordering apps, and a training app is none of them.
            // Declaring only the accessory families is why this could not be put
            // in the car at all.
            .systemSmall,
            .systemMedium,
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
                        .privacySensitive()
                }
                Spacer(minLength: 6)
                if let restAnchor = state.restAnchor {
                    // Mid-lift the weekly percentage is the wrong number to give
                    // this corner. The clock is what he is looking at the phone
                    // for, and `.timer` keeps it moving with no push from the
                    // app - which is the whole point on a locked screen.
                    VStack(alignment: .trailing, spacing: 0) {
                        Text(restAnchor, style: .timer)
                            .font(.callout.monospacedDigit().weight(.bold))
                            .foregroundStyle(accent)
                            .lineLimit(1)
                            .frame(minWidth: 54, alignment: .trailing)
                        Text("\(state.completedSets)/\(state.plannedSets) sets")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .privacySensitive()
                    }
                } else {
                    Text(weeklyPercent)
                        .font(.caption.monospacedDigit().weight(.bold))
                        .foregroundStyle(accent)
                }
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

            ProgressView(value: state.restAnchor == nil ? weeklyRatio : setRatio)
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

    private var setRatio: Double {
        guard state.plannedSets > 0 else { return 0 }
        return min(max(Double(state.completedSets) / Double(state.plannedSets), 0), 1)
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
                    if let restAnchor = context.state.restAnchor {
                        Text(restAnchor, style: .timer)
                            .font(.caption.monospacedDigit().weight(.bold))
                            .frame(minWidth: 54, alignment: .trailing)
                    } else {
                        Text(weeklyPercent(for: context.state))
                            .font(.caption.monospacedDigit().weight(.bold))
                    }
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
                if let restAnchor = context.state.restAnchor {
                    Text(restAnchor, style: .timer)
                        .font(.caption2.monospacedDigit().weight(.bold))
                        .frame(minWidth: 42)
                } else {
                    Text(weeklyPercent(for: context.state))
                        .font(.caption2.monospacedDigit().weight(.bold))
                }
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
    TodayWidgetEntry(date: .now, snapshot: .workoutPlaceholder)
}

#Preview(as: .systemSmall) {
    TodayDailyWidget()
} timeline: {
    TodayWidgetEntry(date: .now, snapshot: .workoutPlaceholder)
    TodayWidgetEntry(date: .now, snapshot: .recapPlaceholder)
    TodayWidgetEntry(date: .now, snapshot: .placeholder)
}

#Preview(as: .systemMedium) {
    TodayDailyWidget()
} timeline: {
    TodayWidgetEntry(date: .now, snapshot: .recapPlaceholder)
    TodayWidgetEntry(date: .now, snapshot: .workoutPlaceholder)
    TodayWidgetEntry(date: .now, snapshot: .placeholder)
}
