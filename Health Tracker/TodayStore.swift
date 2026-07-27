import Combine
import Foundation

@MainActor
final class TodayStore: ObservableObject {
    static let shared = TodayStore()

    @Published private(set) var weights: [WeightEntry] = []
    @Published private(set) var workouts: [WorkoutSession] = []
    @Published var activeWorkout: WorkoutSession?
    @Published var goalWeight: Double = 175
    @Published private(set) var dataRecoveryMessage: String?

    /// False only when a load failed because the bytes were unreadable, which gates
    /// every write. Starts true so a fresh install, which legitimately has no file,
    /// can save normally.
    private var didLoadCleanly = true

    private let storageURL: URL
    private let calendar: Calendar
    private let syncService: any CoachSyncing
    private(set) var permitsExternalCoachSync: Bool
    private var pendingPersistTask: Task<Void, Never>?

    init(
        storageURL: URL? = nil,
        calendar: Calendar = .current,
        syncService: (any CoachSyncing)? = nil
    ) {
        self.calendar = calendar
        if let syncService {
            self.syncService = syncService
            permitsExternalCoachSync = true
        } else if storageURL == nil {
            self.syncService = CoachSyncService.shared
            permitsExternalCoachSync = true
        } else {
            self.syncService = DisabledCoachSync()
            permitsExternalCoachSync = false
        }
        self.storageURL = storageURL ?? Self.defaultStorageURL
        load()
    }

    var latestWeight: WeightEntry? {
        weights.max(by: { $0.date < $1.date })
    }

    var todayWeight: WeightEntry? {
        weights.first { calendar.isDateInToday($0.date) }
    }

