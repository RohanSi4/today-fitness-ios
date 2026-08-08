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
                StatTile(
                    "\(formatMiles(snapshot.completedMiles))/\(formatMiles(snapshot.prescribedMiles))",
                    "miles",
                    style: .plain
                )
                StatTile(snapshot.completedRuns, "runs", style: .plain)
                StatTile(snapshot.completedLifts, "lifts", style: .plain)
                StatTile(snapshot.workingSets, "sets", style: .plain)
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
        if let extra = day.extraLift { return extra.routineTemplate?.title ?? extra.kind.title }
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
}

struct WeeklySnapshotCard: View {
    let snapshot: WeeklyTrainingSnapshot

    /// Defaults to true so every existing call site and preview reads the same as
    /// before. Passed as false only when Apple Health has never been read, which
    /// is when the mileage below is a guess rather than a total.
    var runDataIsTrustworthy = true

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
                    .foregroundStyle(runDataIsTrustworthy ? .primary : .secondary)
                Text("of \(formatMiles(snapshot.prescribedMiles)) miles")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(snapshot.completedLifts) lift\(snapshot.completedLifts == 1 ? "" : "s")")
                    .font(.subheadline.monospacedDigit().weight(.semibold))
            }

            if !runDataIsTrustworthy {
                Label("Runs not read from Apple Health yet", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
                + (runDataIsTrustworthy ? "" : ". Runs have not been read from Apple Health yet.")
        )
        .accessibilityIdentifier("weekly-snapshot-card")
    }

    private func statusColor(_ day: WeeklyDaySnapshot) -> Color {
        if day.isFullyComplete { return .green }
        if day.run != nil || day.lift != nil || day.extraLift != nil { return TodayPalette.warm }
        if day.plannedRunMiles != nil || day.plannedLift != nil { return Color.secondary.opacity(0.3) }
        return TodayPalette.accent.opacity(0.25)
    }
}

/// Miles read as "5" or "5.1", never "5.0". Shared because the weekly card and
/// the weekly detail both showed the same number and had their own copy.
func formatMiles(_ value: Double) -> String {
    value.formatted(.number.precision(.fractionLength(value.rounded() == value ? 0 : 1)))
}
