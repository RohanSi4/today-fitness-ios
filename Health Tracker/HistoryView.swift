import SwiftUI

struct HistoryView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject var store: TodayStore
    @ObservedObject var catalog: ExerciseCatalog
    @State private var pendingWorkoutDeletion: WorkoutSession?
    @State private var selectedWeightForEditing: WeightEntry?
    @State private var pendingWeightDeletion: WeightEntry?
    @State private var weightErrorMessage: String?

    private var isEmpty: Bool {
        store.workouts.isEmpty && store.weights.isEmpty && store.dataRecoveryMessage == nil
    }

    var body: some View {
        Group {
            if isEmpty {
                // The screen used to render as a lone "Weight" header with one
                // button under it, which reads as a bug rather than a new app.
                ContentUnavailableView {
                    Label("Nothing logged yet", systemImage: "clock.arrow.circlepath")
                } description: {
                    Text("Finished workouts and morning weights collect here.")
                } actions: {
                    Button("Start a workout") {
                        appState.openWorkout()
                    }
                    .buttonStyle(.borderedProminent)
                    Button("Log your first weight") {
                        appState.presentedSheet = .weight
                    }
                    .buttonStyle(.bordered)
                }
            } else {
                list
            }
        }
        .navigationTitle("History")
        .confirmationDialog(
            deletionTitle,
            isPresented: deletionConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete workout", role: .destructive) {
                guard let id = pendingWorkoutDeletion?.id else { return }
                store.deleteWorkout(id: id)
                pendingWorkoutDeletion = nil
            }
            Button("Keep workout", role: .cancel) {
                pendingWorkoutDeletion = nil
            }
        } message: {
            if let session = pendingWorkoutDeletion {
                Text("This removes \(session.completedSetCount) working sets and changes progression history.")
            }
        }
        .confirmationDialog(
            "Delete this weight?",
            isPresented: weightDeletionConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete weight", role: .destructive) {
                guard let entry = pendingWeightDeletion else { return }
                Task { await deleteWeight(entry) }
            }
            Button("Keep weight", role: .cancel) { pendingWeightDeletion = nil }
        } message: {
            if let entry = pendingWeightDeletion {
                Text("Removes \(entry.pounds.formatted(.number.precision(.fractionLength(1)))) lb from \(entry.date.formatted(.dateTime.month().day())).")
            }
        }
        .sheet(item: $selectedWeightForEditing) { entry in
            WeightLogView(store: store, entryToEdit: entry)
        }
        .alert("Could not delete weight", isPresented: weightErrorBinding) {
            Button("OK", role: .cancel) { weightErrorMessage = nil }
        } message: {
            Text(weightErrorMessage ?? "Try again.")
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Backdate weight", systemImage: "calendar.badge.plus") {
                        appState.presentedSheet = .weight
                    }
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add an entry")
            }
        }
    }

    private var list: some View {
        List {
            // Grouped by month. One flat "Workouts" section was an
            // undifferentiated scroll, so finding a session meant remembering
            // roughly how far down it was rather than when it happened.
            ForEach(workoutMonths, id: \.title) { month in
                Section(month.title) {
                    ForEach(month.sessions) { session in
                        NavigationLink {
                            WorkoutDetailView(session: session, store: store, catalog: catalog)
                        } label: {
                            WorkoutHistoryRow(session: session, regions: regionSummary(for: session))
                        }
                    }
                    .onDelete { offsets in
                        // Offsets are per-section now, so they index the month's
                        // own array — reading store.workouts here would delete
                        // the wrong session in every month but the first.
                        guard let index = offsets.first,
                              month.sessions.indices.contains(index) else { return }
                        pendingWorkoutDeletion = month.sessions[index]
                    }
                }
            }

            if let message = store.dataRecoveryMessage {
                Section {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "externaldrive.badge.checkmark")
                            .foregroundStyle(TodayPalette.warm)
                        Text(message)
                            .font(.subheadline)
                        Spacer()
                        Button("Dismiss") { store.dismissRecoveryMessage() }
                            .font(.caption.weight(.semibold))
                    }
                }
            }

            Section("Weight") {
                if store.weights.isEmpty {
                    Button("Log your first weight") {
                        appState.presentedSheet = .weight
                    }
                } else {
                    ForEach(Array(store.weights.enumerated()), id: \.element.id) { index, entry in
                        // `weights` is newest-first, so the next element is the
                        // previous morning.
                        weightRow(entry, previous: store.weights.indices.contains(index + 1)
                            ? store.weights[index + 1]
                            : nil)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func weightRow(_ entry: WeightEntry, previous: WeightEntry?) -> some View {
        let change = previous.map { entry.pounds - $0.pounds }
        HStack {
            Text(entry.date.formatted(.dateTime.weekday(.abbreviated).month().day()))
                .font(.subheadline.weight(.semibold))
            Spacer()
            // "Local entry" / "Apple Health" was plumbing — it told him where a
            // number came from, which he never needs, in the space where the
            // useful thing is which way it moved. Direction only: the app shows
            // the trend and does not editorialise about it.
            if let change, abs(change) >= 0.05 {
                Label(
                    abs(change).formatted(.number.precision(.fractionLength(1))),
                    systemImage: change < 0 ? "arrow.down" : "arrow.up"
                )
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .labelStyle(.titleAndIcon)
            }
            Text("\(entry.pounds.formatted(.number.precision(.fractionLength(1)))) lb")
                .font(.headline.monospacedDigit())
                .frame(minWidth: 74, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(weightAccessibilityLabel(entry, change: change))
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button("Delete", systemImage: "trash", role: .destructive) {
                pendingWeightDeletion = entry
            }
            Button("Edit", systemImage: "pencil") {
                selectedWeightForEditing = entry
            }
            .tint(TodayPalette.accent)
        }
        .contextMenu {
            Button("Correct weight", systemImage: "pencil") {
                selectedWeightForEditing = entry
            }
            Button("Delete weight", systemImage: "trash", role: .destructive) {
                pendingWeightDeletion = entry
            }
        }
    }

    private func weightAccessibilityLabel(_ entry: WeightEntry, change: Double?) -> String {
        let base = "\(entry.date.formatted(.dateTime.weekday(.wide).month().day())), \(entry.pounds.formatted(.number.precision(.fractionLength(1)))) pounds"
        guard let change, abs(change) >= 0.05 else { return base }
        let direction = change < 0 ? "down" : "up"
        return "\(base), \(direction) \(abs(change).formatted(.number.precision(.fractionLength(1)))) from the previous entry"
    }

    private struct WorkoutMonth {
        let title: String
        let sessions: [WorkoutSession]
    }

    private var workoutMonths: [WorkoutMonth] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: store.workouts) { session in
            calendar.date(from: calendar.dateComponents([.year, .month], from: session.startedAt)) ?? session.startedAt
        }
        return grouped.keys.sorted(by: >).map { start in
            WorkoutMonth(
                title: start.formatted(.dateTime.month(.wide).year()),
                sessions: (grouped[start] ?? []).sorted { $0.startedAt > $1.startedAt }
            )
        }
    }

    private func regionSummary(for session: WorkoutSession) -> String {
        WorkoutMuscleCoverage.regionSummary(for: session, catalog: catalog)
    }

    private var deletionConfirmation: Binding<Bool> {
        Binding(
            get: { pendingWorkoutDeletion != nil },
            set: { if !$0 { pendingWorkoutDeletion = nil } }
        )
    }

    private var deletionTitle: String {
        guard let session = pendingWorkoutDeletion else { return "Delete workout?" }
        let date = session.startedAt.formatted(.dateTime.month().day())
        return "Delete \(session.workoutTitle) from \(date)?"
    }

    private var weightDeletionConfirmation: Binding<Bool> {
        Binding(
            get: { pendingWeightDeletion != nil },
            set: { if !$0 { pendingWeightDeletion = nil } }
        )
    }

    private var weightErrorBinding: Binding<Bool> {
        Binding(
            get: { weightErrorMessage != nil },
            set: { if !$0 { weightErrorMessage = nil } }
        )
    }

    @MainActor
    private func deleteWeight(_ entry: WeightEntry) async {
        if entry.healthKitOwnedByToday == true, let sampleID = entry.healthKitID {
            do {
                try await HealthKitManager.shared.deleteBodyWeight(id: sampleID)
            } catch {
                weightErrorMessage = "Today left the entry untouched because Apple Health could not delete its copy: \(error.localizedDescription)"
                pendingWeightDeletion = nil
                return
            }
        }
        store.deleteWeight(id: entry.id)
        pendingWeightDeletion = nil
    }
}

private struct WorkoutHistoryRow: View {
    let session: WorkoutSession
    let regions: String

    private var subtitle: String {
        let day = session.startedAt.formatted(.dateTime.weekday(.abbreviated).day())
        return regions.isEmpty ? day : "\(day) · \(regions)"
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "dumbbell.fill")
                .foregroundStyle(TodayPalette.accent)
                .frame(width: 36, height: 36)
                .background(TodayPalette.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 3) {
                Text(session.workoutTitle)
                    .font(.subheadline.weight(.semibold))
                // The month is the section header, so the row only needs the day
                // — which frees the rest of the line for what was trained.
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text(session.completedSetCount == 1 ? "1 set" : "\(session.completedSetCount) sets")
                if let duration = session.durationLabel {
                    Text(duration)
                }
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
        }
    }
}

