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

    private let storageURL: URL
    private let calendar: Calendar
    private var pendingPersistTask: Task<Void, Never>?

    init(storageURL: URL? = nil, calendar: Calendar = .current) {
        self.calendar = calendar
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
        persist()
    }

    func mergeHealthWeights(_ entries: [WeightEntry]) {
        for entry in entries
            .filter({ $0.pounds.isFinite && $0.pounds > 0 && $0.pounds < 1_000 })
            .sorted(by: { $0.date < $1.date }) {
            weights.removeAll { calendar.isDate($0.date, inSameDayAs: entry.date) }
            weights.append(entry)
        }
        weights.sort { $0.date > $1.date }
        persist()
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
        persist()
        return workout
    }

    func discardActiveWorkout() {
        activeWorkout = nil
        persist()
    }

    func deleteWorkout(id: UUID) {
        workouts.removeAll { $0.id == id }
        persist()
    }

    func flushPersistence() {
        pendingPersistTask?.cancel()
        pendingPersistTask = nil
        persist()
    }

    func dismissRecoveryMessage() {
        dataRecoveryMessage = nil
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

    private func load() {
        guard FileManager.default.fileExists(atPath: storageURL.path) else { return }
        if let stored = decodeStoredData(at: storageURL) {
            apply(stored)
            return
        }

        let backupURL = storageURL.appendingPathExtension("backup")
        if let stored = decodeStoredData(at: backupURL) {
            apply(stored)
            dataRecoveryMessage = "Today restored the last good copy of your private data."
            persist()
        } else {
            dataRecoveryMessage = "Today could not read the saved data. The original file was left in place."
        }
    }

    private func decodeStoredData(at url: URL) -> StoredTodayData? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(StoredTodayData.self, from: data)
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

    private func persist() {
        pendingPersistTask?.cancel()
        pendingPersistTask = nil
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
        } catch {
            assertionFailure("Could not persist Today data: \(error)")
        }
    }

    private static var defaultStorageURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("Today", isDirectory: true)
            .appendingPathComponent("private-data.json")
    }
}