    var sevenDayAverage: Double? {
        let cutoff = calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: Date())) ?? Date()
        let recent = weights.filter { $0.date >= cutoff }.map(\.pounds)
        guard !recent.isEmpty else { return nil }
        return recent.reduce(0, +) / Double(recent.count)
    }

    var thirtyDayChange: Double? {
        guard let latest = latestWeight else { return nil }
        let cutoff = calendar.date(byAdding: .day, value: -30, to: latest.date) ?? latest.date
        guard let oldest = weights
            .filter({ $0.date >= cutoff && $0.date < latest.date })
            .min(by: { $0.date < $1.date }) else { return nil }
        return latest.pounds - oldest.pounds
    }

    func completedWorkoutToday(kind: WorkoutKind) -> WorkoutSession? {
        workouts.first { workout in
            workout.kind == kind && calendar.isDateInToday(workout.endedAt ?? workout.startedAt)
        }
    }

    func recordWeight(_ pounds: Double, on date: Date = Date(), healthKitID: UUID? = nil) {
        guard pounds.isFinite, pounds > 0, pounds < 1_000 else { return }
        let day = calendar.startOfDay(for: date)
        weights.removeAll { calendar.isDate($0.date, inSameDayAs: day) }
        weights.append(WeightEntry(date: date, pounds: pounds, healthKitID: healthKitID))
        weights.sort { $0.date > $1.date }
        persist(syncAfterSave: true)
    }

    func mergeHealthWeights(_ entries: [WeightEntry]) {
        for entry in entries
            .filter({ $0.pounds.isFinite && $0.pounds > 0 && $0.pounds < 1_000 })
            .sorted(by: { $0.date < $1.date }) {
            weights.removeAll { calendar.isDate($0.date, inSameDayAs: entry.date) }
            weights.append(entry)
        }
        weights.sort { $0.date > $1.date }
        persist(syncAfterSave: true)
    }

    func beginWorkout(kind: WorkoutKind, catalog: ExerciseCatalog) {
        if activeWorkout != nil { return }
        activeWorkout = WorkoutSession(
            kind: kind,
            startedAt: Date(),
            endedAt: nil,
            exercises: starterExercises(for: kind, catalog: catalog)
        )
        persist()
    }

    func updateActiveWorkout(_ workout: WorkoutSession) {
        activeWorkout = workout
        schedulePersist()
    }

    func finishActiveWorkout() -> WorkoutSession? {
        guard var workout = activeWorkout, workout.completedSetCount > 0 else { return nil }
        workout.endedAt = Date()
        workouts.insert(workout, at: 0)
        activeWorkout = nil
        persist(syncAfterSave: true)
        return workout
    }

    func discardActiveWorkout() {
        activeWorkout = nil
        persist()
    }

    func deleteWorkout(id: UUID) {
        workouts.removeAll { $0.id == id }
        persist(syncAfterSave: true)
    }

    func flushPersistence() {
        pendingPersistTask?.cancel()
        pendingPersistTask = nil
        persist()
    }

    func dismissRecoveryMessage() {
        dataRecoveryMessage = nil
    }

    var syncSnapshot: StoredTodayData {
        StoredTodayData(
            weights: weights,
            workouts: workouts,
            activeWorkout: activeWorkout,
            goalWeight: goalWeight
        )
    }

    func syncWithCoach() async {
        await syncService.sync(snapshot: syncSnapshot, catalog: .shared)
    }

    func lastPerformance(for exerciseID: String, limit: Int = 3) -> [LoggedExercise] {
        workouts
            .sorted { $0.startedAt > $1.startedAt }
            .compactMap { session in
                session.exercises.first {
                    $0.exerciseID == exerciseID && $0.sets.contains(where: \.isPerformed)
                }
            }
            .prefix(limit)
            .map { $0 }
    }

    func muscleScores(for workout: WorkoutSession, catalog: ExerciseCatalog) -> [MuscleGroup: Double] {
        var scores: [MuscleGroup: Double] = [:]
        for loggedExercise in workout.exercises {
            guard let exercise = catalog.exercise(id: loggedExercise.exerciseID) else { continue }
            let completedSets = Double(loggedExercise.sets.filter(\.isPerformed).count)
            guard completedSets > 0 else { continue }
            for contribution in exercise.muscles {
                scores[contribution.muscle, default: 0] += completedSets * contribution.intensity
            }
        }
        return scores
    }

    func starterSets(for exerciseID: String, catalog: ExerciseCatalog) -> [LoggedSet] {
        let previousSets = lastPerformance(for: exerciseID, limit: 1)
            .first?.sets.filter(\.isPerformed) ?? []
        let fallback = catalog.defaultSets(for: exerciseID)
        let first = previousSets.first ?? fallback.first ?? LoggedSet(weight: nil, reps: 8, isComplete: false)
        let second = previousSets.dropFirst().first ?? fallback.dropFirst().first ?? first
        return [first, second].map {
            LoggedSet(weight: $0.weight, reps: $0.reps, isComplete: false)
        }
    }

    private func starterExercises(for kind: WorkoutKind, catalog: ExerciseCatalog) -> [LoggedExercise] {
        let prior = kind == .other ? nil : workouts.first { $0.kind == kind }
        let candidates = prior?.exercises.map(\.exerciseID) ?? catalog.defaultExerciseIDs(for: kind)
        var seen = Set<String>()
        let ids = candidates.filter { id in
            seen.insert(id).inserted && catalog.exercise(id: id) != nil
        }

        return ids.map { exerciseID in
            return LoggedExercise(
                exerciseID: exerciseID,
                sets: starterSets(for: exerciseID, catalog: catalog)
            )
        }
    }

    /// Why a read failed, because "no bytes" and "bad bytes" need opposite responses.
    private enum StoredDataRead {
        case missing
        case decoded(StoredTodayData)
        /// The bytes could not be read at all. Almost always `.completeFileProtection`
        /// while the phone is locked, not corruption.
        case unreadable
        /// Bytes were read but did not decode. This one really is corruption.
        case corrupt
    }

    private func readStoredData(at url: URL) -> StoredDataRead {
        guard FileManager.default.fileExists(atPath: url.path) else { return .missing }
        guard let data = try? Data(contentsOf: url) else { return .unreadable }
        guard let stored = try? JSONDecoder().decode(StoredTodayData.self, from: data) else { return .corrupt }
        return .decoded(stored)
    }

    // The app can launch in the background while the phone is locked, because
    // HealthKit registers `.immediate` delivery for sleep and workouts. A watch run
    // syncing at 6am with the phone on the nightstand does exactly that. Under
    // `.completeFileProtection` the data file is then unreadable, and the old code
    // could not tell that apart from corruption: `fileExists` still returns true,
    // both the primary and the backup fail to read, and the store came up EMPTY.
    // That empty state was then published to the widget ("Log morning weight" after
    // you already had) and, worse, any later save wrote it over the good file.
    private func load() {
        switch readStoredData(at: storageURL) {
        case .missing:
            didLoadCleanly = true
        case .decoded(let stored):
            apply(stored)
            didLoadCleanly = true
        case .unreadable:
            markUnreadable()
        case .corrupt:
            loadFromBackup()
        }
    }

    private func loadFromBackup() {
        switch readStoredData(at: storageURL.appendingPathExtension("backup")) {
        case .decoded(let stored):
            apply(stored)
            didLoadCleanly = true
            dataRecoveryMessage = "Today restored the last good copy of your private data."
            persist()
        case .unreadable:
            markUnreadable()
        case .missing, .corrupt:
            // Genuinely unrecoverable rather than locked, so writing is safe again.
            didLoadCleanly = true
            dataRecoveryMessage = "Today could not read the saved data. The original file was left in place."
        }
    }

    private func markUnreadable() {
        didLoadCleanly = false
        dataRecoveryMessage = "Today could not read your saved data because the phone was locked. It will load once you unlock and open the app, and nothing was overwritten."
    }

    /// Retry a load that failed only because the device was locked. Safe to call on
    /// every foreground transition: it does nothing unless a read actually failed.
    func reloadIfUnreadable() {
        guard !didLoadCleanly else { return }
        load()
        if didLoadCleanly { dataRecoveryMessage = nil }
    }

    private func apply(_ stored: StoredTodayData) {
        weights = stored.weights.sorted { $0.date > $1.date }
        workouts = stored.workouts.sorted { $0.startedAt > $1.startedAt }
        activeWorkout = stored.activeWorkout
        goalWeight = stored.goalWeight.isFinite && stored.goalWeight > 0 ? stored.goalWeight : 175
    }

    private func schedulePersist() {
        pendingPersistTask?.cancel()
        pendingPersistTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            self?.persist()
        }
    }

    private func persist(syncAfterSave: Bool = false) {
        pendingPersistTask?.cancel()
        pendingPersistTask = nil
        // Never let an in-memory state we could not verify overwrite the file on
        // disk. Without this, one locked-device background launch silently replaced
        // the real archive with an empty one.
        guard didLoadCleanly else { return }
        let value = StoredTodayData(
            weights: weights,
            workouts: workouts,
            activeWorkout: activeWorkout,
            goalWeight: goalWeight
        )
        do {
            try FileManager.default.createDirectory(
                at: storageURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(value)
            if let existing = try? Data(contentsOf: storageURL),
               (try? JSONDecoder().decode(StoredTodayData.self, from: existing)) != nil {
                try? existing.write(
                    to: storageURL.appendingPathExtension("backup"),
                    options: [.atomic, .completeFileProtection]
                )
            }
            try data.write(to: storageURL, options: [.atomic, .completeFileProtection])
            if syncAfterSave {
                syncService.scheduleSync(snapshot: value, catalog: .shared)
            }
        } catch {
            // assertionFailure alone compiles out of Release, so on a real phone every
            // failed save was invisible. Surface it, since HistoryView already shows
            // this message.
            assertionFailure("Could not persist Today data: \(error)")
            dataRecoveryMessage = "Today could not save your latest changes. They are still here in the app, and it will try again."
        }
    }

    private static var defaultStorageURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("Today", isDirectory: true)
            .appendingPathComponent("private-data.json")
    }
}

@MainActor
private final class DisabledCoachSync: CoachSyncing {
    func scheduleSync(snapshot: StoredTodayData, catalog: ExerciseCatalog) {}
    func sync(snapshot: StoredTodayData, catalog: ExerciseCatalog) async {}
}
