import SwiftUI

@MainActor
enum WorkoutMuscleCoverage {
    /// Keep assistance work from checking off a planned target. A pulldown can
    /// involve the biceps without replacing the curl that was programmed for them.
    static let directTargetThreshold = 0.75

    static func targets(for session: WorkoutSession, catalog: ExerciseCatalog) -> [WorkoutMuscleArea] {
        if let template = session.routineTemplate {
            return template.targetMuscles
        }

        switch session.kind {
        case .upper:
            return [.chest, .lats, .midBack, .sideDelts, .biceps, .triceps]
        case .lower, .legs:
            return [.quads, .hamstrings, .glutes, .calves, .core]
        case .push:
            return [.chest, .sideDelts, .triceps]
        case .pull:
            return [.lats, .midBack, .rearDelts, .biceps]
        case .chest:
            return [.chest]
        case .back:
            return [.lats, .midBack, .rearDelts]
        case .other:
            return areas(
                for: session.exercises.map(\.exerciseID),
                catalog: catalog
            )
        }
    }

    static func completed(in session: WorkoutSession, catalog: ExerciseCatalog) -> Set<WorkoutMuscleArea> {
        Set(directSetCounts(in: session, catalog: catalog).filter { $0.value > 0 }.map(\.key))
    }

    static func directSetCounts(
        in session: WorkoutSession,
        catalog: ExerciseCatalog
    ) -> [WorkoutMuscleArea: Int] {
        var counts: [WorkoutMuscleArea: Int] = [:]
        for logged in session.exercises {
            let workingSets = logged.sets.filter(\.isWorkingSet).count
            guard workingSets > 0 else { continue }
            guard let exercise = catalog.exercise(id: logged.exerciseID) else { continue }
            for area in areas(for: exercise) {
                counts[area, default: 0] += workingSets
            }
        }
        return counts
    }

    static func areas(for exerciseIDs: [String], catalog: ExerciseCatalog) -> [WorkoutMuscleArea] {
        let found = exerciseIDs.reduce(into: Set<WorkoutMuscleArea>()) { result, exerciseID in
            guard let exercise = catalog.exercise(id: exerciseID) else { return }
            result.formUnion(areas(for: exercise))
        }
        return WorkoutMuscleArea.allCases.filter(found.contains)
    }

    static func areas(for exercise: ExerciseDefinition) -> Set<WorkoutMuscleArea> {
        let directMuscles = exercise.muscles
            .filter { $0.intensity >= directTargetThreshold }
            .map(\.muscle)

        return Set(WorkoutMuscleArea.allCases.filter { area in
            directMuscles.contains(where: area.isTargeted)
        })
    }

    static func summary(_ areas: [WorkoutMuscleArea]) -> String {
        areas.map(\.rawValue).joined(separator: " · ")
    }
}

struct WorkoutCoverageCard: View {
    let targets: [WorkoutMuscleArea]
    let directSetCounts: [WorkoutMuscleArea: Int]

    private var completed: Set<WorkoutMuscleArea> {
        Set(directSetCounts.filter { $0.value > 0 }.map(\.key))
    }

    private var remaining: [WorkoutMuscleArea] {
        targets.filter { !completed.contains($0) }
    }

    private var completedTargetCount: Int {
        targets.filter(completed.contains).count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Coverage")
                    .font(.headline)
                Spacer()
                Text("\(completedTargetCount)/\(targets.count)")
                    .font(.subheadline.monospacedDigit().weight(.bold))
                    .foregroundStyle(remaining.isEmpty ? .green : TodayPalette.accent)
            }

            if targets.isEmpty {
                Text("Add an exercise and Today will show which muscles it directly targets.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                FlowLayout(spacing: 8) {
                    ForEach(targets) { area in
                        coverageChip(area)
                    }
                }

                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: remaining.isEmpty ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                        .foregroundStyle(remaining.isEmpty ? .green : TodayPalette.warm)
                        .accessibilityHidden(true)
                    Text(statusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .todayCard()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary)
    }

    private func coverageChip(_ area: WorkoutMuscleArea) -> some View {
        let isComplete = completed.contains(area)
        let count = directSetCounts[area] ?? 0
        return Label(
            count > 0 ? "\(area.rawValue) \(count)" : area.rawValue,
            systemImage: isComplete ? "checkmark.circle.fill" : "circle"
        )
            .font(.caption.weight(.semibold))
            .foregroundStyle(isComplete ? .green : .secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                (isComplete ? Color.green : Color.secondary).opacity(0.09),
                in: Capsule()
            )
    }

    private var statusText: String {
        if remaining.isEmpty { return "Every planned muscle area has been targeted." }
        if completedTargetCount == 0 {
            return "Shows direct working sets as you log them."
        }
        return "Still to hit: \(remaining.map(\.rawValue).joined(separator: ", "))."
    }

    private var accessibilitySummary: String {
        guard !targets.isEmpty else { return "Workout coverage has no muscle targets yet" }
        guard !remaining.isEmpty else { return "All \(targets.count) planned muscle areas targeted" }
        return "\(completedTargetCount) of \(targets.count) muscle areas targeted. Still to hit: \(remaining.map(\.rawValue).joined(separator: ", "))"
    }
}

struct MuscleBreakdownCard: View {
    let title: String
    let areas: [WorkoutMuscleArea]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)

            if areas.isEmpty {
                Text("No completed sets were mapped to a muscle area.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                FlowLayout(spacing: 8) {
                    ForEach(areas) { area in
                        Label(area.rawValue, systemImage: "checkmark.circle.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(TodayPalette.muscle)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(TodayPalette.muscle.opacity(0.09), in: Capsule())
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .todayCard()
        .accessibilityElement(children: .combine)
    }
}
