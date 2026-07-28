import Foundation

/// Display-only derivations shared by the workout recap and the history list,
/// which each had their own private copy that could drift apart.
extension WorkoutSession {
    var completedExerciseCount: Int {
        exercises.filter { $0.sets.contains(where: \.isPerformed) }.count
    }

    /// `nil` while the workout is still open.
    var durationLabel: String? {
        guard let endedAt else { return nil }
        let minutes = max(1, Int(endedAt.timeIntervalSince(startedAt) / 60))
        if minutes < 60 { return "\(minutes)m" }
        return "\(minutes / 60)h \(minutes % 60)m"
    }
}
