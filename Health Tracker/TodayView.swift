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
                // The session comes first. Logging a weight is a five-second
                // chore and it used to sit above the plan, so the one thing the
                // app exists to tell him was the third thing on screen and
                // "Start workout" was below three cards of scrolling.
                if store.activeWorkout != nil {
                    workoutCard
                }
                planCard
                if store.activeWorkout == nil {
                    workoutCard
                }
                quickTiles
                NavigationLink {
                    WeeklySnapshotView(
                        store: store,
                        planService: planService,
                        runService: runService
                    )
                } label: {
                    WeeklySnapshotCard(
                        snapshot: weeklySnapshot,
                        runDataIsTrustworthy: runService.hasTrustworthyRunData
                    )
                }
                .buttonStyle(.plain)
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
            Text(headerContext)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if !progressChips.isEmpty {
                HStack(spacing: 8) {
                    ForEach(progressChips, id: \.title) { chip in
                        Label(chip.title, systemImage: chip.done ? "checkmark.circle.fill" : chip.symbol)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(chip.done ? Color.green : TodayPalette.accent)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background((chip.done ? Color.green : TodayPalette.accent).opacity(0.12), in: Capsule())
                    }
                }
                .padding(.top, 4)
                .accessibilityElement(children: .combine)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// What today asks for and whether it is done, readable without scrolling.
    /// The weekly card already knew all of this but sat below three other cards.
    private var progressChips: [(title: String, symbol: String, done: Bool)] {
        var chips: [(String, String, Bool)] = []
        if let miles = day?.plannedRunMiles {
            chips.append(("\(formatMiles(miles)) mi", "figure.run", todayProgress?.runCompleted == true))
        }
        if let kind = day?.workoutKind {
            chips.append((kind.title, "dumbbell.fill", todayProgress?.liftCompleted == true))
        }
        return chips
    }

    private var headerContext: String {
        if let active = store.activeWorkout {
            return "\(active.routineTemplate?.title ?? active.kind.title) in progress"
        }
        if day?.isRestOnly == true {
            return "Recovery day · keep movement easy"
        }
        // Name what is still owed. The old fallback ("Your plan, training, and
        // recovery context") fired on every run-only day — which is most days —
        // and told him nothing he could act on.
        var remaining: [String] = []
        if day?.plannedRunMiles != nil, todayProgress?.runCompleted != true { remaining.append("run") }
        if day?.workoutKind != nil, todayProgress?.liftCompleted != true { remaining.append("lift") }
        if !remaining.isEmpty {
            return "\(remaining.joined(separator: " and ")) still to do".capitalizedFirst
        }
        return day == nil ? "Nothing planned · start any workout below" : "Everything is checked off"
    }

    /// Weight and stretches are both one-tap side errands, and each was taking a
    /// full-width card with a headline and a subtitle — together roughly a third
    /// of the first screen. Two-up tiles keep them one tap away while making it
    /// obvious they are not the session.
    private var quickTiles: some View {
        HStack(spacing: 12) {
            quickTile(
                title: store.todayWeight == nil ? "Log weight" : "Weight logged",
                subtitle: store.todayWeight == nil ? "Morning · private" : "Done for today",
                symbol: store.todayWeight == nil ? "scalemass.fill" : "checkmark.circle.fill",
                tint: store.todayWeight == nil ? TodayPalette.accent : .green,
                identifier: "log-weight-button"
            ) {
                appState.presentedSheet = .weight
            }

            quickTile(
                title: "Stretches",
                subtitle: suggestedStretchPhase == .cooldown ? "Cool down" : "Warm up",
                symbol: suggestedStretchPhase.symbol,
                tint: TodayPalette.warm,
                identifier: "stretches-button"
            ) {
                appState.presentedSheet = .stretch(phase: suggestedStretchPhase)
            }
        }
    }

    private func quickTile(
        title: String,
        subtitle: String,
        symbol: String,
        tint: Color,
        identifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: symbol)
                    .font(.title3)
                    .foregroundStyle(tint)
                    .frame(width: 38, height: 38)
                    .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .todayCard()
        .accessibilityIdentifier(identifier)
        .accessibilityLabel("\(title). \(subtitle)")
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
        let miles = formatMiles(run.miles)
        let minutes = Int((run.duration / 60).rounded())
        guard let pace = run.paceSecondsPerMile else { return "\(miles) mi in \(minutes)m" }
        let paceMinutes = Int(pace) / 60
        let paceSeconds = Int(pace) % 60
        return "\(miles) mi in \(minutes)m · \(paceMinutes):\(String(format: "%02d", paceSeconds))/mi"
    }

    private func watchButtonLabel(day: TrainingPlanDay, miles: Double) -> String {
        if watchWorkouts.state == .scheduled(day.date) { return "Run added to Apple Watch" }
        return "Add \(formatMiles(miles)) mi to Apple Watch"
    }

    private var workoutCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Workout", systemImage: "dumbbell.fill")
                .font(.headline)

            if let active = store.activeWorkout {
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(active.workoutTitle) in progress")
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
