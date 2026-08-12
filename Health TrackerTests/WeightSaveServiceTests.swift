import Foundation
import Testing
@testable import Health_Tracker

@MainActor
struct WeightSaveServiceTests {
    /// The regression this whole file exists for. Health access denied, or
    /// granted once and revoked later in Settings, used to jump straight past
    /// `recordWeight` and lose the reading he had just typed.
    @Test func aRefusedHealthWriteNeverCostsTheReading() async throws {
        let store = TodayStore(storageURL: temporaryURL("health-denied"), calendar: utcCalendar)
        let health = StubHealthStore(authorizationError: HealthStubError.denied)
        let reminders = StubReminders()

        let outcome = await WeightSaveService.save(
            pounds: 184.4,
            on: day,
            store: store,
            healthStore: health,
            reminders: reminders,
            calendar: utcCalendar
        )

        #expect(outcome == .saved(health: .failed(HealthStubError.denied.localizedDescription)))
        #expect(store.weights.count == 1)
        #expect(store.weights[0].pounds == 184.4)
        #expect(store.weights[0].healthKitID == nil)
    }

    @Test func aFailedSampleWriteAlsoKeepsTheReading() async throws {
        let store = TodayStore(storageURL: temporaryURL("sample-failed"), calendar: utcCalendar)
        let health = StubHealthStore(saveError: HealthStubError.denied)

        let outcome = await WeightSaveService.save(
            pounds: 183.2,
            on: day,
            store: store,
            healthStore: health,
            reminders: StubReminders(),
            calendar: utcCalendar
        )

        guard case .saved(.failed) = outcome else {
            Issue.record("Expected a saved-but-not-in-Health outcome, got \(outcome)")
            return
        }
        #expect(store.weights.count == 1)
        #expect(store.weights[0].pounds == 183.2)
    }

    /// He logged his weight. The phone must stop nagging him about it whether or
    /// not Apple Health took a copy, which is what the old ordering got wrong.
    @Test func remindersAreClearedEvenWhenHealthRefuses() async {
        let store = TodayStore(storageURL: temporaryURL("reminders-denied"), calendar: utcCalendar)
        let reminders = StubReminders()

        _ = await WeightSaveService.save(
            pounds: 184.4,
            on: day,
            store: store,
            healthStore: StubHealthStore(authorizationError: HealthStubError.denied),
            reminders: reminders,
            calendar: utcCalendar
        )

        #expect(reminders.cancelledDates.contains { utcCalendar.isDate($0, inSameDayAs: day) })
        #expect(reminders.scheduledDayCounts == [30])
    }

    @Test func aSuccessfulWriteAttachesTheSampleWithoutDuplicatingTheDay() async throws {
        let store = TodayStore(storageURL: temporaryURL("health-ok"), calendar: utcCalendar)
        let sampleID = UUID()
        let health = StubHealthStore(sampleID: sampleID)

        let outcome = await WeightSaveService.save(
            pounds: 184.4,
            on: day,
            store: store,
            healthStore: health,
            reminders: StubReminders(),
            calendar: utcCalendar
        )

        #expect(outcome == .saved(health: .written))
        // Recorded twice on purpose, once before the Health write and once after
        // to attach the id. The store is keyed by day, so that is one row.
        #expect(health.savedPounds == [184.4])
        #expect(store.weights.count == 1)
        #expect(store.weights[0].healthKitID == sampleID)
    }

    @Test func aDeviceWithoutHealthDataStillSavesQuietly() async {
        let store = TodayStore(storageURL: temporaryURL("no-health"), calendar: utcCalendar)
        let health = StubHealthStore(isHealthDataAvailable: false)

        let outcome = await WeightSaveService.save(
            pounds: 181.0,
            on: day,
            store: store,
            healthStore: health,
            reminders: StubReminders(),
            calendar: utcCalendar
        )

        #expect(outcome == .saved(health: .unavailable))
        #expect(store.weights.count == 1)
        #expect(health.authorizationRequests == 0)
    }

    /// The store drops implausible readings silently, which used to mean the
    /// sheet closed as though the weight had been saved.
    @Test func anImplausibleReadingIsReportedRatherThanSilentlyDropped() async {
        let store = TodayStore(storageURL: temporaryURL("implausible"), calendar: utcCalendar)

        let outcome = await WeightSaveService.save(
            pounds: 1_780,
            on: day,
            store: store,
            healthStore: StubHealthStore(),
            reminders: StubReminders(),
            calendar: utcCalendar
        )

        guard case .rejected = outcome else {
            Issue.record("Expected a rejection, got \(outcome)")
            return
        }
        #expect(store.weights.isEmpty)
    }

