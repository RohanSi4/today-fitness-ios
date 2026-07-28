import Foundation

/// One place to phrase a logged set.
///
/// The same "235 × 5" string was being rebuilt in four views with subtly
/// different rules, so the workout log, the history detail and the exercise
/// subtitle could disagree about the same set.
enum SetSummary {
    /// - Parameter includingUnit: History shows "235 lb × 5" because it has the
    ///   room; the dense in-workout views drop the unit.
    static func text(
        for set: LoggedSet,
        exercise: ExerciseDefinition,
        includingUnit: Bool = false
    ) -> String {
        guard exercise.loadMode != .bodyweight, let weight = set.weight, weight > 0 else {
            return "\(set.reps) reps"
        }
        let value = weight.formatted(.number.precision(.fractionLength(0...1)))
        return includingUnit ? "\(value) lb × \(set.reps)" : "\(value) × \(set.reps)"
    }

    static func performedText(
        for sets: [LoggedSet],
        exercise: ExerciseDefinition,
        limit: Int? = nil,
        separator: String = ", "
    ) -> String {
        var performed = sets.filter(\.isPerformed)
        if let limit { performed = Array(performed.prefix(limit)) }
        return performed
            .map { text(for: $0, exercise: exercise) }
            .joined(separator: separator)
    }
}
