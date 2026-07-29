import Combine
import CryptoKit
import Foundation
import Security

enum CoachSyncState: Equatable {
    case notConnected
    case ready
    case syncing
    case synced(Date)
    case failed(String)

    var title: String {
        switch self {
        case .notConnected: "Not connected"
        case .ready: "Ready to sync"
        case .syncing: "Syncing"
        case .synced: "Up to date"
        case .failed: "Needs attention"
        }
    }

    var symbol: String {
        switch self {
        case .notConnected: "link.badge.plus"
        case .ready: "arrow.triangle.2.circlepath"
        case .syncing: "arrow.triangle.2.circlepath"
        case .synced: "checkmark.icloud.fill"
        case .failed: "exclamationmark.icloud.fill"
        }
    }
}

struct CoachSyncPairing: Codable, Equatable {
    let schemaVersion: Int
    let endpoint: String
    let writeToken: String
    let encryptionKey: String
    let keyId: String
}

@MainActor
protocol CoachSyncing: AnyObject {
    func scheduleSync(snapshot: StoredTodayData, catalog: ExerciseCatalog)
    func sync(snapshot: StoredTodayData, catalog: ExerciseCatalog) async
}

private struct PrivateFitnessSnapshot: Encodable {
    let schemaVersion = 1
    let generatedAt: Date
    let data: StoredTodayData
    let exerciseDefinitions: [ExerciseDefinition]
}

private struct PublicStrengthSession: Encodable {
    let id: String
    let date: String
    let kind: String
    let durationMinutes: Int
    let workingSets: Int
    let muscleGroups: [String]
    let updatedAt: String
}

private struct PublicWeightTrend: Encodable {
    let asOf: String
    let currentPounds: Double
    let goalPounds: Double
    let sevenDayAverage: Double
    let change28Days: Double?
    let daysLogged28: Int
}

private struct EncryptedPayload: Encodable {
    let algorithm = "AES-256-GCM"
    let keyId: String
    let nonce: String
    let ciphertext: String
    let tag: String
}

private struct FitnessSyncBatch: Encodable {
    let schemaVersion = 1
    let batchId: String
    let deviceId: String
    let createdAt: String
    let encryption: EncryptedPayload
    let publicStrength: [PublicStrengthSession]
    let publicWeight: PublicWeightTrend?
}

private struct FitnessSyncResponse: Decodable {
    let ok: Bool
    let batchId: String
}

@MainActor
final class CoachSyncService: ObservableObject, CoachSyncing {
    static let shared = CoachSyncService()

    @Published private(set) var state: CoachSyncState
    @Published private(set) var lastSyncedAt: Date?
    @Published private(set) var hasPendingChanges: Bool
    @Published private(set) var sharesWeightTrend: Bool

    private let session: URLSession
    private let defaults: UserDefaults
    private let keychain: CoachSyncSecretStore
    private let retryDelays: [Duration]
    private var pairing: CoachSyncPairing?
    private var debounceTask: Task<Void, Never>?

    /// Bumped every time local data changes. A finished upload may only clear the
    /// pending flag for the generation it actually carried.
    private var dataGeneration = 0
    private var isSyncing = false
    private var queued: (snapshot: StoredTodayData, catalog: ExerciseCatalog)?

    private static let pairingAccount = "coach-sync-pairing-v1"
    private static let lastSyncedKey = "coachSync.lastSyncedAt"
    private static let pendingKey = "coachSync.hasPendingChanges"
    private static let deviceKey = "coachSync.deviceId"
    private static let sharesWeightKey = "coachSync.sharesWeightTrend"
    private static let maximumCoalescedPasses = 3

    init(
        session: URLSession = .shared,
        defaults: UserDefaults = .standard,
        keychain: CoachSyncSecretStore = CoachSyncKeychain(),
        retryDelays: [Duration] = [.seconds(2), .seconds(8)]
    ) {
        self.session = session
        self.defaults = defaults
        self.keychain = keychain
        self.retryDelays = retryDelays
        lastSyncedAt = defaults.object(forKey: Self.lastSyncedKey) as? Date
        hasPendingChanges = defaults.bool(forKey: Self.pendingKey)
        sharesWeightTrend = defaults.bool(forKey: Self.sharesWeightKey)
        pairing = keychain.load(Self.pairingAccount).flatMap {
            try? JSONDecoder().decode(CoachSyncPairing.self, from: $0)
        }
        state = pairing == nil ? .notConnected : .ready
        if let lastSyncedAt, pairing != nil, !hasPendingChanges {
            state = .synced(lastSyncedAt)
        }
    }

