import Foundation

/// Display-only derivations shared by the workout recap and the history list,
/// which each had their own private copy that could drift apart.
extension WorkoutSession {
    var routineTemplate: HypertrophyTemplate? {
        if let routineSnapshot { return routineSnapshot }
        guard let routineID else { return nil }
        return HypertrophyProgramming.template(id: routineID)
    }

    var workoutTitle: String {
        routineTemplate.map { "\($0.title) workout" } ?? kind.workoutTitle
    }

    var completionTitle: String {
        routineTemplate.map { "\($0.title) complete" } ?? kind.completionTitle
    }

    var completedExerciseCount: Int {
        exercises.filter { $0.sets.contains(where: \.isWorkingSet) }.count
    }

    /// `nil` while the workout is still open.
    var durationLabel: String? {
        guard let endedAt else { return nil }
        let minutes = max(1, Int(endedAt.timeIntervalSince(startedAt) / 60))
        if minutes < 60 { return "\(minutes)m" }
        return "\(minutes / 60)h \(minutes % 60)m"
    }
}
