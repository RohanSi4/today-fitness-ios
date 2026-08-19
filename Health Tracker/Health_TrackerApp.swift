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
        // Retries a publish the wake could not satisfy. A run landing on a locked
        // phone brings the store up empty, the publish correctly refuses, and
        // without this the Lock Screen keeps insisting the run is still owed.
        TodayWidgetRefresh.shared.start {
            let store = TodayStore.shared
            // The background wake arrives with the archive locked. This is the
            // one call that can turn that around, and it is a no-op once the
            // store already read cleanly.
            store.reloadIfUnreadable()
            return TodayWidgetPublisher.publish(
                store: store,
                plan: TrainingPlanService.shared.plan,
                runs: RunningWorkoutService.shared.workouts,
                // Rebuilt rather than omitted: a watch run syncing mid-lift
                // publishes from here, and passing nil would blank the rest
                // timer off the Lock Screen in the middle of the session.
                workout: TodayWidgetWorkoutBuilder.make(
                    from: store.activeWorkout,
                    catalog: ExerciseCatalog.shared
                ),
                catalog: ExerciseCatalog.shared
            )
        }
        // Awaited rather than fired into a detached `Task`: the observer holds
        // the background wake open until this returns, and a run that landed on
        // a locked phone is exactly the wake that gets suspended out from under
        // an unawaited one.
        let onWorkoutChange: @Sendable () async -> Void = {
            await RunningWorkoutService.shared.refresh()
            await TodayWidgetRefresh.shared.run()
        }
        // Registered here rather than from a view, because this is the only code
        // that runs on a background launch - which is the launch a watch run
        // actually arrives on.
        HealthKitManager.shared.startWorkoutMonitoring(onChange: onWorkoutChange)
        Task {
            // Registered a second time once the Health prompt has resolved.
            // HealthKit will not deliver to an observer executed against an
            // undetermined authorization, and a background launch cannot show a
            // prompt, so on a fresh install the registration above is inert and
            // this is the one that carries every run from then on. Already
            // granted - the normal case - resolves without a prompt and the swap
            // is a no-op in effect.
            try? await HealthKitManager.shared.requestWorkoutAuthorization()
            HealthKitManager.shared.startWorkoutMonitoring(onChange: onWorkoutChange)
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
        }
    }
}
