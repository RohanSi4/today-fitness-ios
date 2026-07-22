import SwiftUI

struct TodayView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject var store: TodayStore
    @ObservedObject var planService: TrainingPlanService
    @ObservedObject var catalog: ExerciseCatalog

    private var day: TrainingPlanDay? { planService.today }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                weightPrompt
                planCard
                workoutCard
                if day?.isRestOnly == true {
                    RecoveryPreviewCard()
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 32)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Today")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await planService.refresh() }
        .task {
            async let plan: Void = planService.refresh()
            async let exercises: Void = catalog.refreshIfNeeded()
            _ = await (plan, exercises)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(Date.now.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                .font(.title2.weight(.bold))
            Text("One place for what matters today.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var weightPrompt: some View {
        Button {
            appState.presentedSheet = .weight
        } label: {
            HStack(spacing: 14) {
                Image(systemName: store.todayWeight == nil ? "scalemass.fill" : "checkmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(store.todayWeight == nil ? TodayPalette.accent : .green)
                    .frame(width: 44, height: 44)
                    .background(TodayPalette.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 13))

                VStack(alignment: .leading, spacing: 3) {
                    Text(store.todayWeight == nil ? "Log morning weight" : "Morning weight logged")
                        .font(.headline)
                    Text(store.todayWeight == nil ? "Private and saved to Apple Health" : "Done for today")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
            .padding(16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .todayCard()
        .accessibilityIdentifier("log-weight-button")
    }

    @ViewBuilder
    private var planCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("Your plan", systemImage: "figure.run")
                    .font(.headline)
                Spacer()
                if planService.isLoading {
                    ProgressView().controlSize(.small)
                }
            }

            if let day {
                Text(day.text.capitalizedFirst)
                    .font(.title3.weight(.bold))

                if !day.details.isEmpty {
                    VStack(alignment: .leading, spacing: 9) {
                        ForEach(day.details, id: \.self) { detail in
                            HStack(alignment: .top, spacing: 9) {
                                Circle()
                                    .fill(TodayPalette.accent)
                                    .frame(width: 5, height: 5)
                                    .padding(.top, 7)
                                Text(detail)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

            } else if planService.isLoading || (planService.plan == nil && planService.errorMessage == nil) {
                ProgressView("Loading today’s plan")
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else if let error = planService.errorMessage, planService.plan == nil {
                ContentUnavailableView(
                    "Plan unavailable",
                    systemImage: "wifi.slash",
                    description: Text(error)
                )
            } else {
                VStack(alignment: .leading, spacing: 5) {
                    Text(planService.errorMessage == nil ? "Nothing planned today" : "Plan could not refresh")
                        .font(.title3.weight(.bold))
                    Text(
                        planService.errorMessage == nil
                            ? "You can still start any workout below."
                            : "The saved plan does not cover today. You can still start any workout below."
                    )
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(18)
        .todayCard()
    }

    private var workoutCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Workout", systemImage: "dumbbell.fill")
                .font(.headline)

            if let active = store.activeWorkout {
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(active.kind.workoutTitle) in progress")
                        .font(.title3.weight(.bold))
                    Text("\(active.completedSetCount) sets checked off so far")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Button {
                    appState.presentedSheet = .workout(suggested: day?.workoutKind)
                } label: {
                    Label("Continue workout", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            } else {
                if let plannedKind = day?.workoutKind,
                   let completed = store.completedWorkoutToday(kind: plannedKind) {
                    Button {
                        appState.presentedSheet = .finishedWorkout(completed)
                    } label: {
                        Label("\(plannedKind.title) logged", systemImage: "checkmark.circle.fill")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.green)
                } else {
                    Text("Choose a split or start empty and add whatever you want.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Button {
                    appState.presentedSheet = .workout(suggested: day?.workoutKind)
                } label: {
                    Label("Start workout", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .accessibilityIdentifier("start-workout-button")
            }
        }
        .padding(18)
        .todayCard()
    }
}

private struct RecoveryPreviewCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Recovery day", systemImage: "moon.stars.fill")
                .font(.headline)
            Text("Your sleep and movement recap is waiting in Insights.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .todayCard()
    }
}

private extension String {
    var capitalizedFirst: String {
        guard let first else { return self }
        return String(first).uppercased() + dropFirst()
    }
}

#Preview {
    NavigationStack {
        TodayView(
            store: TodayStore(storageURL: FileManager.default.temporaryDirectory.appendingPathComponent("today-preview.json")),
            planService: TrainingPlanService(),
            catalog: ExerciseCatalog()
        )
        .environmentObject(AppState())
    }
}
