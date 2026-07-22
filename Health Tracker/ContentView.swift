import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var store = TodayStore.shared
    @StateObject private var planService = TrainingPlanService.shared
    @StateObject private var catalog = ExerciseCatalog.shared
    @ObservedObject private var intentRouter = TodayIntentRouter.shared

    var body: some View {
        TabView(selection: $appState.selectedTab) {
            NavigationStack {
                TodayView(store: store, planService: planService, catalog: catalog)
            }
            .tabItem { Label(AppTab.today.title, systemImage: AppTab.today.symbol) }
            .tag(AppTab.today)

            NavigationStack {
                HistoryView(store: store, catalog: catalog)
            }
            .tabItem { Label(AppTab.history.title, systemImage: AppTab.history.symbol) }
            .tag(AppTab.history)

            NavigationStack {
                InsightsView(store: store, catalog: catalog, recapDate: appState.recapDate)
            }
            .tabItem { Label(AppTab.insights.title, systemImage: AppTab.insights.symbol) }
            .tag(AppTab.insights)
        }
        .tint(TodayPalette.accent)
        .sheet(item: $appState.presentedSheet) { sheet in
            switch sheet {
            case .weight:
                WeightLogView(store: store)
            case .startWorkout(let kind):
                WorkoutLogView(store: store, catalog: catalog, kind: kind)
            case .finishedWorkout(let session):
                WorkoutSummaryView(session: session, store: store, catalog: catalog)
            }
        }
        .onChange(of: intentRouter.route) { _, route in
            guard let route else { return }
            switch route {
            case .weight:
                appState.openWeightLogger()
            case .today:
                appState.selectedTab = .today
            }
            intentRouter.consume()
        }
        .onOpenURL { url in
            guard url.scheme == "today" else { return }
            if url.host == "weight" { appState.openWeightLogger() }
        }
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
