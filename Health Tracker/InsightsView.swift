import AppIntents
import Charts
import SwiftUI

struct InsightsView: View {
    @ObservedObject var store: TodayStore
    @ObservedObject var catalog: ExerciseCatalog
    @ObservedObject var coachSync: CoachSyncService
    @ObservedObject var planService: TrainingPlanService
    @ObservedObject var runService: RunningWorkoutService
    let recapDate: Date?

    @State private var showingRecap = false
    @State private var showingCoachSync = false

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                weightProgress
                weeklyTraining
                coachConnection
                quickAccess
                recentMuscleWork
                strengthProgress

                Button {
                    showingRecap = true
                } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "bed.double.fill")
                            .font(.title2)
                            .foregroundStyle(.indigo)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Sleep and movement recap").font(.headline)
                            Text("The original Health Recap is still here.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                    }
                    .padding(16)
                }
                .buttonStyle(.plain)
                .todayCard()
                .accessibilityIdentifier("sleep-movement-recap-button")
            }
            .padding(16)
            .padding(.bottom, 28)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Insights")
        .sheet(isPresented: $showingRecap) {
            DailyRecapView(targetDate: recapDate)
        }
        .sheet(isPresented: $showingCoachSync) {
            CoachSyncView(service: coachSync, store: store)
        }
    }

    private var weightProgress: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Weight goal", systemImage: "scalemass.fill")
                .font(.headline)
            if let latest = store.latestWeight {
                HStack(alignment: .firstTextBaseline) {
                    Text("\(latest.pounds.formatted(.number.precision(.fractionLength(1))))")
                        .font(.system(size: 38, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text("lb").foregroundStyle(.secondary)
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(goalGapValue(from: latest.pounds))
                            .font(.headline.monospacedDigit())
                        // Read the goal instead of hard-coding it, so this cannot
                        // quietly disagree with the dashed line on the chart.
                        Text(goalGapCaption(from: latest.pounds))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                }

                if let average = store.sevenDayAverage {
                    insightRow("7-day average", "\(average.formatted(.number.precision(.fractionLength(1)))) lb")
                }
                if let change = store.thirtyDayChange {
                    insightRow("30-day change", "\(change.formatted(.number.sign(strategy: .always()).precision(.fractionLength(1)))) lb")
                }

                if weightChartEntries.count >= 2, let domain = weightChartDomain {
                    Chart {
                        ForEach(weightChartEntries) { entry in
                            LineMark(
                                x: .value("Day", entry.date),
                                y: .value("Weight", entry.pounds)
                            )
                            .foregroundStyle(TodayPalette.accent)
                            .interpolationMethod(.catmullRom)

                            PointMark(
                                x: .value("Day", entry.date),
                                y: .value("Weight", entry.pounds)
                            )
                            .foregroundStyle(TodayPalette.accent)
                            .symbolSize(entry.id == store.latestWeight?.id ? 38 : 10)
                        }
                        RuleMark(y: .value("Goal", store.goalWeight))
                            .foregroundStyle(.secondary.opacity(0.5))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    }
                    // Without this Swift Charts anchors the domain at zero and
                    // rounds out to 200, so a month of real mornings reads as a
                    // flat line in the top tenth of the card.
                    .chartYScale(domain: domain)
                    .chartXAxis(.hidden)
                    .chartYAxis {
                        // Four marks rather than three: now that the window is a
                        // dozen pounds instead of two hundred, the extra
                        // gridline is worth reading.
                        AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { mark in
                            if let pounds = mark.as(Double.self) {
                                AxisValueLabel {
                                    Text(pounds.formatted(.number.precision(.fractionLength(0))))
                                }
                            }
                            AxisGridLine().foregroundStyle(.secondary.opacity(0.12))
                        }
                    }
                    .frame(height: 150)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Body weight trend for the last 30 days")
                    .accessibilityValue(weightTrendDescription)

                    if clippedEntryCount > 0 {
                        Text(
                            clippedEntryCount == 1
                                ? "One reading sits outside this range. Log that day again to correct it."
                                : "\(clippedEntryCount) readings sit outside this range. Log those days again to correct them."
                        )
                        .font(.caption)
                        .foregroundStyle(TodayPalette.warm)
                    }
                }
            } else {
                Text("Log a few mornings and your trend will show here.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Text("Daily history stays in Today, Apple Health, and the encrypted coach sync. Public progress is always your choice.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .todayCard()
    }

    private var coachConnection: some View {
        Button {
            showingCoachSync = true
        } label: {
            HStack(spacing: 14) {
                Image(systemName: coachSync.state.symbol)
                    .font(.title2)
                    .foregroundStyle(coachSync.isConnected ? TodayPalette.accent : .secondary)
                    .frame(width: 40, height: 40)
                    .background(TodayPalette.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 3) {
                    Text("Coach sync").font(.headline)
                    Text(coachSyncSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if coachSync.state == .syncing {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                }
            }
            .padding(16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .todayCard()
    }

    private var quickAccess: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Quick access", systemImage: "bolt.fill")
                .font(.headline)
            Text("Log weight, open the plan, or start a workout from Siri, Spotlight, Shortcuts, or an Action Button.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            ShortcutsLink()
                .shortcutsLinkStyle(.automaticOutline)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .todayCard()
    }

    private var coachSyncSummary: String {
        switch coachSync.state {
        case .notConnected: "Connect Today to the private fitness coach"
        case .ready: "Changes are waiting to sync"
        case .syncing: "Sending the latest fitness data"
        case .synced(let date): "Up to date \(date.formatted(.relative(presentation: .named)))"
        case .failed: "Saved here and waiting to retry"
        }
    }

    private var weeklyTraining: some View {
        NavigationLink {
            WeeklySnapshotView(
                store: store,
                planService: planService,
                runService: runService
            )
        } label: {
            WeeklySnapshotCard(
                snapshot: WeeklyTrainingBuilder.build(
                    plan: planService.plan,
                    runs: runService.workouts,
                    lifts: store.workouts
                ),
                runDataIsTrustworthy: runService.hasTrustworthyRunData
            )
        }
        .buttonStyle(.plain)
    }

    private var recentMuscleWork: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Last 7 days").font(.headline)
                Spacer()
                Text("Muscles trained").font(.caption).foregroundStyle(.secondary)
            }
            MuscleMapView(scores: recentScores, compact: true)
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .todayCard()
    }

    @ViewBuilder
    private var strengthProgress: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Strength progress").font(.headline)
            let records = exerciseRecords
            if records.isEmpty {
                Text("Your best sets and estimated strength will appear after the first workout.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(records.prefix(6), id: \.exercise.id) { record in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(record.exercise.name).font(.subheadline.weight(.semibold))
                            Text("Best recorded set").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(record.label)
                            .font(.subheadline.monospacedDigit().weight(.semibold))
                    }
                    if record.exercise.id != records.prefix(6).last?.exercise.id {
                        Divider()
                    }
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .todayCard()
    }

    private var recentScores: [MuscleGroup: Double] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        return store.workouts.filter { $0.startedAt >= cutoff }.reduce(into: [:]) { result, workout in
            for (muscle, value) in store.muscleScores(for: workout, catalog: catalog) {
                result[muscle, default: 0] += value
            }
        }
    }

    private var exerciseRecords: [(exercise: ExerciseDefinition, label: String, estimate: Double)] {
        var records: [String: (exercise: ExerciseDefinition, label: String, estimate: Double)] = [:]
        var latestTrainingDates: [String: Date] = [:]
        for workout in store.workouts {
            for logged in workout.exercises {
                guard let exercise = catalog.exercise(id: logged.exerciseID) else { continue }
                for set in logged.sets where set.isPerformed {
                    latestTrainingDates[exercise.id] = max(
                        latestTrainingDates[exercise.id] ?? .distantPast,
                        workout.startedAt
                    )
                    let weight = set.weight ?? 0
                    let estimate = weight > 0 ? weight * (1 + Double(set.reps) / 30) : Double(set.reps)
                    guard estimate > (records[exercise.id]?.estimate ?? -1) else { continue }
                    let label = weight > 0
                        ? "\(weight.formatted(.number.precision(.fractionLength(0...1)))) × \(set.reps)"
                        : "\(set.reps) reps"
                    records[exercise.id] = (exercise, label, estimate)
                }
            }
        }
        return records.values.sorted {
            (latestTrainingDates[$0.exercise.id] ?? .distantPast) >
                (latestTrainingDates[$1.exercise.id] ?? .distantPast)
        }
    }

    private var weightChartEntries: [WeightEntry] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        return store.weights.filter { $0.date >= cutoff }.sorted { $0.date < $1.date }
    }

    private var weightChartDomain: ClosedRange<Double>? {
        WeightChartScale.domain(
            for: weightChartEntries.map(\.pounds),
            goal: store.goalWeight
        )
    }

    /// Readings the domain deliberately left out, almost always a mistyped entry.
    private var clippedEntryCount: Int {
        guard let domain = weightChartDomain else { return 0 }
        return weightChartEntries.filter { !domain.contains($0.pounds) }.count
    }

    private var weightTrendDescription: String {
        guard let first = weightChartEntries.first, let last = weightChartEntries.last else {
            return "No readings yet"
        }
        let change = last.pounds - first.pounds
        let direction = change < -0.05 ? "down" : (change > 0.05 ? "up" : "level at")
        let magnitude = abs(change) < 0.05
            ? last.pounds.formatted(.number.precision(.fractionLength(1)))
            : abs(change).formatted(.number.precision(.fractionLength(1)))
        return "\(weightChartEntries.count) readings, \(direction) \(magnitude) pounds, "
            + "now \(last.pounds.formatted(.number.precision(.fractionLength(1)))) pounds"
    }

    private func goalGapValue(from pounds: Double) -> String {
        let gap = pounds - store.goalWeight
        guard gap > 0.05 else { return "At goal" }
        return "\(gap.formatted(.number.precision(.fractionLength(1)))) lb"
    }

    private func goalGapCaption(from pounds: Double) -> String {
        let goal = store.goalWeight.formatted(.number.precision(.fractionLength(0...1)))
        return pounds - store.goalWeight > 0.05 ? "to \(goal)" : "goal \(goal)"
    }

    private func insightRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.subheadline.monospacedDigit().weight(.semibold))
        }
        .font(.subheadline)
    }
}
