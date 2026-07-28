import Foundation
import HealthKit
import Testing
@testable import Health_Tracker

/// `send(_:)` had no coverage at all before `RunWorkoutScheduling` existed: it
/// talked to WorkoutKit directly, and WorkoutKit needs a paired Watch, so the
/// one path that actually pushes a run to his wrist was the one path nothing
/// could exercise. Every guard below was previously verifiable only by
/// scheduling a real workout and looking at the Watch.
@MainActor
struct WatchWorkoutServiceTests {
    // MARK: - Guards that must not reach the scheduler

    @Test func aDayWithNoRunInItIsRejectedBeforeAnythingIsScheduled() async {
        let scheduler = StubRunScheduler()
        let service = WatchWorkoutService(scheduler: scheduler)

        await service.send(day(text: "Rest + upper body lift"))

        #expect(service.state == .failed("Today could not find a safe distance goal in this run."))
        #expect(scheduler.scheduleCount == 0)
    }

    @Test func aDeviceWithoutAPairedWatchIsRejectedBeforeAnythingIsScheduled() async {
        let scheduler = StubRunScheduler(isSupported: false)
        let service = WatchWorkoutService(scheduler: scheduler)

        await service.send(day(text: "6 mile run"))

        #expect(service.state == .failed("A paired Apple Watch with the Workout app is required."))
        #expect(scheduler.scheduleCount == 0)
    }

    /// A malformed date must fail rather than schedule the run on some
    /// calendar-corrected day he did not ask for.
    @Test func anUnparseableDateIsRejectedBeforeAnythingIsScheduled() async {
        let scheduler = StubRunScheduler()
        let service = WatchWorkoutService(scheduler: scheduler)

        await service.send(day(date: "2026/07/28", text: "6 mile run"))

        #expect(service.state == .failed("This plan day has an invalid date."))
        #expect(scheduler.scheduleCount == 0)
    }

    @Test func aShortDateIsRejectedBeforeAnythingIsScheduled() async {
        let scheduler = StubRunScheduler()
        let service = WatchWorkoutService(scheduler: scheduler)

        await service.send(day(date: "2026-7-8", text: "6 mile run"))

        #expect(service.state == .failed("This plan day has an invalid date."))
        #expect(scheduler.scheduleCount == 0)
    }

    @Test func refusedSchedulingAuthorizationIsRejectedBeforeAnythingIsScheduled() async {
        let scheduler = StubRunScheduler(authorization: .unavailable)
        let service = WatchWorkoutService(scheduler: scheduler)

        await service.send(day(text: "6 mile run"))

        #expect(service.state == .failed("Allow workout scheduling to send this run to Apple Watch."))
        #expect(scheduler.scheduleCount == 0)
    }

    @Test func aGoalTheWatchCannotHoldIsRejectedBeforeAnythingIsScheduled() async {
        let scheduler = StubRunScheduler(supportsRun: false)
        let service = WatchWorkoutService(scheduler: scheduler)

        await service.send(day(text: "6 mile run"))

        #expect(service.state == .failed("Apple Watch does not support this run goal."))
        #expect(scheduler.scheduleCount == 0)
    }

    // MARK: - Authorization

    /// Prompting is the expensive, user-visible part, so it happens once and
    /// only when the answer is genuinely unknown.
    @Test func anUndecidedAuthorizationPromptsExactlyOnce() async {
        let scheduler = StubRunScheduler(authorization: .notDetermined, afterRequest: .authorized)
        let service = WatchWorkoutService(scheduler: scheduler)

        await service.send(day(text: "6 mile run"))

        #expect(scheduler.requestCount == 1)
        #expect(service.state == .scheduled("2026-07-28"))
    }

    @Test func anAlreadyAuthorizedSchedulerIsNeverPrompted() async {
        let scheduler = StubRunScheduler(authorization: .authorized)
        let service = WatchWorkoutService(scheduler: scheduler)

        await service.send(day(text: "6 mile run"))

        #expect(scheduler.requestCount == 0)
        #expect(service.state == .scheduled("2026-07-28"))
    }

