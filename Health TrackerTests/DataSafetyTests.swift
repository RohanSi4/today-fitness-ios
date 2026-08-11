import Foundation
import CryptoKit
import Testing
@testable import Health_Tracker

// Tests for the paths that can lose a day - or a year - of training data:
// an unreadable file, a partly unreadable file, a save that never lands, and a
// coach sync that reports success for data it never sent.

@MainActor
struct StoreDataSafetyTests {
    @Test func aLockedFileLoadsNothingAndOverwritesNothing() throws {
        let url = temporaryURL("locked-archive")
        let seeded = TodayStore(storageURL: url, calendar: utcCalendar)
        seeded.recordWeight(184.4, on: referenceDay)
        seeded.flushPersistence()
        let original = try Data(contentsOf: url)

        try makeUnreadable(url)
        let locked = TodayStore(storageURL: url, calendar: utcCalendar)

        #expect(locked.weights.isEmpty)
        #expect(!locked.hasReliableData)
        #expect(locked.dataRecoveryMessage != nil)

        // Anything logged now must stay in memory only. Writing it would replace a
        // real archive with a one-entry one.
        locked.recordWeight(183.2, on: referenceDay.addingTimeInterval(86_400))
        locked.flushPersistence()

        try makeReadable(url)
        #expect(try Data(contentsOf: url) == original)
    }

    @Test func whatWasLoggedWhileLockedSurvivesTheReloadAndReachesDisk() throws {
        let url = temporaryURL("locked-then-unlocked")
        let seeded = TodayStore(storageURL: url, calendar: utcCalendar)
        seeded.recordWeight(184.4, on: referenceDay)
        seeded.flushPersistence()

        try makeUnreadable(url)
        let store = TodayStore(storageURL: url, calendar: utcCalendar)
        store.recordWeight(183.2, on: referenceDay.addingTimeInterval(86_400))
        #expect(store.weights.count == 1)

        try makeReadable(url)
        store.reloadIfUnreadable()

        #expect(store.hasReliableData)
        #expect(store.dataRecoveryMessage == nil)
        #expect(store.weights.count == 2)
        #expect(store.weights.contains { $0.pounds == 184.4 })
        #expect(store.weights.contains { $0.pounds == 183.2 })

        // The retry has to actually write, not just fix memory.
        let reopened = TodayStore(storageURL: url, calendar: utcCalendar)
        #expect(reopened.weights.count == 2)
    }

    @Test func anUnreadableStoreIsNeverPublishedToTheWidget() throws {
        let url = temporaryURL("widget-guard")
        let seeded = TodayStore(storageURL: url, calendar: utcCalendar)
        seeded.recordWeight(184.4, on: referenceDay)
        seeded.flushPersistence()

        try makeUnreadable(url)
        let locked = TodayStore(storageURL: url, calendar: utcCalendar)
        #expect(TodayWidgetPublisher.makeSnapshot(store: locked, plan: nil, runs: [], catalog: ExerciseCatalog()) == nil)

        try makeReadable(url)
        let readable = TodayStore(storageURL: url, calendar: utcCalendar)
        #expect(TodayWidgetPublisher.makeSnapshot(store: readable, plan: nil, runs: [], catalog: ExerciseCatalog()) != nil)
    }

    @Test func oneUnreadableEntryDoesNotTakeTheWholeArchiveWithIt() throws {
        let url = temporaryURL("partial-archive")
        let payload = """
        {"goalWeight":178,"weights":[\
        {"id":"\(UUID().uuidString)","date":774316800,"pounds":184.4},\
        {"id":"not-a-uuid","date":774403200,"pounds":183.9},\
        {"id":"\(UUID().uuidString)","date":774489600,"pounds":183.5}\
        ],"workouts":[\
        \(workoutJSON(kind: "upper", startedAt: 774316800)),\
        \(workoutJSON(kind: "telekinesis", startedAt: 774403200)),\
        \(workoutJSON(kind: "lower", startedAt: 774489600))\
        ]}
        """
        let original = Data(payload.utf8)
        try original.write(to: url, options: .atomic)

        let store = TodayStore(storageURL: url, calendar: utcCalendar)

        #expect(store.weights.count == 2)
        #expect(store.workouts.count == 2)
        #expect(store.goalWeight == 178)
        #expect(store.dataRecoveryMessage != nil)

        // The skipped rows may be perfectly good data a newer build wrote, so the
        // original bytes have to outlive the next save.
        let salvaged = quarantinedCopies(for: url)
        #expect(salvaged.count == 1)
        #expect(try Data(contentsOf: try #require(salvaged.first)) == original)
    }

