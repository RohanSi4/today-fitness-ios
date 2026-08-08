import Combine
import Foundation

@MainActor
final class TodayStore: ObservableObject {
    static let shared = TodayStore()

    @Published private(set) var weights: [WeightEntry] = []
    @Published private(set) var workouts: [WorkoutSession] = []
    @Published var activeWorkout: WorkoutSession?
    @Published var goalWeight: Double = 175
    @Published private(set) var routines: [HypertrophyTemplate] = HypertrophyProgramming.templates
    @Published private(set) var dataRecoveryMessage: String?

    /// False only when a load failed because the bytes were unreadable, which gates
    /// every write. Starts true so a fresh install, which legitimately has no file,
    /// can save normally.
    private var didLoadCleanly = true

    /// True between a save that did not reach disk and the next one that does. The
    /// old code told the owner "it will try again" and then never did.
    private var hasUnsavedChanges = false

    /// Whether the in-memory archive actually came from disk. Anything that
    /// publishes this state outside the app - the widget above all - has to check
    /// it, because an unreadable load leaves the store empty, not wrong-but-close.
    var hasReliableData: Bool { didLoadCleanly }

    private let storageURL: URL
    private let calendar: Calendar
    private let syncService: any CoachSyncing
    private(set) var permitsExternalCoachSync: Bool
    private var pendingPersistTask: Task<Void, Never>?
    private var deletedWorkoutIDs: [UUID] = []

    /// Read when a template builds its starting exercises, so a workout opens on
    /// the makers he already picked instead of on unbranded rows he has to fix.
    private let brandPreferences: BrandPreferences

