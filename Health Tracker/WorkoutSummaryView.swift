import SwiftUI

struct WorkoutSummaryView: View {
    @Environment(\.dismiss) private var dismiss
    let session: WorkoutSession
    @ObservedObject var store: TodayStore
    @ObservedObject var catalog: ExerciseCatalog
    let onReopen: (() -> Void)?
    @State private var showUndoConfirmation = false

    init(
        session: WorkoutSession,
        store: TodayStore,
        catalog: ExerciseCatalog,
        onReopen: (() -> Void)? = nil
    ) {
        self.session = session
        self.store = store
        self.catalog = catalog
        self.onReopen = onReopen
    }

    private var completedAreas: [WorkoutMuscleArea] {
        let completed = WorkoutMuscleCoverage.completed(in: session, catalog: catalog)
        return WorkoutMuscleArea.allCases.filter(completed.contains)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    completionHeader

                    HStack(spacing: 10) {
                        StatTile(session.completedExerciseCount, "exercises")
                        StatTile(session.completedSetCount, "sets")
                        StatTile(session.durationLabel ?? "In progress", "time")
                    }

                    MuscleBreakdownCard(title: "Muscles hit", areas: completedAreas)

                    highlights
                    exerciseProgress

                    Button("Undo finish and reopen", systemImage: "arrow.uturn.backward") {
                        showUndoConfirmation = true
                    }
                    .buttonStyle(.bordered)
                    .disabled(store.activeWorkout != nil)

                    Text("Exercise details and weights stay private. The public site only needs to know that the lift happened.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(16)
                .padding(.bottom, 24)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Workout recap")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .confirmationDialog(
                "Reopen this workout?",
                isPresented: $showUndoConfirmation,
                titleVisibility: .visible
            ) {
                Button("Reopen workout") {
                    if store.undoFinishedWorkout(id: session.id) {
                        if let onReopen {
                            onReopen()
                        } else {
                            dismiss()
                        }
                    }
                }
                Button("Keep finished", role: .cancel) {}
            } message: {
                Text("The workout returns to the active logger with every set intact.")
            }
        }
    }

    private var completionHeader: some View {
        VStack(spacing: 6) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)
                .accessibilityHidden(true)
            Text(session.completionTitle)
                .font(.title2.weight(.bold))
                .multilineTextAlignment(.center)
            Text(
                session.completedSetCount == 1
                    ? "1 working set"
                    : "\(session.completedSetCount) working sets"
            )
            .foregroundStyle(.secondary)
        }
    }

    private var highlights: some View {
        HStack(spacing: 10) {
            StatTile(personalRecordCount, "PRs")
            StatTile(improvedExerciseCount, "improved")
            StatTile(session.exercises.flatMap(\.sets).filter { $0.setType == .warmup && $0.isPerformed }.count, "warm-ups")
        }
    }

    private var exerciseProgress: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Progress and next targets")
                .font(.headline)
            ForEach(session.exercises.filter { $0.sets.contains(where: \.isWorkingSet) }) { logged in
                if let exercise = catalog.exercise(id: logged.exerciseID) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(exercise.name)
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            Text(bestSetLabel(for: logged, exercise: exercise))
                                .font(.caption.monospacedDigit().weight(.semibold))
                        }
                        Text(progressNote(for: logged, exercise: exercise))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if logged.id != session.exercises.filter({ $0.sets.contains(where: \.isWorkingSet) }).last?.id {
                        Divider()
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .todayCard()
    }

    private var earlierWorkouts: [WorkoutSession] {
        store.workouts.filter { $0.id != session.id && $0.startedAt < session.startedAt }
    }

    private func priorPerformances(for exerciseID: String) -> [LoggedExercise] {
        earlierWorkouts.compactMap { workout in
            workout.exercises.first { $0.exerciseID == exerciseID && $0.sets.contains(where: \.isWorkingSet) }
        }
    }

    private var personalRecordCount: Int {
        session.exercises.reduce(0) { total, logged in
            guard let exercise = catalog.exercise(id: logged.exerciseID),
                  let current = bestEstimate(logged, exercise: exercise) else { return total }
            let previous = priorPerformances(for: logged.exerciseID)
                .compactMap { bestEstimate($0, exercise: exercise) }
                .max() ?? -.infinity
            return total + (current > previous ? 1 : 0)
        }
    }

    private var improvedExerciseCount: Int {
        session.exercises.reduce(0) { total, logged in
            guard let previous = priorPerformances(for: logged.exerciseID).first else { return total }
            let currentReps = logged.sets.filter(\.isWorkingSet).reduce(0) { $0 + $1.reps }
            let previousReps = previous.sets.filter(\.isWorkingSet).reduce(0) { $0 + $1.reps }
            return total + (currentReps > previousReps ? 1 : 0)
        }
    }

    private func bestEstimate(_ logged: LoggedExercise, exercise: ExerciseDefinition) -> Double? {
        logged.sets.filter(\.isProgressionSet).map { set in
            let load = set.weight ?? 0
            return load > 0 ? load * (1 + Double(set.reps) / 30) : Double(set.reps)
        }.max()
    }

    private func bestSetLabel(for logged: LoggedExercise, exercise: ExerciseDefinition) -> String {
        let sets = logged.sets.filter(\.isProgressionSet)
        guard let best = sets.max(by: { lhs, rhs in
            let left = (lhs.weight ?? 0) * (1 + Double(lhs.reps) / 30)
            let right = (rhs.weight ?? 0) * (1 + Double(rhs.reps) / 30)
            return left < right
        }) else { return "" }
        return SetSummary.text(for: best, exercise: exercise, includingUnit: false)
    }

    private func progressNote(for logged: LoggedExercise, exercise: ExerciseDefinition) -> String {
        let previous = priorPerformances(for: logged.exerciseID)
        let currentReps = logged.sets.filter(\.isWorkingSet).reduce(0) { $0 + $1.reps }
        let comparison: String
        if let prior = previous.first {
            let priorReps = prior.sets.filter(\.isWorkingSet).reduce(0) { $0 + $1.reps }
            let delta = currentReps - priorReps
            comparison = delta == 0 ? "Matched last session's total reps." : "\(abs(delta)) total reps \(delta > 0 ? "above" : "below") last session."
        } else {
            comparison = "First comparable session recorded."
        }

        guard let last = logged.sets.last(where: \.isWorkingSet) else { return comparison }
        var seed = last
        seed.isComplete = false
        seed.completedAt = nil
        let next = LoggedExercise(exerciseID: logged.exerciseID, sets: [seed])
        guard let target = HypertrophyProgramming.nextSetTarget(
            current: next,
            history: [logged] + previous,
            exercise: exercise
        ) else { return comparison }
        let load = target.weight.map { "\($0.formatted(.number.precision(.fractionLength(0...1)))) lb × " } ?? ""
        return "\(comparison) Next: \(load)\(target.reps) reps."
    }

}

/// Wraps its subviews onto as many lines as they need. Used for the muscle chips.
struct FlowLayout: Layout {
    let spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 0
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