    @Test func aPromptHeDeclinesStopsTheSend() async {
        let scheduler = StubRunScheduler(authorization: .notDetermined, afterRequest: .unavailable)
        let service = WatchWorkoutService(scheduler: scheduler)

        await service.send(day(text: "6 mile run"))

        #expect(scheduler.requestCount == 1)
        #expect(service.state == .failed("Allow workout scheduling to send this run to Apple Watch."))
        #expect(scheduler.scheduleCount == 0)
    }

    // MARK: - The scheduled run

    @Test func aConfirmedRunReportsScheduled() async throws {
        let scheduler = StubRunScheduler()
        let service = WatchWorkoutService(scheduler: scheduler)

        await service.send(day(text: "6 mile run"))

        #expect(service.state == .scheduled("2026-07-28"))
        let request = try #require(scheduler.lastRequest)
        #expect(request.miles == 6)
        #expect(request.date.year == 2026)
        #expect(request.date.month == 7)
        #expect(request.date.day == 28)
    }

    /// The Watch not confirming is different from the app failing to ask, and he
    /// needs to know the run is not actually on his wrist.
    @Test func anUnconfirmedRunIsReportedAsAFailureNotASuccess() async {
        let scheduler = StubRunScheduler(confirms: false)
        let service = WatchWorkoutService(scheduler: scheduler)

        await service.send(day(text: "6 mile run"))

        #expect(service.state == .failed("Apple Watch did not confirm the scheduled run."))
        #expect(scheduler.scheduleCount == 1)
    }

    /// The stable id is the whole reason a second tap replaces the run instead
    /// of stacking a duplicate onto the same day.
    @Test func theSameDayAlwaysSchedulesUnderTheSamePlanID() async {
        let scheduler = StubRunScheduler()
        let service = WatchWorkoutService(scheduler: scheduler)

        await service.send(day(text: "6 mile run"))
        await service.send(day(text: "8 mile run"))

        #expect(scheduler.planIDs.count == 2)
        #expect(scheduler.planIDs[0] == scheduler.planIDs[1])
        #expect(scheduler.planIDs[0] == WatchWorkoutService.planID(for: "2026-07-28"))
    }

    @Test func aDifferentDayGetsADifferentPlanID() async {
        let scheduler = StubRunScheduler()
        let service = WatchWorkoutService(scheduler: scheduler)

        await service.send(day(date: "2026-07-28", text: "6 mile run"))
        await service.send(day(date: "2026-07-29", text: "6 mile run"))

        #expect(scheduler.planIDs.count == 2)
        #expect(scheduler.planIDs[0] != scheduler.planIDs[1])
    }

    // MARK: - Location

    @Test func aTreadmillRunIsScheduledIndoors() async throws {
        let scheduler = StubRunScheduler()
        let service = WatchWorkoutService(scheduler: scheduler)

        await service.send(day(text: "6 mile treadmill run"))

        #expect(try #require(scheduler.lastRequest).location == .indoor)
    }

    @Test func anOutdoorRunIsScheduledOutdoors() async throws {
        let scheduler = StubRunScheduler()
        let service = WatchWorkoutService(scheduler: scheduler)

        await service.send(day(text: "6 mile run outdoors"))

        #expect(try #require(scheduler.lastRequest).location == .outdoor)
    }

    @Test func anUnqualifiedRunLeavesTheLocationUnknown() async throws {
        let scheduler = StubRunScheduler()
        let service = WatchWorkoutService(scheduler: scheduler)

        await service.send(day(text: "6 mile run"))

        #expect(try #require(scheduler.lastRequest).location == .unknown)
    }

    // MARK: - Distance bounds

    @Test func theSmallestAllowedRunIsAccepted() async throws {
        let scheduler = StubRunScheduler()
        let service = WatchWorkoutService(scheduler: scheduler)

        await service.send(day(text: "0.1 mile shakeout"))

        #expect(service.state == .scheduled("2026-07-28"))
        #expect(try #require(scheduler.lastRequest).miles == 0.1)
    }

    /// Just under the floor, and the only boundary case that reaches the range
    /// check with a real value: anything larger than two digits never parses at
    /// all (see `aThreeDigitRunNeverParsesSoItFailsAsAMissingDistance`).
    @Test func aRunJustUnderTheFloorIsRejected() async {
        let scheduler = StubRunScheduler()
        let service = WatchWorkoutService(scheduler: scheduler)

        await service.send(day(text: "0.09 mile stride"))

        #expect(service.state == .failed("Today could not find a safe distance goal in this run."))
        #expect(scheduler.scheduleCount == 0)
    }

