import Foundation
import HealthKit
import WorkoutKit

/// Whether the Watch will accept scheduled workouts, in the app's own terms.
///
/// `WorkoutScheduler.AuthorizationState` is not `Sendable`, so it cannot be
/// returned to a main-actor caller under the Swift 6 language mode. Translating
/// at this boundary is what lets the rest of the app stay isolated.
enum WatchSchedulingAuthorization: Sendable, Equatable {
    case notDetermined
    case authorized
    case unavailable
}

/// Everything the Watch hand-off needs from WorkoutKit.
///
/// This exists because `WorkoutScheduler` is not `Sendable` and every one of its
/// members is `nonisolated` and `async`. Holding one inside the `@MainActor`
/// `WatchWorkoutService` meant the value had to leave the main actor to be used
/// at all, which is an error under Swift 6 and cannot be fixed with
/// `nonisolated(unsafe)` - the result types are not `Sendable` either, so they
/// cannot come back.
///
/// It is deliberately shaped around intent rather than mirroring WorkoutKit.
/// `replaceScheduledRun` is one operation because "remove the old plan, add the
/// new one, confirm it landed" is one thing the app wants and three things
/// WorkoutKit makes you do, and splitting it would put the non-Sendable
/// `WorkoutPlan` back in the caller's hands.
///
/// The second reason it is a protocol: `send(_:)` previously could not be
/// tested at all, because it talked to WorkoutKit directly and WorkoutKit needs
/// a paired Watch.
protocol RunWorkoutScheduling: Sendable {
    /// Whether this device can schedule Watch workouts at all.
    var isSupported: Bool { get }

    /// Whether the Watch accepts a distance goal of this size at this location.
    func supportsRun(miles: Double, location: HKWorkoutSessionLocationType) -> Bool

    func authorizationState() async -> WatchSchedulingAuthorization
    func requestAuthorization() async -> WatchSchedulingAuthorization

    /// Schedules a run, replacing any already scheduled under `planID`, and
    /// reports whether the Watch confirmed it afterwards.
    func replaceScheduledRun(
        planID: UUID,
        miles: Double,
        location: HKWorkoutSessionLocationType,
        at date: DateComponents
    ) async -> Bool
}

/// The real thing.
///
/// `@unchecked Sendable` covers the stored `WorkoutScheduler`, which Apple
/// documents as a process-wide singleton safe to use from any thread but has not
/// annotated. The reference is a `let` and is never reassigned, and no other
/// state is held here.
struct WorkoutKitRunScheduler: RunWorkoutScheduling, @unchecked Sendable {
    private let scheduler: WorkoutScheduler

    init(scheduler: WorkoutScheduler = .shared) {
        self.scheduler = scheduler
    }

    var isSupported: Bool { WorkoutScheduler.isSupported }

    func supportsRun(miles: Double, location: HKWorkoutSessionLocationType) -> Bool {
        SingleGoalWorkout.supportsGoal(
            .distance(miles, .miles),
            activity: .running,
            location: location
        )
    }

    func authorizationState() async -> WatchSchedulingAuthorization {
        Self.translate(await scheduler.authorizationState)
    }

    func requestAuthorization() async -> WatchSchedulingAuthorization {
        Self.translate(await scheduler.requestAuthorization())
    }

    func replaceScheduledRun(
        planID: UUID,
        miles: Double,
        location: HKWorkoutSessionLocationType,
        at date: DateComponents
    ) async -> Bool {
        let workout = SingleGoalWorkout(
            activity: .running,
            location: location,
            goal: .distance(miles, .miles)
        )
        let plan = WorkoutPlan(.goal(workout), id: planID)

        // Same order as before: clear anything under this id, then schedule, then
        // read back. The stable id is what makes a second tap replace rather than
        // stack up a duplicate run.
        for item in await scheduler.scheduledWorkouts where item.plan.id == planID {
            await scheduler.remove(item.plan, at: item.date)
        }
        await scheduler.schedule(plan, at: date)

        return await scheduler.scheduledWorkouts.contains { item in
            item.plan.id == planID
                && item.date.year == date.year
                && item.date.month == date.month
                && item.date.day == date.day
        }
    }

    /// Anything that is not "ask him" or "yes" is a dead end for this feature,
    /// so denied and restricted collapse into one case. The caller shows the
    /// same message either way, and pretending to distinguish them would imply
    /// a recovery path that does not exist.
    private static func translate(
        _ state: WorkoutScheduler.AuthorizationState
    ) -> WatchSchedulingAuthorization {
        switch state {
        case .notDetermined: .notDetermined
        case .authorized: .authorized
        default: .unavailable
        }
    }
}
