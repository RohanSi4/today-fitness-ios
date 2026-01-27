import Foundation
import UserNotifications

final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()

    weak var appState: AppState?

    private let recapNotificationId = "dailyRecap"
    private let recapDateKey = "recapDate"

    func register() {
        UNUserNotificationCenter.current().delegate = self
    }

    func requestAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        return await withCheckedContinuation { continuation in
            center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
                continuation.resume(returning: granted)
            }
        }
    }

    func scheduleSleepHighlight(wakeTime: Date, sleepSummary: SleepSummary, recapDate: Date) async {
        guard await requestAuthorization() else {
            return
        }

        guard let fireDate = Calendar.current.date(byAdding: .minute, value: 20, to: wakeTime) else {
            return
        }

        if fireDate <= Date() {
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "Daily health check"
        content.body = buildSleepHighlight(for: sleepSummary)
        content.sound = .default
        content.userInfo = [recapDateKey: isoDateString(from: recapDate)]

        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(identifier: recapNotificationId, content: content, trigger: trigger)

        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [recapNotificationId])

        do {
            try await center.add(request)
        } catch {
            // Best-effort scheduling; ignore errors for MVP.
        }
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
        let userInfo = response.notification.request.content.userInfo
        if let dateString = userInfo[recapDateKey] as? String,
           let recapDate = isoDate(from: dateString) {
            Task { @MainActor in
                appState?.openRecap(for: recapDate)
            }
        }
        completionHandler()
    }

    private func buildSleepHighlight(for summary: SleepSummary) -> String {
        let score = summary.score

        guard summary.avgDuration > 0 else {
            let durationText = formattedDuration(summary.duration)
            return "Sleep Score \(score). You slept \(durationText)."
        }

        let deltaMinutes = Int(abs(summary.durationDelta) / 60)
        let direction = summary.durationDelta >= 0 ? "more" : "less"
        return "Sleep Score \(score). You slept \(deltaMinutes)m \(direction) than your 7 day average."
    }

    private func formattedDuration(_ seconds: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: seconds) ?? "--"
    }

    private func isoDateString(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        return formatter.string(from: date)
    }

    private func isoDate(from string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        return formatter.date(from: string)
    }
}
