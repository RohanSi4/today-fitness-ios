import SwiftUI

/// One exercise inside an in-progress workout: its sets, its history, and the
/// controls for reordering or dropping it.
struct ExerciseLogCard: View {
    let exercise: ExerciseDefinition
    @Binding var loggedExercise: LoggedExercise
    let history: [LoggedExercise]
    let canMoveUp: Bool
    let canMoveDown: Bool
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onRemove: () -> Void
    let onFinished: () -> Void

    @State private var showingHistory = false
    @State private var showingDetails = true

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            if showingDetails {
                if showingHistory {
                    PreviousPerformanceView(history: history, exercise: exercise)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }

                setRows
                setCountControls
            } else {
                collapsedSummary
            }
        }
        .padding(16)
        .todayCard()
        .onChange(of: isComplete) { wasComplete, nowComplete in
            guard wasComplete != nowComplete else { return }
            if nowComplete {
                withAnimation(.snappy) { showingDetails = false }
                onFinished()
            } else {
                // Unchecking a set used to leave the card collapsed showing a
                // summary of work that was no longer logged.
                withAnimation(.snappy) { showingDetails = true }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text(exercise.name)
                    .font(.headline)
                Text(exerciseSubtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if isComplete, !showingDetails {
                Button("Edit") {
                    withAnimation(.snappy) { showingDetails = true }
                }
                .font(.caption.weight(.semibold))
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            Menu {
                if !history.isEmpty {
                    Button("Last three sessions", systemImage: "clock.arrow.circlepath") {
                        withAnimation(.snappy) { showingHistory.toggle() }
                    }
                }
                Button("Move up", systemImage: "arrow.up", action: onMoveUp)
                    .disabled(!canMoveUp)
                Button("Move down", systemImage: "arrow.down", action: onMoveDown)
                    .disabled(!canMoveDown)
                Divider()
                Button("Remove exercise", systemImage: "trash", role: .destructive, action: onRemove)
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("\(exercise.name) options")
        }
    }

    // Identity, not position. Indexing a `ForEach` by `\.self` over
    // `sets.indices` while `$loggedExercise.sets[index]` is still bound means a
    // removed set can be read at a stale index, and every add or remove
    // reshuffles rows instead of animating one in or out.
    private var setRows: some View {
        ForEach($loggedExercise.sets) { $set in
            SetLogRow(
                number: setNumber(for: set),
                exercise: exercise,
                set: $set,
                isNext: nextSetID == set.id
            )
        }
    }

    private var setCountControls: some View {
        HStack {
            Button {
                withAnimation(.snappy) { loggedExercise.removeOneSet() }
            } label: {
                Label("Remove set", systemImage: "minus")
            }
            .disabled(loggedExercise.sets.count <= 1)
            .accessibilityLabel("Remove one set from \(exercise.name)")

            Spacer()

            Text(loggedExercise.sets.count == 1 ? "1 set" : "\(loggedExercise.sets.count) sets")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            Spacer()

            Button {
                withAnimation(.snappy) { loggedExercise.addSet() }
            } label: {
                Label("Add set", systemImage: "plus")
            }
            .accessibilityLabel("Add one set to \(exercise.name)")
        }
        .buttonStyle(.plain)
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(TodayPalette.accent)
    }

    /// The collapsed state used to be dead text: the only way back was the small
    /// Edit button in the corner, which is easy to miss mid-set.
    private var collapsedSummary: some View {
        Button {
            withAnimation(.snappy) { showingDetails = true }
        } label: {
            HStack {
                Text(completedSummary)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(exercise.name) logged, \(completedSummary). Reopen to edit.")
    }

    private func setNumber(for set: LoggedSet) -> Int {
        (loggedExercise.sets.firstIndex(where: { $0.id == set.id }) ?? 0) + 1
    }

    private var nextSetID: UUID? {
        loggedExercise.sets.first { !$0.isPerformed }?.id
    }

    private var exerciseSubtitle: String {
        if let previous = history.first {
            let sets = SetSummary.performedText(for: previous.sets, exercise: exercise, limit: 3)
            if !sets.isEmpty { return "Last: \(sets)" }
        }
        let muscles = exercise.muscles
            .sorted { $0.intensity > $1.intensity }
            .prefix(3)
            .map(\.muscle.title)
            .joined(separator: " · ")
        return muscles.isEmpty ? exercise.equipment.capitalized : muscles
    }

    private var isComplete: Bool {
        !loggedExercise.sets.isEmpty && loggedExercise.sets.allSatisfy(\.isPerformed)
    }

    private var completedSummary: String {
        SetSummary.performedText(
            for: loggedExercise.sets,
            exercise: exercise,
            separator: "  ·  "
        )
    }
}

struct SetLogRow: View {
    let number: Int
    let exercise: ExerciseDefinition
    @Binding var set: LoggedSet
    let isNext: Bool

    private var weightBinding: Binding<Double> {
        Binding(
            get: { set.weight ?? 0 },
            set: { set.weight = max(0, $0) }
        )
    }

    var body: some View {
        HStack(spacing: 4) {
            Text("\(number)")
                .font(.subheadline.monospacedDigit().weight(.bold))
                .foregroundStyle(.secondary)
                .frame(width: 22)
                .accessibilityHidden(true)

            if exercise.loadMode != .bodyweight {
                ValueStepper(
                    value: weightBinding,
                    step: exercise.weightIncrement,
                    minimum: 0,
                    label: exercise.loadMode.shortLabel,
                    fractionDigits: 0...1,
                    accessibilityName: "\(exercise.name), set \(number), weight"
                )
            } else {
                Text("Bodyweight")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity)
            }

            IntValueStepper(
                value: $set.reps,
                label: repLabel,
                accessibilityName: "\(exercise.name), set \(number), reps"
            )

            Button {
                withAnimation(.snappy) { set.isComplete.toggle() }
            } label: {
                Image(systemName: set.isComplete ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(set.isComplete ? .green : .secondary)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!set.isComplete && set.reps == 0)
            .accessibilityLabel(
                set.isComplete
                    ? "Mark set \(number) of \(exercise.name) incomplete"
                    : "Complete set \(number) of \(exercise.name)"
            )
        }
        .padding(10)
        // Six controls on one line cannot also honour the accessibility text
        // sizes; past this point the row wraps into unusable overlap. Everything
        // outside the set row still scales the whole way.
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .background(
            set.isComplete ? Color.green.opacity(0.075) : Color(.tertiarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 15)
        )
        .overlay {
            if isNext {
                RoundedRectangle(cornerRadius: 15)
                    .stroke(TodayPalette.accent.opacity(0.5), lineWidth: 1.5)
            }
        }
        .sensoryFeedback(.success, trigger: set.isComplete) { wasComplete, isComplete in
            !wasComplete && isComplete
        }
    }

    private var repLabel: String {
        exercise.name.localizedCaseInsensitiveContains("single-arm") ? "each" : "reps"
    }
}

struct PreviousPerformanceView: View {
    let history: [LoggedExercise]
    let exercise: ExerciseDefinition

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(history.prefix(3).enumerated()), id: \.offset) { index, entry in
                HStack {
                    Text(index == 0 ? "Last" : "\(index + 1) back")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(SetSummary.performedText(for: entry.sets, exercise: exercise))
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .multilineTextAlignment(.trailing)
                }
                .font(.caption)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(TodayPalette.accent.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
    }
}