    var isConnected: Bool { pairing != nil }

    func markPending() {
        guard pairing != nil else { return }
        dataGeneration &+= 1
        hasPendingChanges = true
        defaults.set(true, forKey: Self.pendingKey)
        if isSyncing { return }
        state = .ready
    }

    func connect(pairingCode: String) throws {
        let trimmed = pairingCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count <= 4_096,
              let data = Self.decodeBase64URL(trimmed),
              let value = try? JSONDecoder().decode(CoachSyncPairing.self, from: data),
              value.schemaVersion == 1,
              let url = URL(string: value.endpoint),
              Self.isAllowedEndpoint(url),
              value.writeToken.count >= 32,
              Data(base64Encoded: value.encryptionKey)?.count == 32,
              !value.keyId.isEmpty,
              value.keyId.count <= 80 else {
            throw CoachSyncError.invalidPairingCode
        }
        let encoded = try JSONEncoder().encode(value)
        try keychain.save(encoded, account: Self.pairingAccount)
        pairing = value
        hasPendingChanges = true
        defaults.set(true, forKey: Self.pendingKey)
        state = .ready
    }

    func setWeightTrendSharing(_ enabled: Bool) {
        guard sharesWeightTrend != enabled else { return }
        sharesWeightTrend = enabled
        defaults.set(enabled, forKey: Self.sharesWeightKey)
        markPending()
    }

    func disconnect() {
        debounceTask?.cancel()
        debounceTask = nil
        queued = nil
        keychain.delete(Self.pairingAccount)
        pairing = nil
        hasPendingChanges = false
        lastSyncedAt = nil
        defaults.removeObject(forKey: Self.pendingKey)
        defaults.removeObject(forKey: Self.lastSyncedKey)
        defaults.removeObject(forKey: Self.sharesWeightKey)
        sharesWeightTrend = false
        state = .notConnected
    }

