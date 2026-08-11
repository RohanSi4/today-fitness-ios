import Foundation

/// Turns an in-progress `WorkoutSession` into the small, name-resolved payload
/// the Lock Screen widget can render.
///
/// This lives in the app rather than in `TodayWidgetShared` because naming an
/// exercise needs `ExerciseCatalog`, and the widget extension has no business
/// loading the whole catalog to print one string.
@MainActor
enum TodayWidgetWorkoutBuilder {
    static func make(
        from session: WorkoutSession?,
        catalog: ExerciseCatalog
    ) -> TodayWidgetWorkout? {
        guard let session else { return nil }
        return TodayWidgetWorkout(
            title: session.workoutTitle,
            startedAt: session.startedAt,
            lastSetAt: session.lastCompletedSetAt,
            nextExercise: nextExerciseName(in: session, catalog: catalog),
            completedSets: session.completedSetCount,
            plannedSets: plannedSetCount(in: session)
        )
    }

    /// The first movement still holding an unfinished working set.
    ///
    /// Warm-ups are skipped deliberately. An exercise whose only unchecked row
    /// is a warm-up is done as far as the session is concerned, and naming it as
    /// what is coming up next would send him back to a bar he already left.
    private static func nextExerciseName(
        in session: WorkoutSession,
        catalog: ExerciseCatalog
    ) -> String? {
        guard let pending = session.exercises.first(where: { logged in
            logged.sets.contains { !$0.isPerformed && $0.setType.countsAsWorking }
        }) else { return nil }

        // The brandless name. "Pec deck" reads on a Lock Screen line; "Pec deck
        // (Life Fitness)" gets truncated into uselessness, and the maker is not
        // the thing he needs reminding of between sets.
        return catalog.exercise(id: pending.baseExerciseID)?.name
            ?? catalog.exercise(id: pending.exerciseID)?.name
    }

    /// Every working set on the card, checked or not, so the progress bar has a
    /// denominator that does not move as he checks rows off.
    private static func plannedSetCount(in session: WorkoutSession) -> Int {
        session.exercises
            .flatMap(\.sets)
            .filter { $0.setType.countsAsWorking }
            .count
    }
}