    @Test func anUnrecoverableFileIsCopiedAsideBeforeAnythingOverwritesIt() throws {
        let url = temporaryURL("unrecoverable")
        let original = Data("{ this is not json".utf8)
        try original.write(to: url, options: .atomic)

        let store = TodayStore(storageURL: url, calendar: utcCalendar)
        #expect(store.weights.isEmpty)
        #expect(store.dataRecoveryMessage != nil)

        store.recordWeight(184.4, on: referenceDay)
        store.flushPersistence()

        let salvaged = quarantinedCopies(for: url)
        #expect(salvaged.count == 1)
        #expect(try Data(contentsOf: try #require(salvaged.first)) == original)
        // ...and the store really did move on and save the new value.
        #expect(TodayStore(storageURL: url, calendar: utcCalendar).weights.count == 1)
    }

    @Test func anArchiveWrittenByTheOlderBuildStillLoadsExactly() throws {
        let url = temporaryURL("legacy-format")
        // Byte-for-byte the shape the previous encoder produced: default date
        // strategy (seconds since 2001), no `healthKitID` on older weights, and an
        // in-progress workout parked in `activeWorkout`.
        let payload = """
        {"goalWeight":175,"weights":[\
        {"id":"\(UUID().uuidString)","date":774316800,"pounds":184.4},\
        {"id":"\(UUID().uuidString)","date":774403200,"pounds":183.9,"healthKitID":"\(UUID().uuidString)"}\
        ],"workouts":[\(workoutJSON(kind: "upper", startedAt: 774316800))],\
        "activeWorkout":\(workoutJSON(kind: "lower", startedAt: 774489600, ended: false))}
        """
        try Data(payload.utf8).write(to: url, options: .atomic)

        let store = TodayStore(storageURL: url, calendar: utcCalendar)

        #expect(store.weights.count == 2)
        #expect(store.workouts.count == 1)
        #expect(store.workouts[0].kind == .upper)
        #expect(store.workouts[0].exercises[0].sets[0].weight == 235)
        #expect(store.activeWorkout?.kind == .lower)
        #expect(store.goalWeight == 175)
        #expect(store.dataRecoveryMessage == nil)
        #expect(store.hasReliableData)
    }

    @Test func aPayloadMissingEveryOptionalKeyStillLoads() throws {
        let url = temporaryURL("minimal-format")
        try Data("{}".utf8).write(to: url, options: .atomic)

        let store = TodayStore(storageURL: url, calendar: utcCalendar)

        #expect(store.weights.isEmpty)
        #expect(store.workouts.isEmpty)
        #expect(store.activeWorkout == nil)
        #expect(store.goalWeight == 175)
        #expect(store.hasReliableData)
    }