    func scheduleSync(snapshot: StoredTodayData, catalog: ExerciseCatalog) {
        markPending()
        guard pairing != nil else { return }
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled, let self else { return }
            // Past the debounce window. Drop the handle so a later schedule cannot
            // cancel an upload that is already on the wire: that used to abort the
            // request and surface it as "Needs attention".
            self.debounceTask = nil
            await self.sync(snapshot: snapshot, catalog: catalog)
        }
    }

    func sync(snapshot: StoredTodayData, catalog: ExerciseCatalog) async {
        guard pairing != nil else {
            state = .notConnected
            return
        }

        // A sync arriving while one is in flight used to be dropped on the floor
        // while the in-flight one went on to clear `hasPendingChanges`. The newer
        // lift or weight was then never sent, and the app still said "Up to date"
        // until some unrelated change happened to trigger another sync. Queue it.
        guard !isSyncing else {
            queued = (snapshot, catalog)
            markPending()
            return
        }

        isSyncing = true
        defer { isSyncing = false }
        state = .syncing

        var work: (snapshot: StoredTodayData, catalog: ExerciseCatalog)? = (snapshot, catalog)
        var passes = 0
        while let job = work, passes < Self.maximumCoalescedPasses {
            passes += 1
            queued = nil
            let generation = dataGeneration

            switch await attemptUpload(snapshot: job.snapshot, catalog: job.catalog) {
            case .cancelled:
                state = pairing == nil ? .notConnected : .ready
                return
            case .failed(let message):
                hasPendingChanges = true
                defaults.set(true, forKey: Self.pendingKey)
                state = .failed(message)
                return
            case .succeeded:
                if let next = queued {
                    work = next
                    continue
                }
                guard dataGeneration == generation else {
                    // Something changed mid-upload without handing us a snapshot
                    // (a sharing toggle, say). Stay pending so the next foreground
                    // pass sends it rather than claiming to be up to date.
                    state = .ready
                    return
                }
                let now = Date()
                lastSyncedAt = now
                hasPendingChanges = false
                defaults.set(now, forKey: Self.lastSyncedKey)
                defaults.set(false, forKey: Self.pendingKey)
                state = .synced(now)
                return
            }
        }

        // Out of coalescing passes with data still newer than the server.
        state = .ready
    }

    private enum UploadOutcome {
        case succeeded
        case cancelled
        case failed(String)
    }

    private func attemptUpload(
        snapshot: StoredTodayData,
        catalog: ExerciseCatalog
    ) async -> UploadOutcome {
        guard let pairing else { return .cancelled }

        let batch: FitnessSyncBatch
        do {
            batch = try makeBatch(snapshot: snapshot, catalog: catalog, pairing: pairing)
        } catch CoachSyncError.snapshotTooLarge {
            // This one never fixes itself: the archive only grows. Saying "will
            // retry when online" would hide a permanently stalled coach copy.
            return .failed("Your private history has outgrown a single sync. Everything is safe on this phone, but the coach copy is paused until the limit is raised.")
        } catch {
            return .failed("Today could not prepare this update. Reconnect in Coach Sync to refresh the connection code.")
        }

        guard let endpoint = URL(string: pairing.endpoint), Self.isAllowedEndpoint(endpoint) else {
            return .failed("The saved coach address is no longer allowed. Reconnect with a fresh code.")
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("Bearer \(pairing.writeToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        do {
            request.httpBody = try Self.encoder.encode(batch)
        } catch {
            return .failed("Today could not prepare this update.")
        }

        // The same batch id is reused across attempts so a retry after a dropped
        // response is a repeat, not a second entry.
        for attempt in 0...retryDelays.count {
            do {
                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse else {
                    return .failed(Self.offlineMessage)
                }
                if Self.isRetryableStatus(http.statusCode) {
                    guard attempt < retryDelays.count else {
                        return .failed("The coach server is not answering right now. Saved on this phone and it will retry.")
                    }
                    guard await backOff(retryDelays[attempt]) else { return .cancelled }
                    continue
                }
                guard http.statusCode == 200 else {
                    return .failed(Self.message(forStatus: http.statusCode))
                }
                guard let receipt = try? JSONDecoder().decode(FitnessSyncResponse.self, from: data),
                      receipt.ok,
                      receipt.batchId == batch.batchId else {
                    return .failed("The coach server did not confirm this update, so it stayed on this phone.")
                }
                return .succeeded
            } catch is CancellationError {
                return .cancelled
            } catch let error as URLError where error.code == .cancelled {
                return .cancelled
            } catch let error as URLError where Self.isTransient(error) {
                guard attempt < retryDelays.count else { return .failed(Self.offlineMessage) }
                guard await backOff(retryDelays[attempt]) else { return .cancelled }
            } catch {
                return .failed(Self.offlineMessage)
            }
        }
        return .failed(Self.offlineMessage)
    }

    /// Returns false when the wait was cancelled.
    private func backOff(_ duration: Duration) async -> Bool {
        guard duration > .zero else { return !Task.isCancelled }
        do {
            try await Task.sleep(for: duration)
            return true
        } catch {
            return false
        }
    }

    private static let offlineMessage = "Saved on this phone. Sync will retry when the app is online."

    static func isTransient(_ error: URLError) -> Bool {
        switch error.code {
        case .notConnectedToInternet,
             .networkConnectionLost,
             .timedOut,
             .cannotConnectToHost,
             .cannotFindHost,
             .dnsLookupFailed,
             .internationalRoamingOff,
             .callIsActive,
             .dataNotAllowed,
             .secureConnectionFailed:
            return true
        default:
            return false
        }
    }

    static func isRetryableStatus(_ status: Int) -> Bool {
        status == 408 || status == 429 || (500...599).contains(status)
    }

    static func message(forStatus status: Int) -> String {
        switch status {
        case 401, 403:
            "The coach server rejected this phone's connection code. Reconnect in Coach Sync."
        case 413:
            "Your private history has outgrown a single sync. Everything is safe on this phone."
        case 400...499:
            "The coach server rejected this update (\(status)). It is still saved on this phone."
        default:
            "The coach server answered unexpectedly (\(status)). Saved on this phone and it will retry."
        }
    }

    private func makeBatch(
        snapshot: StoredTodayData,
        catalog: ExerciseCatalog,
        pairing: CoachSyncPairing
    ) throws -> FitnessSyncBatch {
        guard let rawKey = Data(base64Encoded: pairing.encryptionKey), rawKey.count == 32 else {
            throw CoachSyncError.invalidPairingCode
        }
        let usedExerciseIDs = Set(
            (snapshot.workouts + [snapshot.activeWorkout].compactMap { $0 })
                .flatMap(\.exercises)
                .map(\.exerciseID)
        )
        let definitions = usedExerciseIDs.compactMap(catalog.exercise(id:))
        let privateData = try Self.encoder.encode(
            PrivateFitnessSnapshot(
                generatedAt: Date(),
                data: snapshot,
                exerciseDefinitions: definitions
            )
        )
        guard privateData.count <= 900_000 else { throw CoachSyncError.snapshotTooLarge }
        let sealed = try AES.GCM.seal(privateData, using: SymmetricKey(data: rawKey))
        let nonce = sealed.nonce.withUnsafeBytes { Data($0) }
        let now = Self.isoFormatter.string(from: Date())
        return FitnessSyncBatch(
            batchId: "batch_\(UUID().uuidString.lowercased())",
            deviceId: deviceID,
            createdAt: now,
            encryption: EncryptedPayload(
                keyId: pairing.keyId,
                nonce: nonce.base64EncodedString(),
                ciphertext: sealed.ciphertext.base64EncodedString(),
                tag: sealed.tag.base64EncodedString()
            ),
            publicStrength: publicStrength(snapshot.workouts, catalog: catalog),
            publicWeight: sharesWeightTrend ? publicWeight(snapshot) : nil
        )
    }

    private func publicWeight(_ snapshot: StoredTodayData) -> PublicWeightTrend? {
        guard let latest = snapshot.weights.max(by: { $0.date < $1.date }) else { return nil }
        let calendar = Calendar.current
        let latestDay = calendar.startOfDay(for: latest.date)
        let sevenDayStart = calendar.date(byAdding: .day, value: -6, to: latestDay) ?? latestDay
        let twentyEightDayStart = calendar.date(byAdding: .day, value: -27, to: latestDay) ?? latestDay
        let sevenDay = snapshot.weights.filter { $0.date >= sevenDayStart && $0.date <= latest.date }
        let twentyEightDay = snapshot.weights.filter { $0.date >= twentyEightDayStart && $0.date <= latest.date }
        guard !sevenDay.isEmpty, !twentyEightDay.isEmpty else { return nil }
        let oldest = twentyEightDay.min(by: { $0.date < $1.date })
        let change = oldest?.id == latest.id ? nil : oldest.map { latest.pounds - $0.pounds }
        let loggedDays = Set(twentyEightDay.map { Self.dayKey(for: $0.date) }).count
        return PublicWeightTrend(
            asOf: Self.dayKey(for: latest.date),
            currentPounds: latest.pounds,
            goalPounds: snapshot.goalWeight,
            sevenDayAverage: sevenDay.map(\.pounds).reduce(0, +) / Double(sevenDay.count),
            change28Days: change,
            daysLogged28: min(28, loggedDays)
        )
    }

    private func publicStrength(
        _ workouts: [WorkoutSession],
        catalog: ExerciseCatalog
    ) -> [PublicStrengthSession] {
        workouts
            .filter { $0.endedAt != nil && $0.completedSetCount > 0 }
            .sorted { $0.startedAt > $1.startedAt }
            .prefix(400)
            .map { workout in
                var scores: [MuscleGroup: Double] = [:]
                for logged in workout.exercises {
                    guard let exercise = catalog.exercise(id: logged.exerciseID) else { continue }
                    let sets = Double(logged.sets.filter(\.isPerformed).count)
                    for contribution in exercise.muscles {
                        scores[contribution.muscle, default: 0] += sets * contribution.intensity
                    }
                }
                let muscles = scores
                    .sorted { $0.value > $1.value }
                    .prefix(8)
                    .map { $0.key.title.lowercased() }
                let endedAt = workout.endedAt ?? workout.startedAt
                return PublicStrengthSession(
                    id: "workout_\(workout.id.uuidString.lowercased())",
                    date: Self.dayKey(for: workout.startedAt),
                    kind: workout.kind.rawValue,
                    durationMinutes: max(1, Int(endedAt.timeIntervalSince(workout.startedAt) / 60)),
                    workingSets: workout.completedSetCount,
                    muscleGroups: muscles,
                    updatedAt: Self.isoFormatter.string(from: endedAt)
                )
            }
    }

    private var deviceID: String {
        if let value = defaults.string(forKey: Self.deviceKey), !value.isEmpty { return value }
        let value = "device_\(UUID().uuidString.lowercased())"
        defaults.set(value, forKey: Self.deviceKey)
        return value
    }

    private static func decodeBase64URL(_ value: String) -> Data? {
        var base64 = value.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = base64.count % 4
        if remainder > 0 { base64 += String(repeating: "=", count: 4 - remainder) }
        return Data(base64Encoded: base64)
    }

    static func isAllowedEndpoint(_ url: URL) -> Bool {
        url.scheme == "https"
            && url.host == "rohansingh04.com"
            && url.port == nil
            && url.user == nil
            && url.password == nil
            && url.path == "/api/fitness/private-sync"
            && url.query == nil
            && url.fragment == nil
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    private static let isoFormatter = ISO8601DateFormatter()

    /// `TimeZone.current` read once into a static formatter freezes the zone for the
    /// life of the process, so after a flight every session and weight date shipped
    /// to the coach was still stamped in the home zone. Reading `Calendar.current`
    /// per call tracks the device, and matches how the widget builds its day key.
    static func dayKey(for date: Date, calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }
}

enum CoachSyncError: LocalizedError, Equatable {
    case invalidPairingCode
    /// The keychain refused to hold the pairing secret. This is deliberately NOT
    /// `invalidPairingCode`: it was, and a perfectly valid code then reported itself
    /// as invalid, which sent the diagnosis at the guard conditions for a week while
    /// the real cause was the environment. Carries the OSStatus so the next failure
    /// names itself (-34018 = errSecMissingEntitlement, what an unsigned build gets).
    case secretStoreUnavailable(OSStatus)
    case serverRejected
    case snapshotTooLarge

    var errorDescription: String? {
        switch self {
        case .invalidPairingCode: "That connection code is not valid."
        case .secretStoreUnavailable: "This phone would not store the connection securely. Try again after unlocking it."
        case .serverRejected: "The coach sync server rejected the update."
        case .snapshotTooLarge: "The private fitness snapshot is too large to sync."
        }
    }
}

/// Where the pairing secret lives. A protocol so tests can supply a store that does
/// not depend on the process holding a keychain entitlement — see the note on
/// `CoachSyncError.secretStoreUnavailable`.
protocol CoachSyncSecretStore: AnyObject {
    func save(_ data: Data, account: String) throws
    func load(_ account: String) -> Data?
    func delete(_ account: String)
}

final class CoachSyncKeychain: CoachSyncSecretStore {
    private let service: String

    /// The service name is injectable purely so tests never touch, overwrite, or
    /// delete the real pairing secret.
    init(service: String = "com.rohansingh.today.coach-sync") {
        self.service = service
    }

    func save(_ data: Data, account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let values: [String: Any] = [
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: data,
        ]
        let updateStatus = SecItemUpdate(query as CFDictionary, values as CFDictionary)
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw CoachSyncError.secretStoreUnavailable(updateStatus)
        }
        let addQuery = query.merging(values) { _, new in new }
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw CoachSyncError.secretStoreUnavailable(addStatus)
        }
    }

    func load(_ account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }

    func delete(_ account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
