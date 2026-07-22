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
    private let keychain: CoachSyncKeychain
    private var pairing: CoachSyncPairing?
    private var syncTask: Task<Void, Never>?

    private static let pairingAccount = "coach-sync-pairing-v1"
    private static let lastSyncedKey = "coachSync.lastSyncedAt"
    private static let pendingKey = "coachSync.hasPendingChanges"
    private static let deviceKey = "coachSync.deviceId"
    private static let sharesWeightKey = "coachSync.sharesWeightTrend"

    init(
        session: URLSession = .shared,
        defaults: UserDefaults = .standard,
        keychain: CoachSyncKeychain = CoachSyncKeychain()
    ) {
        self.session = session
        self.defaults = defaults
        self.keychain = keychain
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
        hasPendingChanges = true
        defaults.set(true, forKey: Self.pendingKey)
        if case .syncing = state { return }
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
        syncTask?.cancel()
        syncTask = nil
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
        syncTask?.cancel()
        syncTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            await self?.sync(snapshot: snapshot, catalog: catalog)
        }
    }

    func sync(snapshot: StoredTodayData, catalog: ExerciseCatalog) async {
        guard let pairing else {
            state = .notConnected
            return
        }
        guard state != .syncing else { return }
        state = .syncing

        do {
            let batch = try makeBatch(snapshot: snapshot, catalog: catalog, pairing: pairing)
            guard let endpoint = URL(string: pairing.endpoint), Self.isAllowedEndpoint(endpoint) else {
                throw CoachSyncError.invalidPairingCode
            }
            var request = URLRequest(url: endpoint)
            request.httpMethod = "POST"
            request.timeoutInterval = 20
            request.setValue("Bearer \(pairing.writeToken)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
            request.httpBody = try Self.encoder.encode(batch)

            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                throw CoachSyncError.serverRejected
            }
            let receipt = try JSONDecoder().decode(FitnessSyncResponse.self, from: data)
            guard receipt.ok, receipt.batchId == batch.batchId else { throw CoachSyncError.serverRejected }

            let now = Date()
            lastSyncedAt = now
            hasPendingChanges = false
            defaults.set(now, forKey: Self.lastSyncedKey)
            defaults.set(false, forKey: Self.pendingKey)
            state = .synced(now)
        } catch is CancellationError {
            state = .ready
        } catch {
            hasPendingChanges = true
            defaults.set(true, forKey: Self.pendingKey)
            state = .failed("Saved on this phone. Sync will retry when the app is online.")
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
        let loggedDays = Set(twentyEightDay.map { Self.dayFormatter.string(from: $0.date) }).count
        return PublicWeightTrend(
            asOf: Self.dayFormatter.string(from: latest.date),
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
                    date: Self.dayFormatter.string(from: workout.startedAt),
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

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

enum CoachSyncError: LocalizedError {
    case invalidPairingCode
    case serverRejected
    case snapshotTooLarge

    var errorDescription: String? {
        switch self {
        case .invalidPairingCode: "That connection code is not valid."
        case .serverRejected: "The coach sync server rejected the update."
        case .snapshotTooLarge: "The private fitness snapshot is too large to sync."
        }
    }
}

final class CoachSyncKeychain {
    private let service = "com.rohansingh.today.coach-sync"

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
            throw CoachSyncError.invalidPairingCode
        }
        let addQuery = query.merging(values) { _, new in new }
        guard SecItemAdd(addQuery as CFDictionary, nil) == errSecSuccess else {
            throw CoachSyncError.invalidPairingCode
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