    @Test func aRoundTripThroughTheCurrentEncoderIsUnchanged() throws {
        let url = temporaryURL("round-trip")
        let store = TodayStore(storageURL: url, calendar: utcCalendar)
        store.recordWeight(184.4, on: referenceDay)
        store.goalWeight = 172
        store.flushPersistence()

        let decoded = try JSONDecoder().decode(StoredTodayData.self, from: Data(contentsOf: url))

        #expect(decoded.weights.count == 1)
        #expect(decoded.goalWeight == 172)
        #expect(decoded.unreadableEntryCount == 0)
        // The extra bookkeeping field must never be written to disk.
        let raw = try #require(
            try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        )
        #expect(raw["unreadableEntryCount"] == nil)
    }

    @Test func repeatedHealthKitMergesDoNotResendIdenticalData() {
        let spy = RecordingCoachSync()
        let store = TodayStore(
            storageURL: temporaryURL("merge-churn"),
            calendar: utcCalendar,
            syncService: spy
        )
        let sampleID = UUID()
        let entries = [WeightEntry(date: referenceDay, pounds: 184.4, healthKitID: sampleID)]

        store.mergeHealthWeights(entries)
        // HealthKit hands back a freshly built value with a new local id every fetch.
        store.mergeHealthWeights([
            WeightEntry(date: referenceDay, pounds: 184.4, healthKitID: sampleID),
        ])

        #expect(store.weights.count == 1)
        #expect(spy.scheduledSnapshots.count == 1)

        store.mergeHealthWeights([
            WeightEntry(date: referenceDay, pounds: 183.9, healthKitID: sampleID),
        ])
        #expect(spy.scheduledSnapshots.count == 2)
    }

    @Test func aUserCorrectionWinsOverLaterExternalHealthRefreshes() {
        let store = TodayStore(storageURL: temporaryURL("manual-weight-priority"), calendar: utcCalendar)
        let externalID = UUID()
        store.mergeHealthWeights([
            WeightEntry(date: referenceDay, pounds: 184.4, healthKitID: externalID),
        ])

        store.recordWeight(183.8, on: referenceDay.addingTimeInterval(600))
        store.mergeHealthWeights([
            WeightEntry(date: referenceDay, pounds: 184.4, healthKitID: externalID),
        ])

        #expect(store.weights.count == 1)
        #expect(store.weights[0].pounds == 183.8)
        #expect(store.weights[0].isUserEntered == true)
    }

    // MARK: - helpers

    private var referenceDay: Date { Date(timeIntervalSince1970: 1_753_075_200) }

    private func workoutJSON(kind: String, startedAt: Double, ended: Bool = true) -> String {
        let endedAt = ended ? ",\"endedAt\":\(startedAt + 3600)" : ""
        return """
        {"id":"\(UUID().uuidString)","kind":"\(kind)","startedAt":\(startedAt)\(endedAt),\
        "exercises":[{"id":"\(UUID().uuidString)","exerciseID":"machine-chest-fly",\
        "sets":[{"id":"\(UUID().uuidString)","weight":235,"reps":5,"isComplete":true}]}]}
        """
    }

    /// Stands in for `.completeFileProtection` on a locked phone: the file is still
    /// there, `fileExists` still says yes, and the bytes cannot be read.
    private func makeUnreadable(_ url: URL) throws {
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o000))],
            ofItemAtPath: url.path
        )
    }

    private func makeReadable(_ url: URL) throws {
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o644))],
            ofItemAtPath: url.path
        )
    }

    private func quarantinedCopies(for url: URL) -> [URL] {
        let directory = url.deletingLastPathComponent()
        let stem = url.deletingPathExtension().lastPathComponent
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )) ?? []
        return contents.filter {
            $0.lastPathComponent.hasPrefix("\(stem).corrupt-")
                || $0.lastPathComponent.hasPrefix("\(stem).partial-")
        }
    }

    private func temporaryURL(_ name: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("TodaySafety-\(name)-\(UUID().uuidString).json")
    }

    private var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }
}

@MainActor
private final class RecordingCoachSync: CoachSyncing {
    private(set) var scheduledSnapshots: [StoredTodayData] = []

    func scheduleSync(snapshot: StoredTodayData, catalog: ExerciseCatalog) {
        scheduledSnapshots.append(snapshot)
    }

    func sync(snapshot: StoredTodayData, catalog: ExerciseCatalog) async {}
}

/// Serialized: these share one intercepting URL protocol, and the in-flight tests
/// hold it open on purpose.
@MainActor
@Suite(.serialized, .timeLimit(.minutes(1)))
struct CoachSyncReliabilityTests {
    @Test func aSecondChangeDuringAnUploadIsQueuedRatherThanDropped() async throws {
        let service = try makeService()
        let catalog = ExerciseCatalog(cacheURL: temporaryURL("queued-catalog"))
        let (started, startedContinuation) = AsyncStream.makeStream(of: Void.self)
        let release = DispatchSemaphore(value: 0)
        syncStub.reset()
        // Timeouts everywhere so a regression fails the test instead of wedging CI.
        syncStub.setGate {
            startedContinuation.yield()
            _ = release.wait(timeout: .now() + 20)
        }

        async let inFlight: Void = service.sync(snapshot: StoredTodayData(), catalog: catalog)
        #expect(await signalArrives(on: started))

        // Arrives while the first batch is on the wire. It used to be discarded, and
        // the finishing upload then cleared the pending flag on its behalf.
        await service.sync(snapshot: StoredTodayData(goalWeight: 170), catalog: catalog)
        syncStub.setGate(nil)
        release.signal()
        await inFlight

        #expect(syncStub.requestCount == 2)
        #expect(!service.hasPendingChanges)
    }

