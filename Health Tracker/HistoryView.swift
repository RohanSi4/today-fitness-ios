import SwiftUI

struct HistoryView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject var store: TodayStore
    @ObservedObject var catalog: ExerciseCatalog
    @State private var pendingWorkoutDeletion: WorkoutSession?

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

    /// What a session actually trained, so history answers "when did I last do
    /// legs" instead of only "when did I lift". Uses the same region rollup the
    /// training pulse does, and only counts a muscle the exercise really loads.
    private func regionSummary(for session: WorkoutSession) -> String {
        var load: [TrainingRegion: Double] = [:]
        for logged in session.exercises {
            guard let exercise = catalog.exercise(id: logged.exerciseID) else { continue }
            let sets = logged.sets.filter(\.isPerformed).count
            guard sets > 0 else { continue }
            for contribution in exercise.muscles where contribution.intensity >= 0.5 {
                load[TrainingRegion.region(for: contribution.muscle), default: 0] += Double(sets) * contribution.intensity
            }
        }
        // Two, not three: with the day in front of it a third region truncated
        // mid-word ("Fri 24 · Quads · Calves · Hamstri…"), and the third is the
        // least informative of the three anyway.
        return load
            .sorted { $0.value == $1.value ? $0.key.rawValue < $1.key.rawValue : $0.value > $1.value }
            .prefix(2)
            .map(\.key.rawValue)
            .joined(separator: " · ")
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
        return "Delete \(session.kind.workoutTitle) from \(date)?"
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
                Text(session.kind.workoutTitle)
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
    let session: WorkoutSession
    let store: TodayStore
    let catalog: ExerciseCatalog

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                HStack(spacing: 10) {
                    StatTile(session.completedExerciseCount, "exercises")
                    StatTile(session.completedSetCount, "sets")
                    StatTile(session.durationLabel ?? "In progress", "time")
                }

                MuscleMapView(scores: store.muscleScores(for: session, catalog: catalog), compact: true)
                    .padding(16)
                    .frame(maxWidth: .infinity)
                    .todayCard()

                ForEach(session.exercises.filter { $0.sets.contains(where: \.isPerformed) }) { logged in
                    if let exercise = catalog.exercise(id: logged.exerciseID) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(exercise.name).font(.headline)
                            ForEach(Array(logged.sets.filter(\.isPerformed).enumerated()), id: \.element.id) { index, set in
                                HStack {
                                    Text("Set \(index + 1)").foregroundStyle(.secondary)
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
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(session.kind.workoutTitle)
        .navigationBarTitleDisplayMode(.inline)
    }
}
