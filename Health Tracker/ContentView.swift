import SwiftUI
import UIKit

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
                // If a background launch happened while the phone was locked, the
                // store came up empty and refused to write. Now that we are
                // foreground the device is unlocked, so the real data can load.
                store.reloadIfUnreadable()
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
    /// These were fixed sRGB values, which meant the deep green accent sat at
    /// roughly the same luminance as the dark-mode card it is drawn on: buttons,
    /// the tab bar tint and the weight trend line all but disappeared at night,
    /// which is when a gym session actually gets logged. Each colour now carries
    /// a lighter variant for dark mode.
    static let accent = adaptive(
        light: (red: 0.16, green: 0.43, blue: 0.31),
        dark: (red: 0.36, green: 0.76, blue: 0.55)
    )
    static let muscle = adaptive(
        light: (red: 0.86, green: 0.16, blue: 0.18),
        dark: (red: 0.98, green: 0.42, blue: 0.42)
    )
    static let warm = adaptive(
        light: (red: 0.93, green: 0.43, blue: 0.18),
        dark: (red: 1.00, green: 0.62, blue: 0.35)
    )

    private typealias Components = (red: Double, green: Double, blue: Double)

    private static func adaptive(light: Components, dark: Components) -> Color {
        Color(UIColor { traits in
            let value = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: value.red, green: value.green, blue: value.blue, alpha: 1)
        })
    }
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
