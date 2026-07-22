import Combine
import CryptoKit
import Foundation
import HealthKit
import WorkoutKit

enum WatchWorkoutState: Equatable {
    case idle
    case sending(String)
    case scheduled(String)
    case failed(String)
}

@MainActor
final class WatchWorkoutService: ObservableObject {
    static let shared = WatchWorkoutService()

    @Published private(set) var state: WatchWorkoutState = .idle

    private let scheduler: WorkoutScheduler
    private let supported: () -> Bool

    init(
        scheduler: WorkoutScheduler = .shared,
        supported: @escaping () -> Bool = { WorkoutScheduler.isSupported }
    ) {
        self.scheduler = scheduler
        self.supported = supported
    }

    var isSupported: Bool { supported() }

    func send(_ day: TrainingPlanDay) async {
        guard let miles = Self.runMiles(from: day.text), (0.1...100).contains(miles) else {
            state = .failed("Today could not find a safe distance goal in this run.")
            return
        }
        guard isSupported else {
            state = .failed("A paired Apple Watch with the Workout app is required.")
            return
        }
        guard let date = Self.dateComponents(for: day.date) else {
            state = .failed("This plan day has an invalid date.")
            return
        }

        state = .sending(day.date)
        let current = await scheduler.authorizationState
        let authorization = current == .notDetermined
            ? await scheduler.requestAuthorization()
            : current
        guard authorization == .authorized else {
            state = .failed("Allow workout scheduling to send this run to Apple Watch.")
            return
        }

        let goal = WorkoutGoal.distance(miles, .miles)
        let location = Self.location(from: day.text)
        guard SingleGoalWorkout.supportsGoal(
            goal,
            activity: .running,
            location: location
        ) else {
            state = .failed("Apple Watch does not support this run goal.")
            return
        }

        let workout = SingleGoalWorkout(
            activity: .running,
            location: location,
            goal: goal
        )
        let plan = WorkoutPlan(.goal(workout), id: Self.planID(for: day.date))
        let existing = await scheduler.scheduledWorkouts.filter { $0.plan.id == plan.id }
        for item in existing {
            await scheduler.remove(item.plan, at: item.date)
        }
        await scheduler.schedule(plan, at: date)

        let confirmed = await scheduler.scheduledWorkouts.contains { item in
            item.plan.id == plan.id && item.date.year == date.year
                && item.date.month == date.month && item.date.day == date.day
        }
        state = confirmed
            ? .scheduled(day.date)
            : .failed("Apple Watch did not confirm the scheduled run.")
    }

    static func runMiles(from text: String) -> Double? {
        let pattern = #"(?i)\b(\d{1,2}(?:\.\d{1,2})?)\s*(?:mile|miles|mi)\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(
                in: text,
                range: NSRange(text.startIndex..., in: text)
              ),
              let range = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return Double(text[range])
    }

    static func location(from text: String) -> HKWorkoutSessionLocationType {
        let lower = text.lowercased()
        if lower.contains("treadmill") || lower.contains("indoor") { return .indoor }
        if lower.contains("outdoor") { return .outdoor }
        return .unknown
    }

    static func planID(for date: String) -> UUID {
        var bytes = Array(SHA256.hash(data: Data("today-run:\(date)".utf8)).prefix(16))
        bytes[6] = (bytes[6] & 0x0f) | 0x50
        bytes[8] = (bytes[8] & 0x3f) | 0x80
        return bytes.withUnsafeBufferPointer { buffer in
            NSUUID(uuidBytes: buffer.baseAddress!) as UUID
        }
    }

    private static func dateComponents(for value: String) -> DateComponents? {
        guard value.count == 10 else { return nil }
        let parts = value.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = .current
        components.year = parts[0]
        components.month = parts[1]
        components.day = parts[2]
        return components.date == nil ? nil : components
    }
}