    @Test func aChangeMadeMidUploadIsNotReportedAsSynced() async throws {
        let service = try makeService()
        let catalog = ExerciseCatalog(cacheURL: temporaryURL("pending-catalog"))
        let (started, startedContinuation) = AsyncStream.makeStream(of: Void.self)
        let release = DispatchSemaphore(value: 0)
        syncStub.reset()
        // Timeouts everywhere so a regression fails the test instead of wedging CI.
        syncStub.setGate {
            startedContinuation.yield()
            _ = release.wait(timeout: .now() + 20)
        }

        async let inFlight: Void = service.sync(snapshot: StoredTodayData(), catalog: catalog)
        #expect(await signalArrives(on: started))
        service.markPending()
        syncStub.setGate(nil)
        release.signal()
        await inFlight

        #expect(service.hasPendingChanges)
        #expect(service.state != .synced(service.lastSyncedAt ?? .distantPast))
    }

    @Test func aSuccessfulUploadClearsPending() async throws {
        let service = try makeService()
        let catalog = ExerciseCatalog(cacheURL: temporaryURL("clean-catalog"))
        syncStub.reset()

        await service.sync(snapshot: StoredTodayData(), catalog: catalog)

        #expect(syncStub.requestCount == 1)
        #expect(!service.hasPendingChanges)
        #expect(service.lastSyncedAt != nil)
    }

    @Test func uploadedPrivateDataAuthenticatesItsEnvelopeAndNeverPublishesWeight() async throws {
        let service = try makeService()
        let catalog = ExerciseCatalog(cacheURL: temporaryURL("authenticated-catalog"))
        syncStub.reset()
        let snapshot = StoredTodayData(
            weights: [WeightEntry(date: Date(), pounds: 184.4, healthKitID: nil)],
            goalWeight: 175
        )

        await service.sync(snapshot: snapshot, catalog: catalog)

        let body = try #require(syncStub.latestBody)
        let object = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(object["schemaVersion"] as? Int == 2)
        #expect(object["publicWeight"] == nil)
        let batchID = try #require(object["batchId"] as? String)
        let deviceID = try #require(object["deviceId"] as? String)
        let createdAt = try #require(object["createdAt"] as? String)
        let encryption = try #require(object["encryption"] as? [String: Any])
        let keyID = try #require(encryption["keyId"] as? String)
        let nonceString = try #require(encryption["nonce"] as? String)
        let ciphertextString = try #require(encryption["ciphertext"] as? String)
        let tagString = try #require(encryption["tag"] as? String)
        let nonceData = try #require(Data(base64Encoded: nonceString))
        let ciphertext = try #require(Data(base64Encoded: ciphertextString))
        let tag = try #require(Data(base64Encoded: tagString))
        let box = try AES.GCM.SealedBox(
            nonce: AES.GCM.Nonce(data: nonceData),
            ciphertext: ciphertext,
            tag: tag
        )
        let plaintext = try AES.GCM.open(
            box,
            using: SymmetricKey(data: Data(repeating: 7, count: 32)),
            authenticating: CoachSyncService.authenticatedMetadata(
                batchID: batchID,
                deviceID: deviceID,
                createdAt: createdAt,
                keyID: keyID
            )
        )
        let privateObject = try #require(JSONSerialization.jsonObject(with: plaintext) as? [String: Any])
        #expect(privateObject["schemaVersion"] as? Int == 2)
    }

    @Test func aServerErrorIsRetriedAndARejectionIsNot() async throws {
        let catalog = ExerciseCatalog(cacheURL: temporaryURL("retry-catalog"))

        syncStub.reset()
        syncStub.setStatus(503)
        let retrying = try makeService(retryDelays: [.zero, .zero])
        await retrying.sync(snapshot: StoredTodayData(), catalog: catalog)
        #expect(syncStub.requestCount == 3)
        #expect(retrying.hasPendingChanges)

        syncStub.reset()
        syncStub.setStatus(401)
        let rejected = try makeService(retryDelays: [.zero, .zero])
        await rejected.sync(snapshot: StoredTodayData(), catalog: catalog)
        #expect(syncStub.requestCount == 1)
        #expect(rejected.hasPendingChanges)
    }

    @Test func retryClassificationSeparatesFlakyFromFinal() {
        #expect(CoachSyncService.isTransient(URLError(.notConnectedToInternet)))
        #expect(CoachSyncService.isTransient(URLError(.timedOut)))
        #expect(CoachSyncService.isTransient(URLError(.networkConnectionLost)))
        #expect(!CoachSyncService.isTransient(URLError(.userAuthenticationRequired)))
        #expect(!CoachSyncService.isTransient(URLError(.cancelled)))

        #expect(CoachSyncService.isRetryableStatus(503))
        #expect(CoachSyncService.isRetryableStatus(429))
        #expect(!CoachSyncService.isRetryableStatus(401))
        #expect(!CoachSyncService.isRetryableStatus(200))
    }