    @Test func arejectedReadingLeavesTheExistingDayIntact() async {
        let store = TodayStore(storageURL: temporaryURL("keep-existing"), calendar: utcCalendar)
        store.recordWeight(184.4, on: day)

        let outcome = await WeightSaveService.save(
            pounds: 1_780,
            on: day,
            store: store,
            healthStore: StubHealthStore(),
            reminders: StubReminders(),
            calendar: utcCalendar
        )

        guard case .rejected = outcome else {
            Issue.record("Expected a rejection, got \(outcome)")
            return
        }
        #expect(store.weights.count == 1)
        #expect(store.weights[0].pounds == 184.4)
    }

    @Test func aRejectedReadingNeverReachesAppleHealth() async {
        let health = StubHealthStore()

        _ = await WeightSaveService.save(
            pounds: -5,
            on: day,
            store: TodayStore(storageURL: temporaryURL("negative"), calendar: utcCalendar),
            healthStore: health,
            reminders: StubReminders(),
            calendar: utcCalendar
        )

        #expect(health.savedPounds.isEmpty)
        #expect(health.authorizationRequests == 0)
    }

    @Test func healthHistoryIsMergedAfterASuccessfulWrite() async {
        let store = TodayStore(storageURL: temporaryURL("merge"), calendar: utcCalendar)
        let earlier = day.addingTimeInterval(-86_400)
        let health = StubHealthStore(
            history: [WeightEntry(date: earlier, pounds: 185.0, healthKitID: UUID())]
        )

        _ = await WeightSaveService.save(
            pounds: 184.4,
            on: day,
            store: store,
            healthStore: health,
            reminders: StubReminders(),
            calendar: utcCalendar
        )

        #expect(store.weights.count == 2)
        #expect(store.weights.contains { $0.pounds == 185.0 })
    }

    @Test func correctingATodayOwnedWeightRemovesTheOldHealthSample() async {
        let store = TodayStore(storageURL: temporaryURL("replace-owned"), calendar: utcCalendar)
        let oldID = UUID()
        let newID = UUID()
        store.recordWeight(
            184.4,
            on: day,
            healthKitID: oldID,
            healthKitOwnedByToday: true
        )
        let health = StubHealthStore(sampleID: newID)

        _ = await WeightSaveService.save(
            pounds: 183.9,
            on: day,
            store: store,
            healthStore: health,
            reminders: StubReminders(),
            calendar: utcCalendar
        )

        #expect(health.deletedIDs == [oldID])
        #expect(store.weights.first?.healthKitID == newID)
        #expect(store.weights.first?.healthKitOwnedByToday == true)
    }

    private var day: Date { Date(timeIntervalSince1970: 1_753_075_200) }

    private func temporaryURL(_ name: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("WeightSaveTests-\(name)-\(UUID().uuidString).json")
    }

    private var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }
}

private enum HealthStubError: LocalizedError {
    case denied

    var errorDescription: String? { "Today is not allowed to write weight to Apple Health." }
}

@MainActor
private final class StubHealthStore: BodyWeightHealthStoring, BodyWeightHealthDeleting {
    let isHealthDataAvailable: Bool
    private let authorizationError: Error?
    private let saveError: Error?
    private let sampleID: UUID
    private let history: [WeightEntry]

    private(set) var authorizationRequests = 0
    private(set) var savedPounds: [Double] = []
    private(set) var deletedIDs: [UUID] = []

    init(
        isHealthDataAvailable: Bool = true,
        authorizationError: Error? = nil,
        saveError: Error? = nil,
        sampleID: UUID = UUID(),
        history: [WeightEntry] = []
    ) {
        self.isHealthDataAvailable = isHealthDataAvailable
        self.authorizationError = authorizationError
        self.saveError = saveError
        self.sampleID = sampleID
        self.history = history
    }

    func requestBodyWeightAuthorization() async throws {
        authorizationRequests += 1
        if let authorizationError { throw authorizationError }
    }

    func saveBodyWeight(pounds: Double, date: Date) async throws -> UUID {
        if let saveError { throw saveError }
        savedPounds.append(pounds)
        return sampleID
    }

    func fetchBodyWeights(start: Date, end: Date) async throws -> [WeightEntry] {
        history
    }

    func deleteBodyWeight(id: UUID) async throws {
        deletedIDs.append(id)
    }
}

private final class StubReminders: WeightReminderScheduling, @unchecked Sendable {
    private(set) var cancelledDates: [Date] = []
    private(set) var scheduledDayCounts: [Int] = []

    func requestAuthorization() async -> Bool { true }

    func scheduleWeightReminders(from date: Date, days: Int, firstCommitments: [String: Date]) async {
        scheduledDayCounts.append(days)
    }

    func cancelWeightReminders(for date: Date) {
        cancelledDates.append(date)
    }
}
