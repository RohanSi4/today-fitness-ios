import Combine
import Foundation

@MainActor
final class TodayStore: ObservableObject {
    static let shared = TodayStore()

    @Published private(set) var weights: [WeightEntry] = []
    @Published private(set) var workouts: [WorkoutSession] = []
    @Published var activeWorkout: WorkoutSession?
    @Published var goalWeight: Double = 175

    private let storageURL: URL
    private let calendar: Calendar

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
            workout.kind == kind && calendar.isDateInToday(workout.startedAt)
        }
    }

    func recordWeight(_ pounds: Double, on date: Date = Date(), healthKitID: UUID? = nil) {
        let day = calendar.startOfDay(for: date)
        weights.removeAll { calendar.isDate($0.date, inSameDayAs: day) }
        weights.append(WeightEntry(date: date, pounds: pounds, healthKitID: healthKitID))
        weights.sort { $0.date > $1.date }
        persist()
    }

    func mergeHealthWeights(_ entries: [WeightEntry]) {
        for entry in entries.sorted(by: { $0.date < $1.date }) {
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
        persist()
    }

    func finishActiveWorkout() -> WorkoutSession? {
        guard var workout = activeWorkout else { return nil }
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

    func lastPerformance(for exerciseID: String, limit: Int = 3) -> [LoggedExercise] {
        workouts
            .sorted { $0.startedAt > $1.startedAt }
            .compactMap { session in
                session.exercises.first { $0.exerciseID == exerciseID }
            }
            .prefix(limit)
            .map { $0 }
    }

    func muscleScores(for workout: WorkoutSession, catalog: ExerciseCatalog) -> [MuscleGroup: Double] {
        var scores: [MuscleGroup: Double] = [:]
        for loggedExercise in workout.exercises {
            guard let exercise = catalog.exercise(id: loggedExercise.exerciseID) else { continue }
            let completedSets = Double(loggedExercise.sets.filter(\.isComplete).count)
            guard completedSets > 0 else { continue }
            for contribution in exercise.muscles {
                scores[contribution.muscle, default: 0] += completedSets * contribution.intensity
            }
        }
        return scores
    }

    private func starterExercises(for kind: WorkoutKind, catalog: ExerciseCatalog) -> [LoggedExercise] {
        let prior = workouts.first { $0.kind == kind }
        let ids = prior?.exercises.map(\.exerciseID) ?? catalog.defaultExerciseIDs(for: kind)

        return ids.map { exerciseID in
            let previousSets = lastPerformance(for: exerciseID, limit: 1).first?.sets.filter(\.isComplete) ?? []
            let fallback = catalog.defaultSets(for: exerciseID)
            let first = previousSets.first ?? fallback.first ?? LoggedSet(weight: nil, reps: 8, isComplete: false)
            let second = previousSets.dropFirst().first ?? fallback.dropFirst().first ?? first
            return LoggedExercise(
                exerciseID: exerciseID,
                sets: [
                    LoggedSet(weight: first.weight, reps: first.reps, isComplete: false),
                    LoggedSet(weight: second.weight, reps: second.reps, isComplete: false)
                ]
            )
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: storageURL),
              let stored = try? JSONDecoder().decode(StoredTodayData.self, from: data) else {
            return
        }
        weights = stored.weights.sorted { $0.date > $1.date }
        workouts = stored.workouts.sorted { $0.startedAt > $1.startedAt }
        activeWorkout = stored.activeWorkout
        goalWeight = stored.goalWeight
    }

    private func persist() {
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
            try data.write(to: storageURL, options: .atomic)
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
