import Combine
import CryptoKit
import Foundation
// No `import WorkoutKit`. Every WorkoutKit type now lives behind
// `RunWorkoutScheduling`, and keeping the import out is what stops one from
// leaking back into this main-actor class.
import HealthKit

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

    /// A `Sendable` façade rather than a `WorkoutScheduler`. WorkoutKit's
    /// scheduler is not `Sendable` and all of its members are `nonisolated` and
    /// `async`, so holding one in this `@MainActor` class meant the value had to
    /// leave the main actor on every call - an error under the Swift 6 language
    /// mode that `nonisolated(unsafe)` cannot fix, because the result types are
    /// not `Sendable` either and so cannot come back.
    ///
    /// It also replaces the old `supported` closure: both answers now come from
    /// the same object, so a test cannot set up the impossible combination of a
    /// supported device with no scheduler behind it.
    private let scheduler: any RunWorkoutScheduling

    init(scheduler: any RunWorkoutScheduling = WorkoutKitRunScheduler()) {
        self.scheduler = scheduler
    }

    var isSupported: Bool { scheduler.isSupported }

    func send(_ day: TrainingPlanDay) async {
        guard let miles = day.plannedRunMiles, (0.1...100).contains(miles) else {
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
        let current = await scheduler.authorizationState()
        let authorization = current == .notDetermined
            ? await scheduler.requestAuthorization()
            : current
        guard authorization == .authorized else {
            state = .failed("Allow workout scheduling to send this run to Apple Watch.")
            return
        }

        let location = Self.location(from: day.text)
        guard scheduler.supportsRun(miles: miles, location: location) else {
            state = .failed("Apple Watch does not support this run goal.")
            return
        }

        // The id is derived from the date, so sending the same day twice replaces
        // the scheduled run instead of stacking a duplicate on his Watch.
        let confirmed = await scheduler.replaceScheduledRun(
            planID: Self.planID(for: day.date),
            miles: miles,
            location: location,
            at: date
        )
        state = confirmed
            ? .scheduled(day.date)
            : .failed("Apple Watch did not confirm the scheduled run.")
    }

    static func runMiles(from text: String) -> Double? {
        TrainingPlanDay(
            date: "2000-01-01",
            dayLabel: "",
            text: text,
            isKeyDay: false,
            details: []
        ).plannedRunMiles
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
