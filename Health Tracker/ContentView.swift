import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var store = TodayStore.shared
    @StateObject private var planService = TrainingPlanService.shared
    @StateObject private var catalog = ExerciseCatalog.shared
    @StateObject private var coachSync = CoachSyncService.shared
    @StateObject private var runService = RunningWorkoutService.shared
    @ObservedObject private var intentRouter = TodayIntentRouter.shared

    var body: some View {
        TabView(selection: $appState.selectedTab) {
            NavigationStack {
                TodayView(
                    store: store,
                    planService: planService,
                    catalog: catalog,
                    runService: runService
                )
            }
            .tabItem { Label(AppTab.today.title, systemImage: AppTab.today.symbol) }
            .tag(AppTab.today)

            NavigationStack {
                HistoryView(store: store, catalog: catalog)
            }
            .tabItem { Label(AppTab.history.title, systemImage: AppTab.history.symbol) }
            .tag(AppTab.history)

            NavigationStack {
                InsightsView(
                    store: store,
                    catalog: catalog,
                    coachSync: coachSync,
                    planService: planService,
                    runService: runService,
                    recapDate: appState.recapDate
                )
            }
            .tabItem { Label(AppTab.insights.title, systemImage: AppTab.insights.symbol) }
            .tag(AppTab.insights)
        }
        .tint(TodayPalette.accent)
        .sheet(item: $appState.presentedSheet) { sheet in
            switch sheet {
            case .weight:
                WeightLogView(store: store)
            case .workout(let suggested):
                WorkoutStartFlow(
                    store: store,
                    catalog: catalog,
                    suggestedKind: suggested
                )
            case .finishedWorkout(let session):
                WorkoutSummaryView(session: session, store: store, catalog: catalog)
            case .stretch(let phase):
                StretchRoutineView(initialPhase: phase)
            }
        }
        .onChange(of: intentRouter.route) { _, route in
            handleIntentRoute(route)
        }
        .task {
            handleIntentRoute(intentRouter.route)
            await runService.start()
            publishWidgetSnapshot()
            if coachSync.isConnected, coachSync.hasPendingChanges {
                await store.syncWithCoach()
            }
        }
        .onChange(of: store.weights) { _, _ in publishWidgetSnapshot() }
        .onChange(of: store.workouts) { _, _ in publishWidgetSnapshot() }
        .onChange(of: planService.plan) { _, _ in publishWidgetSnapshot() }
        .onChange(of: runService.workouts) { _, _ in publishWidgetSnapshot() }
        .onOpenURL { url in
            guard url.scheme == "today" else { return }
            switch url.host {
            case "weight": appState.openWeightLogger()
            case "workout": appState.openWorkout()
            case "stretch", "stretches", "warmup": appState.openStretches(.dynamic)
            case "cooldown": appState.openStretches(.cooldown)
            case "history": appState.selectedTab = .history
            case "week": appState.selectedTab = .insights
            default: appState.selectedTab = .today
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                store.flushPersistence()
            } else {
                Task {
                    async let runs: Void = runService.refresh()
                    async let plan: Void = planService.refresh()
                    _ = await (runs, plan)
                    publishWidgetSnapshot()
                    if coachSync.isConnected, coachSync.hasPendingChanges {
                        await store.syncWithCoach()
                    }
                }
            }
        }
    }

    private func handleIntentRoute(_ route: TodayIntentRoute?) {
        guard let route else { return }
        switch route {
        case .weight:
            appState.openWeightLogger()
        case .workout:
            appState.openWorkout()
        case .today:
            appState.selectedTab = .today
        }
        intentRouter.consume()
    }

    private func publishWidgetSnapshot() {
        TodayWidgetPublisher.publish(
            store: store,
            plan: planService.plan,
            runs: runService.workouts
        )
    }
}

enum TodayPalette {
    static let accent = Color(red: 0.16, green: 0.43, blue: 0.31)
    static let muscle = Color(red: 0.86, green: 0.16, blue: 0.18)
    static let warm = Color(red: 0.93, green: 0.43, blue: 0.18)
}

extension View {
    func todayCard() -> some View {
        background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color.primary.opacity(0.055), lineWidth: 1)
            }
    }
}
