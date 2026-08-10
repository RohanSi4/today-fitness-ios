import Foundation
import SwiftUI

enum PlanInstructionKind: Equatable {
    case run
    case lift
    case swim
    case other
}

extension TrainingPlanDay {
    var hasSwim: Bool {
        taskComponents.contains { $0.localizedCaseInsensitiveContains("swim") }
    }

    func remainingTasks(runCompleted: Bool, liftCompleted: Bool) -> [String] {
        taskComponents.filter { task in
            switch taskKind(task) {
            case .run: !runCompleted
            case .lift: !liftCompleted
            case .swim, .other: true
            }
        }
    }

    func remainingDetails(runCompleted: Bool, liftCompleted: Bool) -> [String] {
        details.filter { detail in
            switch instructionKind(detail) {
            case .run: !runCompleted
            case .lift: !liftCompleted
            case .swim, .other: true
            }
        }
    }

    func shortTaskName(_ task: String) -> String {
        switch taskKind(task) {
        case .run: "run"
        case .lift: "lift"
        case .swim: "swim"
        case .other: task
        }
    }

    private var taskComponents: [String] {
        text.components(separatedBy: " + ")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func taskKind(_ task: String) -> PlanInstructionKind {
        let value = task.lowercased()
        if value.contains("run") { return .run }
        if value.contains("body lift") { return .lift }
        if value.contains("swim") { return .swim }
        return .other
    }

    /// The coach publishes an allowlisted sentence vocabulary, but it is still a
    /// string boundary. Classify only known prefixes and preserve unknown copy as
    /// `.other`; hiding a new instruction is worse than briefly showing too much.
    private func instructionKind(_ detail: String) -> PlanInstructionKind {
        let value = detail.lowercased()
        let liftPrefixes = ["complete upper", "complete lower", "skip ", "emphasise ", "circuit:"]
        if liftPrefixes.contains(where: value.hasPrefix) { return .lift }

        let swimPrefixes = ["swim", "count strokes:", "breathe bilaterally"]
        if swimPrefixes.contains(where: value.hasPrefix) { return .swim }

        let runPrefixes = [
            "keep ", "this is a hard session", "target ", "run ", "route ",
            "start ", "warm up ", "cool down ", "hold ", "stop ", "optional,",
            "close ", "do ", "bring cold water", "take ", "if anything",
            "recovery day.",
        ]
        if runPrefixes.contains(where: value.hasPrefix) { return .run }
        return .other
    }
}

struct PostRunSummary: Equatable {
    let run: RunningWorkoutSummary
    let plannedMiles: Double?
    let completedWeekMiles: Double
    let prescribedWeekMiles: Double

    var distance: String { "\(formatMiles(run.miles)) mi" }

    var duration: String {
        let totalMinutes = Int((run.duration / 60).rounded())
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        return hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
    }

    var pace: String {
        guard let rawPace = run.paceSecondsPerMile else { return "—" }
        let totalSeconds = Int(rawPace.rounded())
        return "\(totalSeconds / 60):\(String(format: "%02d", totalSeconds % 60))"
    }

    var planInsight: String {
        guard let plannedMiles, plannedMiles > 0 else {
            return "This was an extra run outside today’s mileage outline."
        }
        let delta = run.miles - plannedMiles
        let tolerance = max(0.1, plannedMiles * 0.02)
        if abs(delta) <= tolerance {
            return "You matched today’s \(formatMiles(plannedMiles)) mile outline."
        }
        if delta > 0 {
            return "You ran \(formatMiles(delta)) mi beyond today’s \(formatMiles(plannedMiles)) mile outline."
        }
        return "The run is checked off at \(formatMiles(run.miles)) mi against a \(formatMiles(plannedMiles)) mile outline."
    }

    var weekProgress: Double {
        guard prescribedWeekMiles > 0 else { return 0 }
        return min(max(completedWeekMiles / prescribedWeekMiles, 0), 1)
    }

    var weekProgressLabel: String? {
        guard prescribedWeekMiles > 0 else { return nil }
        return "\(formatMiles(completedWeekMiles)) of \(formatMiles(prescribedWeekMiles)) mi"
    }

