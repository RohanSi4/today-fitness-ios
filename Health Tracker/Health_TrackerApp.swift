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
                TodayWidgetPublisher.publish(
                    store: TodayStore.shared,
                    plan: TrainingPlanService.shared.plan,
                    runs: runs.workouts
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