    init(
        storageURL: URL? = nil,
        calendar: Calendar = .current,
        syncService: (any CoachSyncing)? = nil,
        brandPreferences: BrandPreferences? = nil
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
        // Same rule the sync service follows: a store pointed at its own file is
        // a test store, and must not read or write the real preference map.
        if let brandPreferences {
            self.brandPreferences = brandPreferences
        } else if storageURL == nil {
            self.brandPreferences = .shared
        } else {
            self.brandPreferences = BrandPreferences(
                defaults: UserDefaults(suiteName: "today.test.\(UUID().uuidString)") ?? .standard
            )
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

    func recordWeight(
        _ pounds: Double,
        on date: Date = Date(),
        healthKitID: UUID? = nil,
        healthKitOwnedByToday: Bool = false
    ) {
        guard pounds.isFinite, pounds > 0, pounds < 1_000 else { return }
        let day = calendar.startOfDay(for: date)
        weights.removeAll { calendar.isDate($0.date, inSameDayAs: day) }
        weights.append(WeightEntry(
            date: date,
            pounds: pounds,
            healthKitID: healthKitID,
            healthKitOwnedByToday: healthKitOwnedByToday,
            isUserEntered: true
        ))
        weights.sort { $0.date > $1.date }
        persist(syncAfterSave: true)
    }

    func deleteWeight(id: UUID) {
        guard weights.contains(where: { $0.id == id }) else { return }
        weights.removeAll { $0.id == id }
        persist(syncAfterSave: true)
    }

    func updateGoalWeight(_ pounds: Double) {
        guard pounds.isFinite, pounds >= 50, pounds <= 500 else { return }
        goalWeight = pounds
        persist(syncAfterSave: true)
    }

    func updateRoutine(_ routine: HypertrophyTemplate) {
        guard let index = routines.firstIndex(where: { $0.id == routine.id }),
              !routine.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !routine.exercises.isEmpty else { return }
        routines[index] = routine
        persist(syncAfterSave: true)
    }

    func resetRoutine(id: String) {
        guard let original = HypertrophyProgramming.template(id: id),
              let index = routines.firstIndex(where: { $0.id == id }) else { return }
        routines[index] = original
        persist(syncAfterSave: true)
    }

    func routine(id: String?) -> HypertrophyTemplate? {
        guard let id else { return nil }
        return routines.first { $0.id == id }
    }

    func nextRoutine(for kind: WorkoutKind) -> HypertrophyTemplate? {
        let ids: (a: String, b: String)
        switch kind {
        case .upper: ids = ("upper-a", "upper-b")
        case .lower: ids = ("lower-a", "lower-b")
        default: return nil
        }
        let last = workouts.first { $0.routineID == ids.a || $0.routineID == ids.b }?.routineID
        return routine(id: last == ids.a ? ids.b : ids.a)
    }

    func mergeHealthWeights(_ entries: [WeightEntry]) {
        var changed = false
        for entry in entries
            .filter({ $0.pounds.isFinite && $0.pounds > 0 && $0.pounds < 1_000 })
            .sorted(by: { $0.date < $1.date }) {
            // Every HealthKit fetch rebuilds these values with fresh ids, so a plain
            // replace rewrote identical rows, churned SwiftUI identity, and fired a
            // coach sync on every single weight save. Only take a genuine change.
            let existing = weights.first { calendar.isDate($0.date, inSameDayAs: entry.date) }
            if existing?.isUserEntered == true,
               existing?.healthKitID != entry.healthKitID {
                continue
            }
            if let existing,
               existing.date == entry.date,
               existing.pounds == entry.pounds,
               existing.healthKitID == entry.healthKitID {
                continue
            }
            weights.removeAll { calendar.isDate($0.date, inSameDayAs: entry.date) }
            weights.append(entry)
            changed = true
        }
        guard changed else { return }
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

    func beginWorkout(template: HypertrophyTemplate, catalog: ExerciseCatalog) {
        if activeWorkout != nil { return }
        activeWorkout = WorkoutSession(
            kind: template.kind,
            routineID: template.id,
            routineSnapshot: template,
            startedAt: Date(),
            endedAt: nil,
            exercises: starterExercises(for: template, catalog: catalog)
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
        guard workouts.contains(where: { $0.id == id }) else { return }
        workouts.removeAll { $0.id == id }
        if !deletedWorkoutIDs.contains(id) {
            deletedWorkoutIDs.append(id)
        }
        persist(syncAfterSave: true)
    }

    func updateWorkout(_ workout: WorkoutSession) {
        guard let index = workouts.firstIndex(where: { $0.id == workout.id }) else { return }
        workouts[index] = workout
        workouts.sort { $0.startedAt > $1.startedAt }
        persist(syncAfterSave: true)
    }

    @discardableResult
    func reopenWorkout(id: UUID) -> Bool {
        guard activeWorkout == nil,
              let index = workouts.firstIndex(where: { $0.id == id }) else { return false }
        var reopened = workouts.remove(at: index)
        reopened.endedAt = nil
        activeWorkout = reopened
        persist(syncAfterSave: true)
        return true
    }

    @discardableResult
    func undoFinishedWorkout(id: UUID) -> Bool {
        reopenWorkout(id: id)
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
            goalWeight: goalWeight,
            routines: routines,
            deletedWorkoutIDs: deletedWorkoutIDs
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
                    $0.exerciseID == exerciseID && $0.sets.contains(where: \.isWorkingSet)
                }
            }
            .prefix(limit)
            .map { $0 }
    }

    func muscleScores(for workout: WorkoutSession, catalog: ExerciseCatalog) -> [MuscleGroup: Double] {
        var scores: [MuscleGroup: Double] = [:]
        for loggedExercise in workout.exercises {
            guard let exercise = catalog.exercise(id: loggedExercise.exerciseID) else { continue }
            let completedSets = Double(loggedExercise.sets.filter(\.isWorkingSet).count)
            guard completedSets > 0 else { continue }
            for contribution in exercise.muscles {
                scores[contribution.muscle, default: 0] += completedSets * contribution.intensity
            }
        }
        return scores
    }

    func starterSets(for exerciseID: String, catalog: ExerciseCatalog) -> [LoggedSet] {
        let previousSets = lastPerformance(for: exerciseID, limit: 1)
            .first?.sets.filter(\.isProgressionSet) ?? []
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
            let resolved = brandedID(for: exerciseID, catalog: catalog)
            return LoggedExercise(
                exerciseID: resolved,
                // Not `starterSets` directly. That only looks up the exact id, so
                // the first session on a newly chosen maker opened on catalog
                // defaults with his real numbers sitting one id away. These rules
                // borrow the unbranded history once, then let the two diverge.
                sets: BrandedStarterRules.starter(
                    for: resolved,
                    history: self,
                    catalog: catalog
                ).sets
            )
        }
    }

    private func starterExercises(
        for template: HypertrophyTemplate,
        catalog: ExerciseCatalog
    ) -> [LoggedExercise] {
        template.exercises.compactMap { item in
            guard catalog.exercise(id: item.exerciseID) != nil else { return nil }
            let exerciseID = brandedID(for: item.exerciseID, catalog: catalog)
            let starter = BrandedStarterRules.starter(
                for: exerciseID,
                history: self,
                catalog: catalog
            ).sets
            let seed = starter.isEmpty
                ? [LoggedSet(
                    weight: nil,
                    reps: HypertrophyProgramming.prescription(for: exerciseID).reps.lower,
                    isComplete: false
                )]
                : starter
            let sets = (0..<item.sets).map { index in
                let source = seed[min(index, seed.count - 1)]
                return LoggedSet(weight: source.weight, reps: source.reps, isComplete: false, rir: 0)
            }
            return LoggedExercise(exerciseID: exerciseID, sets: sets)
        }
    }

    /// The id a template row should open on, once his remembered maker is applied.
    ///
    /// A deliberate choice always wins, including a deliberate "No brand", because
    /// the preference is the most recent thing he actually said. With no choice on
    /// record the id is left exactly as it came in, so a brand carried by the
    /// previous session is never silently stripped.
    private func brandedID(for exerciseID: String, catalog: ExerciseCatalog) -> String {
        guard brandPreferences.hasChoice(for: exerciseID) else { return exerciseID }
        let brand = brandPreferences.lastBrand(for: exerciseID)
        let qualified = catalog.qualifiedID(for: exerciseID, brand: brand)
        // `qualifiedID` refuses a maker the movement does not accept, so a barbell
        // row cannot pick up a brand from a stale preference.
        return catalog.exercise(id: qualified) != nil ? qualified : exerciseID
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
            if stored.unreadableEntryCount > 0 {
                // Some entries did not decode, so the next save would write a
                // shorter archive than the one on disk. Keep the original bytes
                // first: they may be perfectly good data this build cannot parse.
                let count = stored.unreadableEntryCount
                quarantine(storageURL, reason: "partial")
                dataRecoveryMessage = "Today loaded your data but skipped \(count) \(count == 1 ? "entry it" : "entries it") could not read. A copy of the original file was kept."
            }
        case .unreadable:
            markUnreadable()
        case .corrupt:
            loadFromBackup()
        }
    }

