import Foundation
import Testing
@testable import Health_Tracker

@MainActor
struct BrandPreferenceTests {
    @Test func aMakerIsRememberedPerMovement() {
        let preferences = isolatedPreferences()

        preferences.remember(.cybex, for: "lat-pulldown")

        #expect(preferences.lastBrand(for: "lat-pulldown") == .cybex)
        #expect(preferences.lastBrand(for: "seated-machine-row") == nil)
    }

    @Test func aQualifiedIdResolvesToTheSameMemoryAsItsMovement() {
        let preferences = isolatedPreferences()

        preferences.remember(.technogym, for: "lat-pulldown@cybex")

        // Keyed by movement, not by "lat-pulldown@cybex", or every maker would
        // get its own slot and nothing would ever be remembered.
        #expect(preferences.lastBrand(for: "lat-pulldown") == .technogym)
        #expect(preferences.lastBrand(for: "lat-pulldown@precor") == .technogym)
    }

    /// Choosing "No brand" has to stick. Storing nothing would let the previous
    /// maker be re-applied on the next session.
    @Test func deliberatelyChoosingNoBrandOverridesAnEarlierChoice() {
        let preferences = isolatedPreferences()
        preferences.remember(.hammerStrength, for: "leg-press")

        preferences.remember(nil, for: "leg-press")

        #expect(preferences.lastBrand(for: "leg-press") == nil)
        #expect(preferences.hasChoice(for: "leg-press"))
    }

    @Test func neverChoosingIsDistinctFromChoosingNone() {
        let preferences = isolatedPreferences()

        #expect(!preferences.hasChoice(for: "leg-press"))
        preferences.remember(nil, for: "leg-press")
        #expect(preferences.hasChoice(for: "leg-press"))
    }

    @Test func choicesSurviveALaunch() {
        let suite = "today.brand-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        BrandPreferences(defaults: defaults).remember(.precor, for: "lat-pulldown")

        #expect(BrandPreferences(defaults: defaults).lastBrand(for: "lat-pulldown") == .precor)
    }

    private func isolatedPreferences() -> BrandPreferences {
        let suite = "today.brand-tests.\(UUID().uuidString)"
        return BrandPreferences(defaults: UserDefaults(suiteName: suite)!)
    }
}

@MainActor
struct BrandedStarterTests {
    /// The case the whole fallback exists for. Months of unbranded lat pulldowns,
    /// then he picks Cybex: the prefills must not vanish.
    @Test func aFirstBrandedSessionInheritsTheUnbrandedNumbers() {
        let history = StubHistory(
            performed: ["lat-pulldown": [LoggedSet(weight: 150, reps: 9, isComplete: true)]]
        )

        let starter = BrandedStarterRules.starter(
            for: "lat-pulldown@cybex",
            history: history,
            catalog: catalog()
        )

        #expect(starter.origin == .carriedOverFromUnbranded)
        #expect(starter.sets.first?.weight == 150)
        #expect(starter.sets.first?.reps == 9)
    }

    @Test func onceTheMakerHasItsOwnHistoryItStopsBorrowing() {
        let history = StubHistory(
            performed: [
                "lat-pulldown": [LoggedSet(weight: 150, reps: 9, isComplete: true)],
                "lat-pulldown@cybex": [LoggedSet(weight: 130, reps: 8, isComplete: true)],
            ]
        )

        let starter = BrandedStarterRules.starter(
            for: "lat-pulldown@cybex",
            history: history,
            catalog: catalog()
        )

        #expect(starter.origin == .ownHistory)
        #expect(starter.sets.first?.weight == 130)
    }

    /// Borrowing across makers is the exact averaging that brand-qualified ids
    /// exist to prevent, so a Hammer Strength row must not seed from Cybex.
    @Test func oneMakerNeverBorrowsFromAnother() {
        let history = StubHistory(
            performed: ["lat-pulldown@cybex": [LoggedSet(weight: 130, reps: 8, isComplete: true)]]
        )

        let starter = BrandedStarterRules.starter(
            for: "lat-pulldown@hammer-strength",
            history: history,
            catalog: catalog()
        )

        #expect(starter.origin == .catalogDefault)
        #expect(starter.sets.first?.weight != 130)
    }

