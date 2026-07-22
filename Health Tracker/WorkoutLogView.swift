import SwiftUI
import UIKit

struct WorkoutLogView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: TodayStore
    @ObservedObject var catalog: ExerciseCatalog

    let kind: WorkoutKind
    @State private var draft: WorkoutSession
    @State private var showingExercisePicker = false
    @State private var showingMuscleMap = false
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
        .onDisappear {
            persistActiveWorkoutIfNeeded()
        }
    }

    private var workoutEditor: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 16) {
                        watchReminder

                        liveMuscleMap

                        ForEach($draft.exercises) { $loggedExercise in
                            if let exercise = catalog.exercise(id: loggedExercise.exerciseID) {
                                ExerciseLogCard(
                                    exercise: exercise,
                                    loggedExercise: $loggedExercise,
                                    history: store.lastPerformance(for: exercise.id),
                                    canMoveUp: draft.exercises.first?.id != loggedExercise.id,
                                    canMoveDown: draft.exercises.last?.id != loggedExercise.id,
                                    onMoveUp: {
                                        moveExercise(loggedExercise.id, by: -1)
                                    },
                                    onMoveDown: {
                                        moveExercise(loggedExercise.id, by: 1)
                                    },
                                    onRemove: {
                                        draft.exercises.removeAll { $0.id == loggedExercise.id }
                                    },
                                    onFinished: {
                                        guard let nextID = nextExerciseID(after: loggedExercise.id) else { return }
                                        withAnimation(.snappy) {
                                            proxy.scrollTo(nextID, anchor: .top)
                                        }
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
            .navigationTitle(kind.workoutTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        persistActiveWorkoutIfNeeded()
                        dismiss()
                    }
                    .accessibilityIdentifier("close-workout-button")
                }
                ToolbarItemGroup(placement: .confirmationAction) {
                    Text("\(draft.completedSetCount) sets")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Menu {
                        Button(role: .destructive) {
                            showDiscardConfirmation = true
                        } label: {
                            Label("Discard workout", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel("Workout options")
                    .accessibilityIdentifier("workout-options-menu")
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        UIApplication.shared.sendAction(
                            #selector(UIResponder.resignFirstResponder),
                            to: nil,
                            from: nil,
                            for: nil
                        )
                    }
                    .fontWeight(.semibold)
                }
            }
            .sheet(isPresented: $showingExercisePicker) {
                ExercisePickerView(
                    catalog: catalog,
                    selectedIDs: Set(draft.exercises.map(\.exerciseID)),
                    recentIDs: recentExerciseIDs
                ) { exercise in
                    draft.exercises.append(
                        LoggedExercise(
                            exerciseID: exercise.id,
                            sets: store.starterSets(for: exercise.id, catalog: catalog)
                        )
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

    private var liveMuscleMap: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.snappy) { showingMuscleMap.toggle() }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "figure.strengthtraining.traditional")
                        .font(.title3)
                        .foregroundStyle(TodayPalette.muscle)
                        .frame(width: 38, height: 38)
                        .background(TodayPalette.muscle.opacity(0.09), in: RoundedRectangle(cornerRadius: 11))

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Muscle map")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text(muscleMapStatus)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(showingMuscleMap ? 180 : 0))
                }
                .padding(14)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if showingMuscleMap {
                Divider().padding(.horizontal, 14)
                MuscleMapView(scores: store.muscleScores(for: draft, catalog: catalog), compact: true)
                    .padding(14)
                    .frame(maxWidth: .infinity)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .todayCard()
    }

    private var muscleMapStatus: String {
        let count = store.muscleScores(for: draft, catalog: catalog).filter { $0.value > 0 }.count
        if count == 0 { return "Fills in as you finish sets" }
        return count == 1 ? "1 area hit so far" : "\(count) areas hit so far"
    }

    private var recentExerciseIDs: [String] {
        var seen = Set<String>()
        return store.workouts
            .sorted { $0.startedAt > $1.startedAt }
            .flatMap(\.exercises)
            .map(\.exerciseID)
            .filter { seen.insert($0).inserted }
            .prefix(10)
            .map { $0 }
    }

    private func moveExercise(_ id: UUID, by offset: Int) {
        guard let source = draft.exercises.firstIndex(where: { $0.id == id }) else { return }
        let destination = source + offset
        guard draft.exercises.indices.contains(destination) else { return }
        withAnimation(.snappy) {
            draft.exercises.swapAt(source, destination)
        }
    }

    private func nextExerciseID(after id: UUID) -> UUID? {
        guard let index = draft.exercises.firstIndex(where: { $0.id == id }) else { return nil }
        return draft.exercises.dropFirst(index + 1).first(where: { logged in
            logged.sets.contains { !$0.isPerformed }
        })?.id
    }

    private func persistActiveWorkoutIfNeeded() {
        guard completedSession == nil, store.activeWorkout != nil else { return }
        store.updateActiveWorkout(draft)
        store.flushPersistence()
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
                            showingHistory.toggle()
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
                }
            }

            if showingDetails {
                if showingHistory {
                    PreviousPerformanceView(history: history, exercise: exercise)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }

                ForEach(Array(loggedExercise.sets.indices), id: \.self) { index in
                    SetLogRow(
                        number: index + 1,
                        exercise: exercise,
                        set: $loggedExercise.sets[index],
                        isNext: loggedExercise.sets.firstIndex(where: { !$0.isPerformed }) == index
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
            } else {
                Text(completedSummary)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(16)
        .todayCard()
        .onChange(of: isComplete) { wasComplete, nowComplete in
            guard nowComplete, !wasComplete else { return }
            withAnimation(.snappy) { showingDetails = false }
            onFinished()
        }
    }

    private var exerciseSubtitle: String {
        if let previous = history.first {
            let sets = previous.sets.filter(\.isPerformed).prefix(3).map { set in
                if exercise.loadMode == .bodyweight || set.weight == nil {
                    return "\(set.reps) reps"
                }
                return "\(set.weight!.formatted(.number.precision(.fractionLength(0...1)))) × \(set.reps)"
            }
            if !sets.isEmpty { return "Last: \(sets.joined(separator: ", "))" }
        }
        let muscles = exercise.muscles
            .sorted { $0.intensity > $1.intensity }
            .prefix(3)
            .map { $0.muscle.title }
            .joined(separator: " · ")
        return muscles.isEmpty ? exercise.equipment.capitalized : muscles
    }

    private var isComplete: Bool {
        !loggedExercise.sets.isEmpty && loggedExercise.sets.allSatisfy(\.isPerformed)
    }

    private var completedSummary: String {
        loggedExercise.sets.filter(\.isPerformed).map { set in
            if exercise.loadMode == .bodyweight || set.weight == nil {
                return "\(set.reps) reps"
            }
            return "\(set.weight!.formatted(.number.precision(.fractionLength(0...1)))) × \(set.reps)"
        }.joined(separator: "  ·  ")
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
        HStack(spacing: 4) {
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
                    fractionDigits: 0...1,
                    accessibilityName: "\(exercise.name), set \(number), weight"
                )
            } else {
                Text("Bodyweight")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }

            IntValueControl(
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
            }
            .buttonStyle(.plain)
            .disabled(!set.isComplete && set.reps == 0)
            .accessibilityLabel(
                set.isComplete
                    ? "Mark set \(number) of \(exercise.name) incomplete"
                    : "Complete set \(number) of \(exercise.name)"
            )
            .frame(width: 44, height: 44)
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
        .sensoryFeedback(.success, trigger: set.isComplete) { wasComplete, isComplete in
            !wasComplete && isComplete
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
    let accessibilityName: String

    var body: some View {
        HStack(spacing: 2) {
            Button { value = max(minimum, value - step) } label: {
                Image(systemName: "minus")
            }
            .buttonStyle(.plain)
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
            .accessibilityLabel("Decrease \(accessibilityName) by \(step.formatted())")

            VStack(spacing: 0) {
                TextField("0", value: $value, format: .number.precision(.fractionLength(fractionDigits)))
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.center)
                    .font(.headline.monospacedDigit())
                    .frame(minWidth: 42)
                    .accessibilityLabel(accessibilityName)
                Text(label)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Button { value += step } label: {
                Image(systemName: "plus")
            }
            .buttonStyle(.plain)
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
            .accessibilityLabel("Increase \(accessibilityName) by \(step.formatted())")
        }
        .frame(maxWidth: .infinity)
    }
}

private struct IntValueControl: View {
    @Binding var value: Int
    let label: String
    let accessibilityName: String

    var body: some View {
        HStack(spacing: 2) {
            Button { value = max(0, value - 1) } label: { Image(systemName: "minus") }
                .buttonStyle(.plain)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
                .accessibilityLabel("Decrease \(accessibilityName)")
            VStack(spacing: 0) {
                TextField("0", value: $value, format: .number)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.center)
                    .font(.headline.monospacedDigit())
                    .frame(minWidth: 28)
                    .accessibilityLabel(accessibilityName)
                Text(label)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
            Button { value += 1 } label: { Image(systemName: "plus") }
                .buttonStyle(.plain)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
                .accessibilityLabel("Increase \(accessibilityName)")
        }
        .frame(width: 120)
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
                    Text(entry.sets.filter(\.isPerformed).map(setText).joined(separator: ", "))
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
    let recentIDs: [String]
    let onSelect: (ExerciseDefinition) -> Void

    @State private var query = ""
    @State private var addedIDs: Set<String>

    init(
        catalog: ExerciseCatalog,
        selectedIDs: Set<String>,
        recentIDs: [String],
        onSelect: @escaping (ExerciseDefinition) -> Void
    ) {
        self.catalog = catalog
        self.selectedIDs = selectedIDs
        self.recentIDs = recentIDs
        self.onSelect = onSelect
        _addedIDs = State(initialValue: selectedIDs)
    }

    var body: some View {
        NavigationStack {
            List {
                if query.isEmpty, !recentExercises.isEmpty {
                    Section("Recent") {
                        ForEach(recentExercises) { exercise in
                            exerciseRow(exercise)
                        }
                    }
                }

                Section(query.isEmpty ? "Browse" : "Results") {
                    ForEach(searchResults) { exercise in
                        exerciseRow(exercise)
                    }
                }
            }
            .searchable(text: $query, prompt: "Search 700+ exercises")
            .navigationTitle("Add exercises")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
            .task { await catalog.refreshIfNeeded() }
        }
    }

    private var recentExercises: [ExerciseDefinition] {
        recentIDs.compactMap(catalog.exercise(id:)).filter { !selectedIDs.contains($0.id) }
    }

    private var searchResults: [ExerciseDefinition] {
        let recent = Set(recentExercises.map(\.id))
        return catalog.search(query).filter { !query.isEmpty || !recent.contains($0.id) }
    }

    private func exerciseRow(_ exercise: ExerciseDefinition) -> some View {
        Button {
            guard !addedIDs.contains(exercise.id) else { return }
            onSelect(exercise)
            addedIDs.insert(exercise.id)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: addedIDs.contains(exercise.id) ? "checkmark.circle.fill" : "plus.circle.fill")
                    .foregroundStyle(addedIDs.contains(exercise.id) ? .green : TodayPalette.accent)
                VStack(alignment: .leading, spacing: 3) {
                    Text(exercise.name).foregroundStyle(.primary)
                    Text(exercise.muscles.sorted { $0.intensity > $1.intensity }.prefix(3).map { $0.muscle.title }.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
            }
        }
        .disabled(addedIDs.contains(exercise.id))
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
                        Text(session.kind.completionTitle)
                            .font(.title2.weight(.bold))
                        Text(
                            session.completedSetCount == 1
                                ? "1 working set"
                                : "\(session.completedSetCount) working sets"
                        )
                            .foregroundStyle(.secondary)
                    }

                    HStack(spacing: 10) {
                        summaryMetric(session.exercises.filter { $0.sets.contains(where: \.isPerformed) }.count, "exercises")
                        summaryMetric(session.completedSetCount, "sets")
                        summaryMetric(durationLabel, "time")
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

    private var durationLabel: String {
        let end = session.endedAt ?? Date()
        let minutes = max(1, Int(end.timeIntervalSince(session.startedAt) / 60))
        if minutes < 60 { return "\(minutes)m" }
        return "\(minutes / 60)h \(minutes % 60)m"
    }

    private func summaryMetric(_ value: Int, _ label: String) -> some View {
        summaryMetric("\(value)", label)
    }

    private func summaryMetric(_ value: String, _ label: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.subheadline.monospacedDigit().weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .todayCard()
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
