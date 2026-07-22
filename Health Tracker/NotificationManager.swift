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

protocol WeightReminderScheduling {
    func requestAuthorization() async -> Bool
    func scheduleWeightReminders(from date: Date, days: Int) async
    func cancelWeightReminders(for date: Date)
}

final class NotificationManager: NSObject, RecapNotificationScheduling, WeightReminderScheduling, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()

    weak var appState: AppState?

    private let recapNotificationID = "dailyRecap"
    private let recapDateKey = "recapDate"
    private let weightReminderPrefix = "weightReminder"

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

    func scheduleWeightReminders(from date: Date = Date(), days: Int = 30) async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized ||
                settings.authorizationStatus == .provisional else {
            return
        }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: date)
        let formatter = Self.dayFormatter

        for offset in 0..<max(1, min(days, 30)) {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { continue }
            let dayKey = formatter.string(from: day)
            await scheduleWeightReminder(
                identifier: "\(weightReminderPrefix).morning.\(dayKey)",
                title: "Morning check-in",
                body: "Log your weight while the scale is right there.",
                day: day,
                hour: 8,
                minute: 30,
                center: center
            )
            await scheduleWeightReminder(
                identifier: "\(weightReminderPrefix).lunch.\(dayKey)",
                title: "Quick reminder",
                body: "No weight logged yet. It takes five seconds.",
                day: day,
                hour: 12,
                minute: 0,
                center: center
            )
        }
    }

    func cancelWeightReminders(for date: Date) {
        let dayKey = Self.dayFormatter.string(from: date)
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [
            "\(weightReminderPrefix).morning.\(dayKey)",
            "\(weightReminderPrefix).lunch.\(dayKey)"
        ])
    }

    func scheduleWeightReminderAfterWake(_ wakeTime: Date) {
        Task { @MainActor [weak self] in
            guard let self, TodayStore.shared.todayWeight == nil else { return }
            let center = UNUserNotificationCenter.current()
            let settings = await center.notificationSettings()
            guard settings.authorizationStatus == .authorized ||
                    settings.authorizationStatus == .provisional else {
                return
            }

            let now = Date()
            let intended = wakeTime.addingTimeInterval(5 * 60)
            let fireDate = max(intended, now.addingTimeInterval(5))
            guard fireDate.timeIntervalSince(now) <= 90 * 60 else { return }

            let dayKey = Self.dayFormatter.string(from: wakeTime)
            center.removePendingNotificationRequests(withIdentifiers: [
                "\(weightReminderPrefix).morning.\(dayKey)",
                "\(weightReminderPrefix).wake.\(dayKey)"
            ])

            let content = UNMutableNotificationContent()
            content.title = "You’re up"
            content.body = "Log your morning weight while the scale is nearby."
            content.sound = .default
            content.userInfo = ["todayRoute": "weight"]

            let components = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute, .second],
                from: fireDate
            )
            let request = UNNotificationRequest(
                identifier: "\(weightReminderPrefix).wake.\(dayKey)",
                content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            )
            try? await center.add(request)
        }
    }

    private func scheduleWeightReminder(
        identifier: String,
        title: String,
        body: String,
        day: Date,
        hour: Int,
        minute: Int,
        center: UNUserNotificationCenter
    ) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.userInfo = ["todayRoute": "weight"]

        var components = Calendar.current.dateComponents([.year, .month, .day], from: day)
        components.hour = hour
        components.minute = minute
        guard let fireDate = Calendar.current.date(from: components), fireDate > Date() else { return }

        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        )
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

        if response.notification.request.content.userInfo["todayRoute"] as? String == "weight" {
            Task { @MainActor [weak self] in
                self?.appState?.openWeightLogger()
            }
            return
        }

        let value = response.notification.request.content.userInfo[recapDateKey]
        let timestamp = (value as? NSNumber)?.doubleValue ?? value as? Double
        guard let timestamp else { return }

        Task { @MainActor [weak self] in
            self?.appState?.openRecap(for: Date(timeIntervalSince1970: timestamp))
        }
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

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
