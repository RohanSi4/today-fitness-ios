//
//  Health_TrackerApp.swift
//  Health Tracker
//
//  Created by Rohan Singh on 6/17/25.
//

import SwiftUI

@main
struct Health_TrackerApp: App {
    @StateObject private var appState: AppState

    init() {
        let state = AppState()
        _appState = StateObject(wrappedValue: state)
        NotificationManager.shared.appState = state
        NotificationManager.shared.register()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
        }
    }
}
