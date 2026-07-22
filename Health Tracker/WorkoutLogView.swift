import SwiftUI

struct WorkoutLogView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: TodayStore
    @ObservedObject var catalog: ExerciseCatalog

    let kind: WorkoutKind
    @State private var draft: WorkoutSession
    @State private var showingExercisePicker = false
    @State private var completedSession: WorkoutSession?
    @State private var showDiscardConfirmation = false

    init(store: TodayStore, catalog: ExerciseCatalog, kind: WorkoutKind) {
        self.store = store
        self.catalog = catalog
        self.kind = kind
        _draft = State(initialValue: store.activeWorkout ?? WorkoutSession(
            kind: kind,
            startedAt: Date(),
            endedAt: nil,
            exercises: []
        ))
    }

    var body: some View {
        Group {
            if let completedSession {
                WorkoutSummaryView(session: completedSession, store: store, catalog: catalog)
            } else {
                workoutEditor
            }
        }
        .interactiveDismissDisabled(completedSession == nil)
    }

    private var workoutEditor: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 16) {
                        watchReminder

                        MuscleMapView(scores: store.muscleScores(for: draft, catalog: catalog), compact: true)
                            .padding(14)
                            .frame(maxWidth: .infinity)
                            .todayCard()

                        ForEach($draft.exercises) { $loggedExercise in
                            if let exercise = catalog.exercise(id: loggedExercise.exerciseID) {
                                ExerciseLogCard(
                                    exercise: exercise,
                                    loggedExercise: $loggedExercise,
                                    history: store.lastPerformance(for: exercise.id),
                                    onRemove: {
                                        draft.exercises.removeAll { $0.id == loggedExercise.id }
                                    }
                                )
                                .id(loggedExercise.id)
                            }
                        }

                        Button {
                            showingExercisePicker = true
                        } label: {
                            Label("Add exercise", systemImage: "plus.circle.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)

                        Button {
                            store.updateActiveWorkout(draft)
                            completedSession = store.finishActiveWorkout()
                        } label: {
                            Text("Finish workout").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(draft.completedSetCount == 0)
                        .padding(.top, 6)
                    }
                    .padding(16)
                    .padding(.bottom, 24)
                }
                .background(Color(.systemGroupedBackground))
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle("\(kind.title) workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Discard", role: .destructive) {
                        showDiscardConfirmation = true
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Text("\(draft.completedSetCount) sets")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .sheet(isPresented: $showingExercisePicker) {
                ExercisePickerView(catalog: catalog, selectedIDs: Set(draft.exercises.map(\.exerciseID))) { exercise in
                    draft.exercises.append(
                        LoggedExercise(exerciseID: exercise.id, sets: catalog.defaultSets(for: exercise.id))
                    )
                }
            }
            .confirmationDialog(
                "Discard this workout?",
                isPresented: $showDiscardConfirmation,
                titleVisibility: .visible
            ) {
                Button("Discard workout", role: .destructive) {
                    store.discardActiveWorkout()
                    dismiss()
                }
                Button("Keep workout", role: .cancel) {}
            }
            .onChange(of: draft) { _, updated in
                store.updateActiveWorkout(updated)
            }
        }
    }

    private var watchReminder: some View {
        HStack(spacing: 12) {
            Image(systemName: "applewatch")
                .font(.title2)
                .foregroundStyle(TodayPalette.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text("Start Strength Training on your Watch")
                    .font(.subheadline.weight(.semibold))
                Text("Today tracks your sets. Your Watch and HealthFit still own the workout.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(TodayPalette.accent.opacity(0.09), in: RoundedRectangle(cornerRadius: 18))
    }
}

private struct ExerciseLogCard: View {
    let exercise: ExerciseDefinition
    @Binding var loggedExercise: LoggedExercise
    let history: [LoggedExercise]
    let onRemove: () -> Void

    @State private var showingHistory = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(exercise.name)
                        .font(.headline)
                    Text(exerciseSubtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Menu {
                    if !history.isEmpty {
                        Button("Last three sessions", systemImage: "clock.arrow.circlepath") {
                            showingHistory.toggle()
                        }
                    }
                    Button("Remove exercise", systemImage: "trash", role: .destructive, action: onRemove)
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
            }

            if showingHistory {
                PreviousPerformanceView(history: history, exercise: exercise)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            ForEach(Array(loggedExercise.sets.indices), id: \.self) { index in
                SetLogRow(
                    number: index + 1,
                    exercise: exercise,
                    set: $loggedExercise.sets[index],
                    isNext: loggedExercise.sets.firstIndex(where: { !$0.isComplete }) == index
                )
            }

            HStack {
                Button {
                    withAnimation(.snappy) {
                        loggedExercise.removeOneSet()
                    }
                } label: {
                    Label("Remove set", systemImage: "minus")
                }
                .disabled(loggedExercise.sets.count <= 1)
                .accessibilityLabel("Remove one set from \(exercise.name)")

                Spacer()

                Text(loggedExercise.sets.count == 1 ? "1 set" : "\(loggedExercise.sets.count) sets")
                    .foregroundStyle(.secondary)

                Spacer()

                Button {
                    withAnimation(.snappy) {
                        loggedExercise.addSet()
                    }
                } label: {
                    Label("Add set", systemImage: "plus")
                }
                .accessibilityLabel("Add one set to \(exercise.name)")
            }
            .buttonStyle(.plain)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(TodayPalette.accent)
        }
        .padding(16)
        .todayCard()
    }

    private var exerciseSubtitle: String {
        let muscles = exercise.muscles
            .sorted { $0.intensity > $1.intensity }
            .prefix(3)
            .map { $0.muscle.title }
            .joined(separator: " · ")
        return muscles.isEmpty ? exercise.equipment.capitalized : muscles
    }
}

private struct SetLogRow: View {
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
        HStack(spacing: 10) {
            Text("\(number)")
                .font(.subheadline.monospacedDigit().weight(.bold))
                .foregroundStyle(.secondary)
                .frame(width: 22)

            if exercise.loadMode != .bodyweight {
                ValueControl(
                    value: weightBinding,
                    step: exercise.weightIncrement,
                    minimum: 0,
                    label: exercise.loadMode.shortLabel,
                    fractionDigits: 0...1
                )
            } else {
                Text("Bodyweight")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }

            IntValueControl(value: $set.reps, label: repLabel)

            Button {
                withAnimation(.snappy) { set.isComplete.toggle() }
            } label: {
                Image(systemName: set.isComplete ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(set.isComplete ? .green : .secondary)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(set.isComplete ? "Mark set incomplete" : "Complete set")
        }
        .padding(10)
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
    }

    private var repLabel: String {
        exercise.name.localizedCaseInsensitiveContains("single-arm") ? "each" : "reps"
    }
}

private struct ValueControl: View {
    @Binding var value: Double
    let step: Double
    let minimum: Double
    let label: String
    let fractionDigits: ClosedRange<Int>

    var body: some View {
        HStack(spacing: 5) {
            Button { value = max(minimum, value - step) } label: {
                Image(systemName: "minus")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Decrease weight by \(step.formatted())")

            VStack(spacing: 0) {
                TextField("0", value: $value, format: .number.precision(.fractionLength(fractionDigits)))
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.center)
                    .font(.headline.monospacedDigit())
                    .frame(minWidth: 42)
                Text(label)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Button { value += step } label: {
                Image(systemName: "plus")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Increase weight by \(step.formatted())")
        }
        .frame(maxWidth: .infinity)
    }
}

private struct IntValueControl: View {
    @Binding var value: Int
    let label: String

    var body: some View {
        HStack(spacing: 5) {
            Button { value = max(0, value - 1) } label: { Image(systemName: "minus") }
                .buttonStyle(.plain)
                .accessibilityLabel("Decrease reps")
            VStack(spacing: 0) {
                TextField("0", value: $value, format: .number)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.center)
                    .font(.headline.monospacedDigit())
                    .frame(minWidth: 28)
                Text(label)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
            Button { value += 1 } label: { Image(systemName: "plus") }
                .buttonStyle(.plain)
                .accessibilityLabel("Increase reps")
        }
        .frame(width: 82)
    }
}

private struct PreviousPerformanceView: View {
    let history: [LoggedExercise]
    let exercise: ExerciseDefinition

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(history.prefix(3).enumerated()), id: \.offset) { index, entry in
                HStack {
                    Text(index == 0 ? "Last" : "\(index + 1) back")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(entry.sets.filter(\.isComplete).map(setText).joined(separator: ", "))
                        .font(.caption.monospacedDigit().weight(.semibold))
                }
                .font(.caption)
            }
        }
        .padding(10)
        .background(TodayPalette.accent.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
    }

    private func setText(_ set: LoggedSet) -> String {
        if exercise.loadMode == .bodyweight || set.weight == nil {
            return "\(set.reps) reps"
        }
        return "\(set.weight!.formatted(.number.precision(.fractionLength(0...1)))) × \(set.reps)"
    }
}

private struct ExercisePickerView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var catalog: ExerciseCatalog
    let selectedIDs: Set<String>
    let onSelect: (ExerciseDefinition) -> Void

    @State private var query = ""

    var body: some View {
        NavigationStack {
            List(catalog.search(query)) { exercise in
                Button {
                    onSelect(exercise)
                    dismiss()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: selectedIDs.contains(exercise.id) ? "checkmark.circle.fill" : "dumbbell.fill")
                            .foregroundStyle(selectedIDs.contains(exercise.id) ? .green : TodayPalette.accent)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(exercise.name).foregroundStyle(.primary)
                            Text(exercise.muscles.sorted { $0.intensity > $1.intensity }.prefix(3).map { $0.muscle.title }.joined(separator: " · "))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
                .disabled(selectedIDs.contains(exercise.id))
            }
            .searchable(text: $query, prompt: "Search 700+ exercises")
            .navigationTitle("Add exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .task { await catalog.refreshIfNeeded() }
        }
    }
}

struct WorkoutSummaryView: View {
    @Environment(\.dismiss) private var dismiss
    let session: WorkoutSession
    @ObservedObject var store: TodayStore
    @ObservedObject var catalog: ExerciseCatalog

    private var scores: [MuscleGroup: Double] {
        store.muscleScores(for: session, catalog: catalog)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    VStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(.green)
                        Text("\(session.kind.title) complete")
                            .font(.title2.weight(.bold))
                        Text(
                            session.completedSetCount == 1
                                ? "1 working set"
                                : "\(session.completedSetCount) working sets"
                        )
                            .foregroundStyle(.secondary)
                    }

                    MuscleMapView(scores: scores)
                        .padding(18)
                        .frame(maxWidth: .infinity)
                        .todayCard()

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Muscles hit")
                            .font(.headline)
                        FlowLayout(spacing: 8) {
                            ForEach(scores.filter { $0.value > 0 }.sorted { $0.value > $1.value }, id: \.key) { muscle, value in
                                Text(muscle.title)
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 7)
                                    .background(TodayPalette.muscle.opacity(min(0.22, 0.08 + value / 30)), in: Capsule())
                            }
                        }
                    }
                    .padding(18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .todayCard()

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
        }
    }
}

private struct FlowLayout: Layout {
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
