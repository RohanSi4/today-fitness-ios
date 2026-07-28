import SwiftUI

struct HistoryView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject var store: TodayStore
    @ObservedObject var catalog: ExerciseCatalog

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
                    Button("Log your first weight") {
                        appState.presentedSheet = .weight
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else {
                list
            }
        }
        .navigationTitle("History")
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
            if !store.workouts.isEmpty {
                Section("Workouts") {
                    ForEach(store.workouts) { session in
                        NavigationLink {
                            WorkoutDetailView(session: session, store: store, catalog: catalog)
                        } label: {
                            WorkoutHistoryRow(session: session)
                        }
                    }
                    .onDelete { offsets in
                        let ids = offsets.compactMap { index in
                            store.workouts.indices.contains(index) ? store.workouts[index].id : nil
                        }
                        ids.forEach { store.deleteWorkout(id: $0) }
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
                    ForEach(store.weights) { entry in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.date.formatted(.dateTime.weekday(.abbreviated).month().day()))
                                    .font(.subheadline.weight(.semibold))
                                Text(entry.healthKitID == nil ? "Local entry" : "Apple Health")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("\(entry.pounds.formatted(.number.precision(.fractionLength(1)))) lb")
                                .font(.headline.monospacedDigit())
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
    }
}

private struct WorkoutHistoryRow: View {
    let session: WorkoutSession

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "dumbbell.fill")
                .foregroundStyle(TodayPalette.accent)
                .frame(width: 36, height: 36)
                .background(TodayPalette.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 3) {
                Text(session.kind.workoutTitle)
                    .font(.subheadline.weight(.semibold))
                Text(session.startedAt.formatted(.dateTime.month().day().hour().minute()))
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
