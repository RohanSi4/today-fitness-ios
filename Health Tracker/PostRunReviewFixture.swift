#if DEBUG
import Foundation

/// Deterministic full-app state for visual review in Simulator. This is gated by
/// both a Debug build and an explicit launch argument, so it cannot replace or
/// mutate HealthKit data in a release or a normal developer launch.
enum PostRunReviewFixture {
    static let launchArgument = "-reviewCompletedRun"

    static var isEnabled: Bool {
        ProcessInfo.processInfo.arguments.contains(launchArgument)
    }

    static func run(now: Date = .now) -> RunningWorkoutSummary {
        let duration: TimeInterval = 38 * 60
        let endedAt = now.addingTimeInterval(-8 * 60)
        return RunningWorkoutSummary(
            id: UUID(uuidString: "A17A0D00-0000-4000-8000-000000000001")!,
            startedAt: endedAt.addingTimeInterval(-duration),
            endedAt: endedAt,
            miles: 4.1,
            duration: duration
        )
    }

    static func plan(now: Date = .now, calendar: Calendar = .current) -> TrainingPlan {
        let today = calendar.startOfDay(for: now)
        let weekEnd = calendar.date(byAdding: .day, value: 6, to: today) ?? today
        return TrainingPlan(
            weekStart: dayKey(today),
            weekEnd: dayKey(weekEnd),
            prescribedMiles: 38,
            days: [
                TrainingPlanDay(
                    date: dayKey(today),
                    dayLabel: today.formatted(.dateTime.weekday(.abbreviated).month().day()),
                    text: "4 mile run + upper body lift",
                    isKeyDay: false,
                    details: [
                        "Keep the run easy and conversational.",
                        "Target 10:00 to 10:45 per mile.",
                        "Run outdoors.",
                        "Complete upper body lift #1.",
                    ]
                ),
            ]
        )
    }

    private static func dayKey(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
#endif
