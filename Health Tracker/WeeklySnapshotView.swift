import SwiftUI

struct WeeklySnapshotView: View {
    @ObservedObject var store: TodayStore
    @ObservedObject var planService: TrainingPlanService
    @ObservedObject var runService: RunningWorkoutService

    private var snapshot: WeeklyTrainingSnapshot {
        WeeklyTrainingBuilder.build(
            plan: planService.plan,
            runs: runService.workouts,
            lifts: store.workouts
        )
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                summaryCard
                weekTable
            }
            .padding(16)
            .padding(.bottom, 24)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("This week")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            async let plan: Void = planService.refresh()
            async let runs: Void = runService.refresh()
            _ = await (plan, runs)
        }
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Weekly snapshot")
                        .font(.title2.weight(.bold))
                    Text(dateRange)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if planService.isLoading {
                    ProgressView().controlSize(.small)
                }
            }

            HStack(spacing: 10) {
                weeklyMetric(
                    value: "\(formatMiles(snapshot.completedMiles))/\(formatMiles(snapshot.prescribedMiles))",
                    label: "miles"
                )
                weeklyMetric(value: "\(snapshot.completedRuns)", label: "runs")
                weeklyMetric(value: "\(snapshot.completedLifts)", label: "lifts")
                weeklyMetric(value: "\(snapshot.workingSets)", label: "sets")
            }

            ProgressView(
                value: min(snapshot.completedMiles, snapshot.prescribedMiles),
                total: max(snapshot.prescribedMiles, 1)
            )
            .tint(TodayPalette.accent)
            .accessibilityLabel("Weekly running mileage")
            .accessibilityValue(
                "\(formatMiles(snapshot.completedMiles)) of \(formatMiles(snapshot.prescribedMiles)) miles"
            )
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .todayCard()
    }

    private var weekTable: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("Day").frame(width: 42, alignment: .leading)
                Text("Run").frame(maxWidth: .infinity, alignment: .leading)
                Text("Lift + other").frame(maxWidth: .infinity, alignment: .leading)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 11)

            Divider()

            ForEach(Array(snapshot.days.enumerated()), id: \.element.id) { index, day in
                weekRow(day)
                if index < snapshot.days.count - 1 {
                    Divider().padding(.leading, 64)
                }
            }
        }
        .todayCard()
        .accessibilityIdentifier("weekly-snapshot-table")
    }

    private func weekRow(_ day: WeeklyDaySnapshot) -> some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(day.dayLabel)
                    .font(.subheadline.weight(.semibold))
                Text(day.date.formatted(.dateTime.day()))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .frame(width: 42, alignment: .leading)

            taskCell(
                title: runTitle(day),
                detail: runDetail(day),
                complete: day.runCompleted,
                planned: day.plannedRunMiles != nil
            )

            taskCell(
                title: liftTitle(day),
                detail: liftDetail(day),
                complete: day.liftCompleted,
                planned: day.plannedLift != nil
            )
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background {
            if Calendar.current.isDateInToday(day.date) {
                TodayPalette.accent.opacity(0.07)
            }
        }
    }

    private func taskCell(
        title: String,
        detail: String?,
        complete: Bool,
        planned: Bool
    ) -> some View {
        HStack(alignment: .top, spacing: 6) {
            if planned {
                Image(systemName: complete ? "checkmark.circle.fill" : "circle")
                    .font(.caption)
                    .foregroundStyle(complete ? .green : .secondary)
                    .padding(.top, 2)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption.weight(planned ? .semibold : .regular))
                    .foregroundStyle(planned ? .primary : .secondary)
                    .lineLimit(2)
                if let detail {
                    Text(detail)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func weeklyMetric(value: String, label: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.headline.monospacedDigit().weight(.bold))
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func runTitle(_ day: WeeklyDaySnapshot) -> String {
        guard let miles = day.plannedRunMiles else {
            return day.run.map { "\(formatMiles($0.miles)) mi extra" } ?? "Rest"
        }
        return "\(formatMiles(miles)) mi"
    }

    private func runDetail(_ day: WeeklyDaySnapshot) -> String? {
        guard let run = day.run else { return nil }
        let minutes = Int((run.duration / 60).rounded())
        guard let pace = run.paceSecondsPerMile else { return "\(minutes)m" }
        let paceMinutes = Int(pace) / 60
        let paceSeconds = Int(pace) % 60
        return "\(formatMiles(run.miles)) mi · \(minutes)m · \(paceMinutes):\(String(format: "%02d", paceSeconds))/mi"
    }

    private func liftTitle(_ day: WeeklyDaySnapshot) -> String {
        if let kind = day.plannedLift { return kind.title }
        if let extra = day.extraLift { return extra.kind.title }
        return day.plannedOther ?? "Rest"
    }

    private func liftDetail(_ day: WeeklyDaySnapshot) -> String? {
        let workout = day.lift ?? day.extraLift
        guard let workout else { return nil }
        return "\(workout.completedSetCount) working sets"
    }

    private var dateRange: String {
        "\(snapshot.startDate.formatted(.dateTime.month(.abbreviated).day())) to \(snapshot.endDate.formatted(.dateTime.month(.abbreviated).day()))"
    }

    private func formatMiles(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(value.rounded() == value ? 0 : 1)))
    }
}

struct WeeklySnapshotCard: View {
    let snapshot: WeeklyTrainingSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                Label("This week", systemImage: "calendar")
                    .font(.headline)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
            }

            HStack(alignment: .firstTextBaseline) {
                Text("\(formatMiles(snapshot.completedMiles))")
                    .font(.title2.monospacedDigit().weight(.bold))
                Text("of \(formatMiles(snapshot.prescribedMiles)) miles")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(snapshot.completedLifts) lift\(snapshot.completedLifts == 1 ? "" : "s")")
                    .font(.subheadline.monospacedDigit().weight(.semibold))
            }

            HStack(spacing: 7) {
                ForEach(snapshot.days) { day in
                    VStack(spacing: 5) {
                        Circle()
                            .fill(statusColor(day))
                            .frame(width: 9, height: 9)
                        Text(day.dayLabel.prefix(1))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Calendar.current.isDateInToday(day.date) ? .primary : .secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .todayCard()
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "This week, \(formatMiles(snapshot.completedMiles)) of \(formatMiles(snapshot.prescribedMiles)) miles and \(snapshot.completedLifts) lifts"
        )
        .accessibilityIdentifier("weekly-snapshot-card")
    }

    private func statusColor(_ day: WeeklyDaySnapshot) -> Color {
        if day.isFullyComplete { return .green }
        if day.run != nil || day.lift != nil || day.extraLift != nil { return TodayPalette.warm }
        if day.plannedRunMiles != nil || day.plannedLift != nil { return Color.secondary.opacity(0.3) }
        return TodayPalette.accent.opacity(0.25)
    }

    private func formatMiles(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(value.rounded() == value ? 0 : 1)))
    }
}