    @Test func aPermanentlyStalledSyncDoesNotClaimItWillRetryWhenOnline() {
        // A snapshot that outgrew the batch limit never fixes itself, so it must not
        // borrow the wording used for a temporary outage.
        let tooLarge = CoachSyncService.message(forStatus: 413)
        let rejected = CoachSyncService.message(forStatus: 401)

        #expect(!tooLarge.localizedCaseInsensitiveContains("retry"))
        #expect(rejected.localizedCaseInsensitiveContains("reconnect"))
        #expect(CoachSyncService.message(forStatus: 500).localizedCaseInsensitiveContains("retry"))
    }

    @Test func aKeychainRefusalIsNotReportedAsABadPairingCode() throws {
        // The regression that cost a week: the keychain wrapper threw
        // .invalidPairingCode when the STORE failed, so an unsigned CI build made a
        // perfectly good code look malformed and pointed the diagnosis at the guards.
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SyncStubProtocol.self]
        let service = CoachSyncService(
            session: URLSession(configuration: configuration),
            defaults: try #require(UserDefaults(suiteName: "coach-sync-tests-\(UUID().uuidString)")),
            keychain: RefusingSecretStore(),
            retryDelays: []
        )

        #expect(throws: CoachSyncError.secretStoreUnavailable(errSecMissingEntitlement)) {
            try service.connect(pairingCode: Self.pairingCode)
        }
        // And the connection must not be left half-made when the secret never landed.
        #expect(!service.isConnected)
    }

    @Test func dayKeysFollowTheDeviceTimeZoneRatherThanTheLaunchTimeZone() {
        let evening = Date(timeIntervalSince1970: 1_753_146_000) // 2025-07-22 01:00 UTC
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0)!
        var losAngeles = Calendar(identifier: .gregorian)
        losAngeles.timeZone = TimeZone(identifier: "America/Los_Angeles")!

        #expect(CoachSyncService.dayKey(for: evening, calendar: utc) == "2025-07-22")
        #expect(CoachSyncService.dayKey(for: evening, calendar: losAngeles) == "2025-07-21")
    }

    private func makeService(retryDelays: [Duration] = []) throws -> CoachSyncService {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SyncStubProtocol.self]
        let service = CoachSyncService(
            session: URLSession(configuration: configuration),
            defaults: try #require(UserDefaults(suiteName: "coach-sync-tests-\(UUID().uuidString)")),
            keychain: InMemorySecretStore(),
            retryDelays: retryDelays
        )
        try service.connect(pairingCode: Self.pairingCode)
        return service
    }

    private func temporaryURL(_ name: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("TodaySync-\(name)-\(UUID().uuidString).json")
    }

    private static let pairingCode: String = {
        let pairing: [String: Any] = [
            "schemaVersion": 1,
            "endpoint": "https://rohansingh04.com/api/fitness/private-sync",
            "writeToken": String(repeating: "t", count: 40),
            "encryptionKey": Data(repeating: 7, count: 32).base64EncodedString(),
            "keyId": "test-key",
        ]
        let data = try! JSONSerialization.data(withJSONObject: pairing)
        return data.base64EncodedString()
    }()
}

@MainActor
struct WeightReminderTests {
    @Test func loggingAWeightCancelsTheWakeNudgeToo() {
        let date = Date(timeIntervalSince1970: 1_753_075_200)
        let key = NotificationManager.dayKey(for: date)
        let ids = NotificationManager.weightReminderIDs(for: date)

        #expect(ids.contains("weightReminder.morning.\(key)"))
        #expect(ids.contains("weightReminder.lunch.\(key)"))
        // The one that used to survive and buzz five minutes after you already
        // stepped off the scale.
        #expect(ids.contains("weightReminder.wake.\(key)"))
    }

    @Test func theReminderScheduleLeavesRoomUnderTheSystemLimit() {
        let days = NotificationManager.reminderDayCount(requested: 30)
        let scheduled = days * NotificationManager.remindersPerDay

        #expect(days >= 7)
        // Leave headroom for the daily recap and the wake nudge; iOS drops silently
        // once 64 pending requests are queued.
        #expect(scheduled <= NotificationManager.systemPendingNotificationLimit - 30)
        #expect(NotificationManager.reminderDayCount(requested: 0) == 1)
    }

    @Test func reminderDayKeysFollowTheDeviceTimeZone() {
        let evening = Date(timeIntervalSince1970: 1_753_146_000)
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0)!
        var tokyo = Calendar(identifier: .gregorian)
        tokyo.timeZone = TimeZone(identifier: "Asia/Tokyo")!

