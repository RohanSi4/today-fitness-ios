import SwiftUI

struct HistoryView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject var store: TodayStore
    @ObservedObject var catalog: ExerciseCatalog

    var body: some View {
        List {
            if !store.workouts.isEmpty {
                Section("Workouts") {
                    ForEach(store.workouts) { session in
                        NavigationLink {
                            WorkoutDetailView(session: session, store: store, catalog: catalog)
                        } label: {
                            WorkoutHistoryRow(session: session, store: store, catalog: catalog)
                        }
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
                    }
                }
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
            }
        }
    }
}

private struct WorkoutHistoryRow: View {
    let session: WorkoutSession
    let store: TodayStore
    let catalog: ExerciseCatalog

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
            Text(session.completedSetCount == 1 ? "1 set" : "\(session.completedSetCount) sets")
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
                MuscleMapView(scores: store.muscleScores(for: session, catalog: catalog), compact: true)
                    .padding(16)
                    .frame(maxWidth: .infinity)
                    .todayCard()

                ForEach(session.exercises.filter { $0.sets.contains(where: \.isComplete) }) { logged in
                    if let exercise = catalog.exercise(id: logged.exerciseID) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(exercise.name).font(.headline)
                            ForEach(Array(logged.sets.filter(\.isComplete).enumerated()), id: \.element.id) { index, set in
                                HStack {
                                    Text("Set \(index + 1)").foregroundStyle(.secondary)
                                    Spacer()
                                    Text(setText(set, exercise: exercise))
                                        .font(.subheadline.monospacedDigit().weight(.semibold))
                                }
                            }
                        }
                        .padding(16)
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

    private func setText(_ set: LoggedSet, exercise: ExerciseDefinition) -> String {
        if exercise.loadMode == .bodyweight || set.weight == nil {
            return "\(set.reps) reps"
        }
        return "\(set.weight!.formatted(.number.precision(.fractionLength(0...1)))) lb × \(set.reps)"
    }
}