    @Test func theLongestParseableRunIsAccepted() async throws {
        let scheduler = StubRunScheduler()
        let service = WatchWorkoutService(scheduler: scheduler)

        await service.send(day(text: "99 mile ultra"))

        #expect(service.state == .scheduled("2026-07-28"))
        #expect(try #require(scheduler.lastRequest).miles == 99)
    }

    /// `plannedRunMiles` matches at most two digits, so a three-digit run is not
    /// a distance the parser can produce and the day reads as having no run in
    /// it. The upper end of the `0.1...100` range in `send(_:)` is therefore
    /// unreachable in practice. Pinned here so the day someone widens that regex
    /// this stops being true loudly rather than quietly.
    @Test func aThreeDigitRunNeverParsesSoItFailsAsAMissingDistance() async {
        let scheduler = StubRunScheduler()
        let service = WatchWorkoutService(scheduler: scheduler)

        #expect(day(text: "100 mile run").plannedRunMiles == nil)

        await service.send(day(text: "100 mile run"))

        #expect(service.state == .failed("Today could not find a safe distance goal in this run."))
        #expect(scheduler.scheduleCount == 0)
    }

    // MARK: - Support

    @Test func supportIsReadFromTheSchedulerRatherThanAssumed() {
        #expect(WatchWorkoutService(scheduler: StubRunScheduler(isSupported: true)).isSupported)
        #expect(!WatchWorkoutService(scheduler: StubRunScheduler(isSupported: false)).isSupported)
    }

    private func day(date: String = "2026-07-28", text: String) -> TrainingPlanDay {
        TrainingPlanDay(date: date, dayLabel: "Tue", text: text, isKeyDay: false, details: [])
    }
}

/// Records what the service asked WorkoutKit to do.
///
/// Lock-guarded `@unchecked Sendable` rather than `@MainActor`, because
/// `RunWorkoutScheduling` requires `Sendable` and declares `isSupported` and
/// `supportsRun` as nonisolated synchronous members, which a main-actor class
/// cannot witness. The lock is the same shape `HealthKitManager` uses in
/// production, so the claim is real rather than a silencer.
private final class StubRunScheduler: RunWorkoutScheduling, @unchecked Sendable {
    struct Request: Equatable {
        let planID: UUID
        let miles: Double
        let location: HKWorkoutSessionLocationType
        let date: DateComponents
    }

    let isSupported: Bool
    private let runIsSupported: Bool
    private let authorization: WatchSchedulingAuthorization
    private let afterRequest: WatchSchedulingAuthorization
    private let confirms: Bool

    private let lock = NSLock()
    private var requests: [Request] = []
    private var requestAuthorizationCalls = 0

    init(
        isSupported: Bool = true,
        supportsRun: Bool = true,
        authorization: WatchSchedulingAuthorization = .authorized,
        afterRequest: WatchSchedulingAuthorization = .authorized,
        confirms: Bool = true
    ) {
        self.isSupported = isSupported
        self.runIsSupported = supportsRun
        self.authorization = authorization
        self.afterRequest = afterRequest
        self.confirms = confirms
    }

    var scheduleCount: Int { withLock { requests.count } }
    var requestCount: Int { withLock { requestAuthorizationCalls } }
    var lastRequest: Request? { withLock { requests.last } }
    var planIDs: [UUID] { withLock { requests.map(\.planID) } }

    func supportsRun(miles: Double, location: HKWorkoutSessionLocationType) -> Bool {
        runIsSupported
    }

    func authorizationState() async -> WatchSchedulingAuthorization { authorization }

    func requestAuthorization() async -> WatchSchedulingAuthorization {
        withLock { requestAuthorizationCalls += 1 }
        return afterRequest
    }

    func replaceScheduledRun(
        planID: UUID,
        miles: Double,
        location: HKWorkoutSessionLocationType,
        at date: DateComponents
    ) async -> Bool {
        withLock {
            requests.append(
                Request(planID: planID, miles: miles, location: location, date: date)
            )
        }
        return confirms
    }

    private func withLock<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}