        #expect(NotificationManager.dayKey(for: evening, calendar: utc) == "2025-07-22")
        #expect(NotificationManager.dayKey(for: evening, calendar: tokyo) == "2025-07-22")
        #expect(
            NotificationManager.dayKey(for: evening.addingTimeInterval(-7_200), calendar: tokyo)
                == "2025-07-22"
        )
        #expect(
            NotificationManager.dayKey(for: evening.addingTimeInterval(-7_200), calendar: utc)
                == "2025-07-21"
        )
    }
}

// MARK: - Network stub

/// Intercepts every request made through the test session, so no test can reach
/// the real coach endpoint even though the allowlist forces the production URL.
final class SyncStubProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let body = Self.bodyData(from: request)
        syncStub.record(body)
        syncStub.runGate()

        guard let url = request.url,
              let response = HTTPURLResponse(
                url: url,
                statusCode: syncStub.status,
                httpVersion: nil,
                headerFields: nil
              ) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        let batchId = Self.batchID(from: body) ?? ""
        let payload = Data(#"{"ok":true,"batchId":"\#(batchId)"}"#.utf8)
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: payload)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func bodyData(from request: URLRequest) -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let size = 4_096
        var buffer = [UInt8](repeating: 0, count: size)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: size)
            guard read > 0 else { break }
            data.append(buffer, count: read)
        }
        return data
    }

    private static func batchID(from body: Data) -> String? {
        (try? JSONSerialization.jsonObject(with: body) as? [String: Any])??["batchId"] as? String
    }
}

private func signalArrives(
    on stream: AsyncStream<Void>,
    timeout: Duration = .seconds(20)
) async -> Bool {
    await withTaskGroup(of: Bool.self) { group in
        group.addTask {
            var iterator = stream.makeAsyncIterator()
            return await iterator.next() != nil
        }
        group.addTask {
            try? await Task.sleep(for: timeout)
            return false
        }

        let result = await group.next() ?? false
        group.cancelAll()
        return result
    }
}

/// Keeps the pairing secret in memory instead of the system keychain.
///
/// These four tests failed only on CI for a week. CI builds with
/// `CODE_SIGNING_ALLOWED=NO`, so the simulator app carries no
/// `application-identifier` entitlement and `SecItemAdd` returns
/// errSecMissingEntitlement (-34018). Locally the app is signed, the keychain works,
/// and everything passed — which is exactly why inspecting the guard conditions in
/// `connect(pairingCode:)` never found anything: the pairing code was always valid.
///
/// A unit test for sync bookkeeping has no business depending on whether the host
/// process holds a keychain entitlement, so it no longer does.
final class InMemorySecretStore: CoachSyncSecretStore {
    private var storage: [String: Data] = [:]

    func save(_ data: Data, account: String) throws { storage[account] = data }
    func load(_ account: String) -> Data? { storage[account] }
    func delete(_ account: String) { storage[account] = nil }
}

/// Reproduces exactly what an unsigned build gets back from the keychain.
final class RefusingSecretStore: CoachSyncSecretStore {
    func save(_ data: Data, account: String) throws {
        throw CoachSyncError.secretStoreUnavailable(errSecMissingEntitlement)
    }
    func load(_ account: String) -> Data? { nil }
    func delete(_ account: String) {}
}

let syncStub = SyncStubState()

final class SyncStubState: @unchecked Sendable {
    private let lock = NSLock()
    private var bodies: [Data] = []
    private var gate: (() -> Void)?
    private var statusCode = 200

    var requestCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return bodies.count
    }

    var status: Int {
        lock.lock()
        defer { lock.unlock() }
        return statusCode
    }

    var latestBody: Data? {
        lock.lock()
        defer { lock.unlock() }
        return bodies.last
    }

    func reset() {
        lock.lock()
        defer { lock.unlock() }
        bodies = []
        gate = nil
        statusCode = 200
    }

    func setStatus(_ value: Int) {
        lock.lock()
        defer { lock.unlock() }
        statusCode = value
    }

    func setGate(_ value: (() -> Void)?) {
        lock.lock()
        defer { lock.unlock() }
        gate = value
    }

    func record(_ body: Data) {
        lock.lock()
        defer { lock.unlock() }
        bodies.append(body)
    }

    func runGate() {
        lock.lock()
        let current = gate
        lock.unlock()
        current?()
    }
}