private struct WorkoutDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState
    @ObservedObject var store: TodayStore
    @ObservedObject var catalog: ExerciseCatalog
    @State private var draft: WorkoutSession
    @State private var isEditing = false
    @State private var showReopenConfirmation = false

    init(session: WorkoutSession, store: TodayStore, catalog: ExerciseCatalog) {
        self.store = store
        self.catalog = catalog
        _draft = State(initialValue: session)
    }

    private var completedAreas: [WorkoutMuscleArea] {
        let completed = WorkoutMuscleCoverage.completed(in: draft, catalog: catalog)
        return WorkoutMuscleArea.allCases.filter(completed.contains)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                HStack(spacing: 10) {
                    StatTile(draft.completedExerciseCount, "exercises")
                    StatTile(draft.completedSetCount, "sets")
                    StatTile(draft.durationLabel ?? "In progress", "time")
                }

                MuscleBreakdownCard(title: "Muscles hit", areas: completedAreas)

                if isEditing { editableExercises } else { readOnlyExercises }
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(draft.workoutTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if isEditing {
                    Button("Cancel") {
                        if let current = store.workouts.first(where: { $0.id == draft.id }) {
                            draft = current
                        }
                        isEditing = false
                    }
                    Button("Save") {
                        store.updateWorkout(draft)
                        isEditing = false
                    }
                    .fontWeight(.semibold)
                    .disabled(draft.completedSetCount == 0)
                } else {
                    Menu {
                        Button("Edit sets", systemImage: "pencil") { isEditing = true }
                        Button("Reopen workout", systemImage: "arrow.uturn.backward") {
                            showReopenConfirmation = true
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel("Workout actions")
                }
            }
        }
        .confirmationDialog(
            "Reopen this workout?",
            isPresented: $showReopenConfirmation,
            titleVisibility: .visible
        ) {
            Button("Reopen and continue") {
                if store.reopenWorkout(id: draft.id) {
                    dismiss()
                    appState.openWorkout()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(store.activeWorkout == nil
                ? "The workout returns to the active logger so you can correct or add sets."
                : "Finish or discard the active workout before reopening another one.")
        }
    }

    private var readOnlyExercises: some View {
        ForEach(draft.exercises.filter { $0.sets.contains(where: \.isPerformed) }) { logged in
            if let exercise = catalog.exercise(id: logged.exerciseID) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(exercise.name).font(.headline)
                    ForEach(Array(logged.sets.filter(\.isPerformed).enumerated()), id: \.element.id) { index, set in
                        HStack {
                            Text(set.setType == .working ? "Set \(index + 1)" : set.setType.title)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(SetSummary.text(for: set, exercise: exercise, includingUnit: true))
                                .font(.subheadline.monospacedDigit().weight(.semibold))
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .todayCard()
            }
        }
    }

    private var editableExercises: some View {
        ForEach($draft.exercises) { $logged in
            if let exercise = catalog.exercise(id: logged.exerciseID) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(exercise.name).font(.headline)
                        Spacer()
                        Button(role: .destructive) {
                            draft.exercises.removeAll { $0.id == logged.id }
                        } label: {
                            Image(systemName: "trash")
                        }
                        .accessibilityLabel("Remove \(exercise.name)")
                    }
                    ForEach($logged.sets) { $set in
                        HStack(spacing: 4) {
                            SetLogRow(
                                number: setNumber(set.id, in: logged),
                                exercise: exercise,
                                set: $set,
                                isNext: false
                            )
                            Button(role: .destructive) {
                                logged.sets.removeAll { $0.id == set.id }
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .frame(width: 36, height: 44)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Delete set")
                        }
                    }
                    Button("Add set", systemImage: "plus") { logged.addSet() }
                        .font(.subheadline.weight(.semibold))
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .todayCard()
            }
        }
    }

    private func setNumber(_ id: UUID, in exercise: LoggedExercise) -> Int {
        (exercise.sets.firstIndex(where: { $0.id == id }) ?? 0) + 1
    }
}