    @Test func anUnbrandedExerciseNeverBorrowsFromABrandedOne() {
        let history = StubHistory(
            performed: ["lat-pulldown@cybex": [LoggedSet(weight: 130, reps: 8, isComplete: true)]]
        )

        let starter = BrandedStarterRules.starter(
            for: "lat-pulldown",
            history: history,
            catalog: catalog()
        )

        #expect(starter.origin == .catalogDefault)
    }

    @Test func nothingToGoOnFallsBackToTheCatalog() {
        let starter = BrandedStarterRules.starter(
            for: "machine-chest-fly@precor",
            history: StubHistory(),
            catalog: catalog()
        )

        #expect(starter.origin == .catalogDefault)
        #expect(starter.sets.first?.weight == 235)
    }

    @Test func theCarryOverDisclosureTracksTheCurrentBrand() {
        let history = StubHistory(
            performed: ["lat-pulldown": [LoggedSet(weight: 150, reps: 9, isComplete: true)]]
        )

        #expect(
            BrandedStarterRules.isUsingCarriedOverHistory(
                exerciseID: "lat-pulldown@cybex",
                history: history
            )
        )
        // Unbranded is using its own history, not borrowing.
        #expect(
            !BrandedStarterRules.isUsingCarriedOverHistory(
                exerciseID: "lat-pulldown",
                history: history
            )
        )
        // No unbranded history to borrow either.
        #expect(
            !BrandedStarterRules.isUsingCarriedOverHistory(
                exerciseID: "leg-press@cybex",
                history: history
            )
        )
    }

    /// The unbranded sessions are only read. Nothing is copied, moved or
    /// rewritten, so his existing archive is exactly where it was.
    @Test func borrowingNeverTouchesTheOriginalHistory() {
        let history = StubHistory(
            performed: ["lat-pulldown": [LoggedSet(weight: 150, reps: 9, isComplete: true)]]
        )

        _ = BrandedStarterRules.starter(
            for: "lat-pulldown@cybex",
            history: history,
            catalog: catalog()
        )

        #expect(history.performed["lat-pulldown"]?.count == 1)
        #expect(history.performed["lat-pulldown@cybex"] == nil)
        #expect(history.mutations == 0)
    }

    @Test func borrowedSetsArriveUnchecked() {
        let history = StubHistory(
            performed: ["lat-pulldown": [LoggedSet(weight: 150, reps: 9, isComplete: true)]]
        )

        let starter = BrandedStarterRules.starter(
            for: "lat-pulldown@cybex",
            history: history,
            catalog: catalog()
        )

        #expect(starter.sets.allSatisfy { !$0.isComplete })
    }

    private func catalog() -> ExerciseCatalog {
        ExerciseCatalog(
            cacheURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("BrandStarterTests-\(UUID().uuidString).json")
        )
    }
}

/// Stands in for `TodayStore`, so these rules can be checked without an archive
/// on disk and without the real store's starter-set shaping in the way.
@MainActor
private final class StubHistory: ExerciseHistorySource {
    let performed: [String: [LoggedSet]]
    private(set) var mutations = 0

    init(performed: [String: [LoggedSet]] = [:]) {
        self.performed = performed
    }

    func lastPerformance(for exerciseID: String, limit: Int) -> [LoggedExercise] {
        guard let sets = performed[exerciseID] else { return [] }
        return [LoggedExercise(exerciseID: exerciseID, sets: sets)]
    }

    func starterSets(for exerciseID: String, catalog: ExerciseCatalog) -> [LoggedSet] {
        guard let sets = performed[exerciseID] else {
            return catalog.defaultSets(for: exerciseID)
        }
        return sets.map { LoggedSet(weight: $0.weight, reps: $0.reps, isComplete: false) }
    }
}