    private func loadFromBackup() {
        switch readStoredData(at: storageURL.appendingPathExtension("backup")) {
        case .decoded(let stored):
            // Keep the unreadable primary before the restored copy overwrites it.
            quarantine(storageURL, reason: "corrupt")
            apply(stored)
            didLoadCleanly = true
            dataRecoveryMessage = "Today restored the last good copy of your private data."
            persist()
        case .unreadable:
            markUnreadable()
        case .missing, .corrupt:
            // Genuinely unrecoverable rather than locked, so writing is safe again.
            // Writing is also what destroys the original, so copy it aside first:
            // the old message promised the file was left in place, and the very
            // next save broke that promise.
            didLoadCleanly = true
            let kept = quarantine(storageURL, reason: "corrupt") != nil
            dataRecoveryMessage = kept
                ? "Today could not read the saved data and started fresh. A copy of the unreadable file was kept on this phone."
                : "Today could not read the saved data and started fresh."
        }
    }

    private func markUnreadable() {
        didLoadCleanly = false
        dataRecoveryMessage = "Today could not read your saved data because the phone was locked. It will load once you unlock and open the app, and nothing was overwritten."
    }

    /// Recovery hook for becoming active again. Retries a load that failed only
    /// because the device was locked, and retries a save that never reached disk.
    /// Safe to call on every foreground transition: it does nothing unless a read
    /// or a write actually failed.
    func reloadIfUnreadable() {
        if !didLoadCleanly {
            // Anything typed while the archive was unreadable exists only in memory.
            // Reloading would replace it with the file, so carry it back over.
            let pending = hasUnsavedChanges ? syncSnapshot : nil
            load()
            guard didLoadCleanly else { return }
            dataRecoveryMessage = nil
            if let pending { reapply(pending) }
        }
        if hasUnsavedChanges { persist(syncAfterSave: true) }
    }

