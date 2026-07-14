import Foundation
import UserNotifications

protocol RecapNotificationScheduling {
    func requestAuthorization() async -> Bool
    func scheduleSleepHighlightIfAuthorized(
        wakeTime: Date,
        sleepSummary: SleepSummary,
        recapDate: Date
    ) async
}

final class NotificationManager: NSObject, RecapNotificationScheduling, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()

    weak var appState: AppState?

    private let recapNotificationID = "dailyRecap"
    private let recapDateKey = "recapDate"

    func register() {
        UNUserNotificationCenter.current().delegate = self
    }

    func requestAuthorization() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound])
        } catch {
            return false
        }
    }

    func scheduleSleepHighlightIfAuthorized(
        wakeTime: Date,
        sleepSummary: SleepSummary,
        recapDate: Date
    ) async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized ||
                settings.authorizationStatus == .provisional else {
            return
        }

        guard let fireDate = Calendar.current.date(byAdding: .minute, value: 20, to: wakeTime),
              fireDate > Date() else {
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "Your daily recap is ready"
        content.body = buildSleepHighlight(for: sleepSummary)
        content.sound = .default
        content.userInfo = [recapDateKey: recapDate.timeIntervalSince1970]

        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: fireDate
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(
            identifier: recapNotificationID,
            content: content,
            trigger: trigger
        )

        center.removePendingNotificationRequests(withIdentifiers: [recapNotificationID])
        try? await center.add(request)
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        defer { completionHandler() }

        let value = response.notification.request.content.userInfo[recapDateKey]
        let timestamp = (value as? NSNumber)?.doubleValue ?? value as? Double
        guard let timestamp else { return }

        Task { @MainActor [weak self] in
            self?.appState?.openRecap(for: Date(timeIntervalSince1970: timestamp))
        }
    }

    private func buildSleepHighlight(for summary: SleepSummary) -> String {
        guard summary.avgDuration > 0 else {
            return "Sleep score: \(summary.score). You slept \(formattedDuration(summary.duration))."
        }

        let deltaMinutes = Int(abs(summary.durationDelta) / 60)
        let direction = summary.durationDelta >= 0 ? "more" : "less"
        return "Sleep score: \(summary.score). That’s \(deltaMinutes) minutes \(direction) than your baseline."
    }

    private func formattedDuration(_ seconds: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: seconds) ?? "--"
    }
}
