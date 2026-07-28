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

/// `@unchecked` is forced by the `NSObject` base, which is not itself `Sendable`,
/// so the compiler will not synthesise the conformance however safe the members
/// are. The claim still holds: `appState` is the only mutable state and it is
/// pinned to the main actor below, and everything else here is a `let`.
final class NotificationManager: NSObject, RecapNotificationScheduling, WeightReminderScheduling, UNUserNotificationCenterDelegate, @unchecked Sendable {
    static let shared = NotificationManager()

    /// Main-actor isolated rather than free-floating. It was already only ever
    /// touched from the main actor - written once from `App.init`, read inside
    /// the `Task { @MainActor }` hops in the delegate callbacks below - but
    /// nothing said so, which is what made this class unsendable. `AppState`
    /// drives SwiftUI, so the main actor is where it belongs anyway.
    @MainActor weak var appState: AppState?

    private let recapNotificationID = "dailyRecap"
    private let recapDateKey = "recapDate"
    private static let weightReminderPrefix = "weightReminder"
    private static let maximumReminderDays = 14

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

        // iOS keeps at most 64 pending local notifications per app and silently
        // discards the rest. Thirty days of two reminders was 60 on its own, so the
        // daily recap and the wake nudge were fighting for the last four slots and
        // losing at random. Two weeks is 28, which leaves real headroom, and these
        // get rescheduled every time a weight is logged anyway.
        for offset in 0..<Self.reminderDayCount(requested: days) {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { continue }
            let dayKey = Self.dayKey(for: day)
            await scheduleWeightReminder(
                identifier: "\(Self.weightReminderPrefix).morning.\(dayKey)",
                title: "Morning check-in",
                body: "Log your weight while the scale is right there.",
                day: day,
                hour: 8,
                minute: 30,
                center: center
            )
            await scheduleWeightReminder(
                identifier: "\(Self.weightReminderPrefix).lunch.\(dayKey)",
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
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: Self.weightReminderIDs(for: date))
    }

    /// iOS keeps 64 pending local notifications and silently drops the rest.
    static let systemPendingNotificationLimit = 64
    static let remindersPerDay = 2

    static func reminderDayCount(requested: Int) -> Int {
        max(1, min(requested, maximumReminderDays))
    }

    /// Every reminder that nags about logging a weight for this day. The wake nudge
    /// used to be left out, so after logging on the scale the phone still buzzed
    /// "log your morning weight" a few minutes later.
    static func weightReminderIDs(for date: Date) -> [String] {
        let dayKey = Self.dayKey(for: date)
        return ["morning", "lunch", "wake"].map { "\(Self.weightReminderPrefix).\($0).\(dayKey)" }
    }

    func scheduleWeightReminderAfterWake(_ wakeTime: Date) {
        Task { @MainActor in
            guard TodayStore.shared.todayWeight == nil else { return }
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

            let dayKey = Self.dayKey(for: wakeTime)
            center.removePendingNotificationRequests(
                withIdentifiers: Self.weightReminderIDs(for: wakeTime)
            )

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
                identifier: "\(Self.weightReminderPrefix).wake.\(dayKey)",
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

    /// Read `Calendar.current` per call rather than caching a formatter, so the day
    /// a reminder is filed under follows the device across time zones.
    static func dayKey(for date: Date, calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
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
