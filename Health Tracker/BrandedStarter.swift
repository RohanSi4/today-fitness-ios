import Foundation

/// The part of `TodayStore` the starting-weight rules need, named so this logic
/// can be exercised against a stub instead of a real archive on disk.
@MainActor
protocol ExerciseHistorySource {
    func lastPerformance(for exerciseID: String, limit: Int) -> [LoggedExercise]
    func starterSets(for exerciseID: String, catalog: ExerciseCatalog) -> [LoggedSet]
}

extension TodayStore: ExerciseHistorySource {}

/// Where a set of starting weights came from.
enum StarterOrigin: Equatable {
    /// This exact machine has been logged before.
    case ownHistory
    /// Seeded from the movement's unbranded history the first time a maker is
    /// chosen for it.
    case carriedOverFromUnbranded
    /// Nothing to go on, so the catalog's defaults.
    case catalogDefault
}

struct BrandedStarter: Equatable {
    let sets: [LoggedSet]
    let origin: StarterOrigin
}

enum BrandedStarterRules {
    /// Starting weights for an exercise about to be added to a workout.
    ///
    /// The whole point of qualifying an id with a maker is that history stops
    /// being shared, which is correct once there is branded history to use. But
    /// on the very first Cybex session there is none, and falling straight
    /// through to the catalog default would silently throw away months of
    /// prefills for a movement he has been logging all along. That is a real
    /// cost for a choice that is supposed to be free.
    ///
    /// So a branded exercise with no history of its own seeds once from the
    /// movement's *unbranded* history. Nothing is copied, moved, or rewritten:
    /// the old unbranded sessions stay exactly where they are and stay visible
    /// in History. Only the numbers pre-filled into the new row come from them,
    /// and as soon as one branded session is logged the two diverge on their
    /// own, which is the behaviour he asked for.
    ///
    /// The fallback deliberately never reaches across to a *different* maker.
    /// Unbranded history is history whose machine simply was not recorded, so it
    /// plausibly includes this one. Another maker's history is known not to be
    /// this machine, and averaging those is the exact thing brand-qualified ids
    /// exist to prevent.
    @MainActor
    static func starter(
        for exerciseID: String,
        history: some ExerciseHistorySource,
        catalog: ExerciseCatalog
    ) -> BrandedStarter {
        if !history.lastPerformance(for: exerciseID, limit: 1).isEmpty {
            return BrandedStarter(
                sets: history.starterSets(for: exerciseID, catalog: catalog),
                origin: .ownHistory
            )
        }

        let parts = ExerciseDefinition.components(of: exerciseID)
        if parts.brand != nil, !history.lastPerformance(for: parts.base, limit: 1).isEmpty {
            return BrandedStarter(
                sets: history.starterSets(for: parts.base, catalog: catalog),
                origin: .carriedOverFromUnbranded
            )
        }

        return BrandedStarter(
            sets: history.starterSets(for: exerciseID, catalog: catalog),
            origin: .catalogDefault
        )
    }

    /// Whether a row is currently running on numbers borrowed from unbranded
    /// history, which is what the card discloses.
    ///
    /// Recomputed from the archive rather than remembered from when the row was
    /// added, so switching maker part-way through updates the disclosure too.
    @MainActor
    static func isUsingCarriedOverHistory(
        exerciseID: String,
        history: some ExerciseHistorySource
    ) -> Bool {
        let parts = ExerciseDefinition.components(of: exerciseID)
        guard parts.brand != nil else { return false }
        guard history.lastPerformance(for: exerciseID, limit: 1).isEmpty else { return false }
        return !history.lastPerformance(for: parts.base, limit: 1).isEmpty
    }
}
