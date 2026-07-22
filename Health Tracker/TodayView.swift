import SwiftUI

struct TodayView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject var store: TodayStore
    @ObservedObject var planService: TrainingPlanService
    @ObservedObject var catalog: ExerciseCatalog
    @ObservedObject var runService: RunningWorkoutService
    @StateObject private var watchWorkouts = WatchWorkoutService.shared

    private var day: TrainingPlanDay? { planService.today }
    private var weeklySnapshot: WeeklyTrainingSnapshot {
        WeeklyTrainingBuilder.build(
            plan: planService.plan,
            runs: runService.workouts,
            lifts: store.workouts
        )
    }
    private var todayProgress: WeeklyDaySnapshot? { weeklySnapshot.day(for: .now) }
    private var suggestedStretchPhase: StretchPhase {
        todayProgress?.runCompleted == true ? .cooldown : .dynamic
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                weightPrompt
                planCard
                stretchesCard
                NavigationLink {
                    WeeklySnapshotView(
                        store: store,
                        planService: planService,
                        runService: runService
                    )
                } label: {
                    WeeklySnapshotCard(snapshot: weeklySnapshot)
                }
                .buttonStyle(.plain)
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

    private var stretchesCard: some View {
        Button {
            appState.presentedSheet = .stretch(phase: suggestedStretchPhase)
        } label: {
            HStack(spacing: 14) {
                Image(systemName: suggestedStretchPhase.symbol)
                    .font(.title2)
                    .foregroundStyle(TodayPalette.warm)
                    .frame(width: 44, height: 44)
                    .background(TodayPalette.warm.opacity(0.12), in: RoundedRectangle(cornerRadius: 13))

                VStack(alignment: .leading, spacing: 3) {
                    Text("Stretches")
                        .font(.headline)
                    Text(suggestedStretchPhase == .cooldown ? "Cool down after today’s run" : "Warm up before your run, cool down after")
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
        .accessibilityIdentifier("stretches-button")
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
                Text(todayProgress?.isFullyComplete == true ? "Done for the day" : day.text.capitalizedFirst)
                    .font(.title3.weight(.bold))

                if todayProgress?.isFullyComplete == true, let todayProgress {
                    Label(completionSummary(todayProgress), systemImage: "checkmark.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.green)
                } else if !day.details.isEmpty {
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

                if todayProgress?.isFullyComplete != true {
                    if let progress = todayProgress, progress.runCompleted, let run = progress.run {
                        completedRunRow(run)
                    } else if let miles = day.plannedRunMiles {
                        watchRunButton(day: day, miles: miles)
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

    private func watchRunButton(day: TrainingPlanDay, miles: Double) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Divider()
            Button {
                Task { await watchWorkouts.send(day) }
            } label: {
                HStack {
                    Label(watchButtonLabel(day: day, miles: miles), systemImage: "applewatch")
                    Spacer()
                    if watchWorkouts.state == .sending(day.date) {
                        ProgressView().controlSize(.small)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.bordered)
            .disabled(!watchWorkouts.isSupported || watchWorkouts.state == .sending(day.date))

            if !watchWorkouts.isSupported {
                Text("This turns on when a paired Apple Watch supports scheduled workouts.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if case .failed(let message) = watchWorkouts.state {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(TodayPalette.warm)
            }
        }
    }

    private func completedRunRow(_ run: RunningWorkoutSummary) -> some View {
        HStack(spacing: 9) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 2) {
                Text("Run logged")
                    .font(.subheadline.weight(.semibold))
                Text(runSummary(run))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.top, 2)
    }

    private func completionSummary(_ day: WeeklyDaySnapshot) -> String {
        var values: [String] = []
        if let run = day.run { values.append(runSummary(run)) }
        if let lift = day.lift {
            let sets = lift.completedSetCount
            values.append("\(sets) working \(sets == 1 ? "set" : "sets")")
        }
        return values.isEmpty ? "Everything is checked off" : values.joined(separator: " · ")
    }

    private func runSummary(_ run: RunningWorkoutSummary) -> String {
        let miles = run.miles.formatted(.number.precision(.fractionLength(0...2)))
        let minutes = Int((run.duration / 60).rounded())
        guard let pace = run.paceSecondsPerMile else { return "\(miles) mi in \(minutes)m" }
        let paceMinutes = Int(pace) / 60
        let paceSeconds = Int(pace) % 60
        return "\(miles) mi in \(minutes)m · \(paceMinutes):\(String(format: "%02d", paceSeconds))/mi"
    }

    private func watchButtonLabel(day: TrainingPlanDay, miles: Double) -> String {
        if watchWorkouts.state == .scheduled(day.date) { return "Run added to Apple Watch" }
        return "Add \(miles.formatted(.number.precision(.fractionLength(0...2)))) mi to Apple Watch"
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
                    Label("Resume workout", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .accessibilityIdentifier("resume-workout-button")
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
            catalog: ExerciseCatalog(),
            runService: RunningWorkoutService(healthStore: PreviewRunningWorkoutProvider())
        )
        .environmentObject(AppState())
    }
}

private struct PreviewRunningWorkoutProvider: RunningWorkoutProviding {
    let isHealthDataAvailable = false
    func requestWorkoutAuthorization() async throws {}
    func fetchRunningWorkouts(start: Date, end: Date) async throws -> [RunningWorkoutSummary] { [] }
    func startWorkoutMonitoring(onChange: @escaping @Sendable () -> Void) {}
}
