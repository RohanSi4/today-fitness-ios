import Foundation
import Testing
@testable import Health_Tracker

/// `refresh()` had no coverage and swallowed every fetch error with `try?`. The
/// visible result was a week card reading "0 of 26.1 miles" whether he had run
/// nothing or Apple Health had simply refused to answer, which is the same
/// confident-zero failure the Lock Screen widget had.
@MainActor
struct RunningWorkoutServiceTests {
    private func run(miles: Double, daysAgo: Int) -> RunningWorkoutSummary {
        let start = Date().addingTimeInterval(-Double(daysAgo) * 86_400)
        return RunningWorkoutSummary(
            id: UUID(),
            startedAt: start,
            endedAt: start.addingTimeInterval(3_000),
            miles: miles,
            duration: 3_000
        )
    }

    @Test func aSuccessfulReadPublishesRunsNewestFirst() async {
        let provider = StubRunProvider(result: .success([run(miles: 4, daysAgo: 3), run(miles: 6, daysAgo: 1)]))
        let service = RunningWorkoutService(healthStore: provider)

        await service.refresh()

        #expect(service.workouts.count == 2)
        #expect(service.workouts.first?.miles == 6)
        #expect(service.lastUpdated != nil)
        #expect(!service.lastReadFailed)
        #expect(service.hasTrustworthyRunData)
    }

    /// The bug. A refused or failed read must not read as a rest week.
    @Test func aFailedFirstReadIsNotPresentedAsARestWeek() async {
        let service = RunningWorkoutService(healthStore: StubRunProvider(result: .failure(StubError())))

        await service.refresh()

        #expect(service.workouts.isEmpty)
        #expect(service.lastReadFailed)
        #expect(service.lastUpdated == nil)
        // The whole point: the UI can tell these apart now.
        #expect(!service.hasTrustworthyRunData)
    }

    @Test func aGenuinelyEmptyWeekIsStillTrusted() async {
        let service = RunningWorkoutService(healthStore: StubRunProvider(result: .success([])))

        await service.refresh()

        #expect(service.workouts.isEmpty)
        #expect(!service.lastReadFailed)
        // Read fine, he just did not run. Nothing should be flagged.
        #expect(service.hasTrustworthyRunData)
    }

    /// Once something good has been read, a later failure keeps it. Blanking the
    /// list on a transient error would lose the week for no reason.
    @Test func aLaterFailureKeepsTheLastGoodRuns() async {
        let provider = StubRunProvider(result: .success([run(miles: 6, daysAgo: 1)]))
        let service = RunningWorkoutService(healthStore: provider)
        await service.refresh()
        let firstUpdate = service.lastUpdated

        provider.result = .failure(StubError())
        await service.refresh()

        #expect(service.workouts.count == 1)
        #expect(service.workouts.first?.miles == 6)
        #expect(service.lastReadFailed)
        // Stale, but real, so the card keeps presenting it as a total.
        #expect(service.hasTrustworthyRunData)
        #expect(service.lastUpdated == firstUpdate)
    }

    @Test func recoveringFromAFailureClearsTheFlag() async {
        let provider = StubRunProvider(result: .failure(StubError()))
        let service = RunningWorkoutService(healthStore: provider)
        await service.refresh()
        #expect(service.lastReadFailed)

        provider.result = .success([run(miles: 5, daysAgo: 0)])
        await service.refresh()

        #expect(!service.lastReadFailed)
        #expect(service.hasTrustworthyRunData)
        #expect(service.workouts.count == 1)
    }

    @Test func aDeviceWithoutHealthDataIsNotTreatedAsAFailure() async {
        let provider = StubRunProvider(result: .failure(StubError()))
        provider.isHealthDataAvailable = false
        let service = RunningWorkoutService(healthStore: provider)

        await service.refresh()

        // Nothing was attempted, so there is nothing to warn about.
        #expect(!service.lastReadFailed)
        #expect(provider.fetchCount == 0)
    }
}

private struct StubError: Error {}

private final class StubRunProvider: RunningWorkoutProviding, @unchecked Sendable {
    var result: Result<[RunningWorkoutSummary], Error>
    var isHealthDataAvailable = true
    private(set) var fetchCount = 0

    init(result: Result<[RunningWorkoutSummary], Error>) {
        self.result = result
    }

    func requestWorkoutAuthorization() async throws {}

    func fetchRunningWorkouts(start: Date, end: Date) async throws -> [RunningWorkoutSummary] {
        fetchCount += 1
        return try result.get()
    }

}