    private func apply(_ stored: StoredTodayData) {
        weights = stored.weights.sorted { $0.date > $1.date }
        let deleted = Set(stored.deletedWorkoutIDs)
        workouts = stored.workouts
            .filter { !deleted.contains($0.id) }
            .sorted { $0.startedAt > $1.startedAt }
        activeWorkout = stored.activeWorkout
        routines = stored.routines
        deletedWorkoutIDs = stored.deletedWorkoutIDs
        goalWeight = stored.goalWeight.isFinite && stored.goalWeight > 0
            ? stored.goalWeight
            : StoredTodayData.defaultGoalWeight
    }

    /// Layer entries that only ever existed in memory back on top of a load, newest
    /// wins per day, so a recovered read cannot erase what was logged in the meantime.
    private func reapply(_ pending: StoredTodayData) {
        for entry in pending.weights.sorted(by: { $0.date < $1.date }) {
            weights.removeAll { calendar.isDate($0.date, inSameDayAs: entry.date) }
            weights.append(entry)
        }
        weights.sort { $0.date > $1.date }

        let known = Set(workouts.map(\.id))
        workouts.append(contentsOf: pending.workouts.filter { !known.contains($0.id) })
        deletedWorkoutIDs = Array(Set(deletedWorkoutIDs + pending.deletedWorkoutIDs))
            .sorted { $0.uuidString < $1.uuidString }
        let deleted = Set(deletedWorkoutIDs)
        workouts.removeAll { deleted.contains($0.id) }
        workouts.sort { $0.startedAt > $1.startedAt }

        if let active = pending.activeWorkout { activeWorkout = active }
        // A goal left at the default is indistinguishable from one never touched,
        // so only a deliberate-looking value overrides what was on disk.
        if pending.goalWeight != StoredTodayData.defaultGoalWeight {
            goalWeight = pending.goalWeight
        }
        if pending.routines != HypertrophyProgramming.templates {
            routines = pending.routines
        }
    }

    /// Copies a file aside under a timestamped name so unreadable-but-possibly-good
    /// bytes survive the next write. Returns the copy, or nil if there was nothing
    /// to copy.
    @discardableResult
    private func quarantine(_ url: URL, reason: String) -> URL? {
        guard let data = try? Data(contentsOf: url), !data.isEmpty else { return nil }
        let stamp = Int(Date().timeIntervalSince1970)
        let destination = url
            .deletingPathExtension()
            .appendingPathExtension("\(reason)-\(stamp)")
            .appendingPathExtension("json")
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: destination, options: [.atomic, .completeFileProtection])
        } catch {
            return nil
        }
        pruneQuarantine()
        return destination
    }

    /// Salvaged copies are for hand recovery, not storage. Keep the newest few.
    private func pruneQuarantine() {
        let directory = storageURL.deletingLastPathComponent()
        let stem = storageURL.deletingPathExtension().lastPathComponent
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ) else { return }
        let salvaged = files
            .filter { $0.lastPathComponent.hasPrefix("\(stem).corrupt-") || $0.lastPathComponent.hasPrefix("\(stem).partial-") }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        guard salvaged.count > Self.maximumQuarantinedCopies else { return }
        for url in salvaged.prefix(salvaged.count - Self.maximumQuarantinedCopies) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private static let maximumQuarantinedCopies = 5

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
        guard didLoadCleanly else {
            hasUnsavedChanges = true
            return
        }
        let value = syncSnapshot
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
            hasUnsavedChanges = false
            if syncAfterSave {
                syncService.scheduleSync(snapshot: value, catalog: .shared)
            }
        } catch {
            // assertionFailure alone compiles out of Release, so on a real phone every
            // failed save was invisible. Surface it, since HistoryView already shows
            // this message.
            assertionFailure("Could not persist Today data: \(error)")
            // Flagged so `reloadIfUnreadable` can actually make good on the promise
            // below the next time the app comes to the foreground.
            hasUnsavedChanges = true
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