    var weekInsight: String? {
        guard prescribedWeekMiles > 0 else { return nil }
        let contribution = Int(((run.miles / prescribedWeekMiles) * 100).rounded())
        let remaining = max(prescribedWeekMiles - completedWeekMiles, 0)
        if remaining == 0 {
            return "This run supplied \(contribution)% of the weekly outline and brought the week to its mileage target."
        }
        return "This run supplied \(contribution)% of the weekly outline. \(formatMiles(remaining)) mi remain this week."
    }
}

struct PostRunDashboard: View {
    let run: RunningWorkoutSummary
    let plannedMiles: Double?
    let week: WeeklyTrainingSnapshot
    let includeWeeklyImpact: Bool
    let dayComplete: Bool

    private var summary: PostRunSummary {
        PostRunSummary(
            run: run,
            plannedMiles: plannedMiles,
            completedWeekMiles: includeWeeklyImpact ? week.completedMiles : 0,
            prescribedWeekMiles: includeWeeklyImpact ? week.prescribedMiles : 0
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.green)

                VStack(alignment: .leading, spacing: 3) {
                    Text(dayComplete ? "Day complete" : "Run complete")
                        .font(.title2.weight(.bold))
                    Text("Finished \(run.endedAt.formatted(.dateTime.hour().minute()))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 8) {
                StatTile(summary.distance, "distance", style: .plain)
                StatTile(summary.duration, "time", style: .plain)
                StatTile(summary.pace, "pace /mi", style: .plain)
            }
            .padding(.vertical, 12)
            .background(.background.opacity(0.55), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            Label(summary.planInsight, systemImage: "scope")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if let weekProgressLabel = summary.weekProgressLabel,
               let weekInsight = summary.weekInsight {
                VStack(alignment: .leading, spacing: 7) {
                    HStack {
                        Text("Weekly impact")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Text(weekProgressLabel)
                            .font(.caption.monospacedDigit().weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    ProgressView(value: summary.weekProgress)
                        .tint(TodayPalette.accent)
                    Text(weekInsight)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [TodayPalette.accent.opacity(0.16), Color.green.opacity(0.08)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 22, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(TodayPalette.accent.opacity(0.18), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("post-run-dashboard")
    }
}

struct RemainingPlanCard: View {
    let tasks: [String]
    let details: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            Label("Still on deck", systemImage: "list.bullet.clipboard")
                .font(.headline)
                .foregroundStyle(TodayPalette.warm)

            Text(title)
                .font(.title3.weight(.bold))

            if !details.isEmpty {
                VStack(alignment: .leading, spacing: 9) {
                    ForEach(details, id: \.self) { detail in
                        HStack(alignment: .top, spacing: 9) {
                            Circle()
                                .fill(TodayPalette.warm)
                                .frame(width: 5, height: 5)
                                .padding(.top, 7)
                            Text(detail)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .todayCard()
        .accessibilityIdentifier("remaining-plan-card")
    }

    private var title: String {
        let value = tasks.joined(separator: " + ")
        guard let first = value.first else { return value }
        return String(first).uppercased() + value.dropFirst()
    }
}

#Preview("Run complete + lift remaining") {
    let start = Date.now.addingTimeInterval(-2_700)
    let run = RunningWorkoutSummary(
        id: UUID(),
        startedAt: start,
        endedAt: start.addingTimeInterval(2_400),
        miles: 5.1,
        duration: 2_400
    )
    let day = WeeklyDaySnapshot(
        date: .now,
        dateKey: TodayWidgetSnapshot.dayKey(for: .now),
        dayLabel: "Sun",
        plannedRunMiles: 5,
        plannedLift: .lower,
        plannedOther: nil,
        isKeyDay: false,
        run: run,
        lift: nil,
        extraLift: nil
    )
    let week = WeeklyTrainingSnapshot(
        startDate: .now,
        endDate: .now,
        prescribedMiles: 35,
        days: [day]
    )

    ScrollView {
        VStack(spacing: 18) {
            PostRunDashboard(
                run: run,
                plannedMiles: 5,
                week: week,
                includeWeeklyImpact: true,
                dayComplete: false
            )
            RemainingPlanCard(
                tasks: ["lower body lift", "swim"],
                details: [
                    "Complete lower body lift #1 as the main lower session.",
                    "Swim 35 to 40 minutes, technique only with no hard sets.",
                ]
            )
        }
        .padding()
    }
    .background(Color(.systemGroupedBackground))
}
