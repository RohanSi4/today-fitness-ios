//
//  Health_TrackerApp.swift
//  Health Tracker
//
//  Created by Rohan Singh on 6/17/25.
//

import SwiftUI
import AppIntents

@main
struct Health_TrackerApp: App {
    @StateObject private var appState: AppState

    init() {
        let state = AppState()
        _appState = StateObject(wrappedValue: state)
        NotificationManager.shared.appState = state
        NotificationManager.shared.register()
        TodayShortcuts.updateAppShortcutParameters()
        HealthKitManager.shared.startSleepWakeMonitoring { wakeTime in
            NotificationManager.shared.scheduleWeightReminderAfterWake(wakeTime)
        }
        HealthKitManager.shared.startWorkoutMonitoring {
            Task { @MainActor in
                let runs = RunningWorkoutService.shared
                await runs.refresh()
                let store = TodayStore.shared
                TodayWidgetPublisher.publish(
                    store: store,
                    plan: TrainingPlanService.shared.plan,
                    runs: runs.workouts,
                    // Rebuilt rather than omitted: a watch run syncing mid-lift
                    // publishes from here, and passing nil would blank the rest
                    // timer off the Lock Screen in the middle of the session.
                    workout: TodayWidgetWorkoutBuilder.make(
                        from: store.activeWorkout,
                        catalog: ExerciseCatalog.shared
                    )
                )
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
        }
    }
}
