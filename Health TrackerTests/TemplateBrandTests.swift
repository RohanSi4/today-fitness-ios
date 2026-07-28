import Foundation
import Testing
@testable import Health_Tracker

/// What a workout opens on.
///
/// `BrandedStarterRules` was already right and already tested, but nothing on
/// the template path called it. `starterExercises` built its rows straight from
/// `catalog.defaultExerciseIDs`, which knows nothing about makers, so picking
/// Cybex on a lat pulldown and then starting an Upper workout produced an
/// unbranded row with catalog numbers, next to real history one id away.
@MainActor
struct TemplateBrandTests {
    private func makeStore(
        preferences: BrandPreferences
    ) -> (store: TodayStore, catalog: ExerciseCatalog) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("TemplateBrandTests-\(UUID().uuidString).json")
        let store = TodayStore(storageURL: url, brandPreferences: preferences)
        let catalog = ExerciseCatalog(
            cacheURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("TemplateBrandTests-catalog-\(UUID().uuidString).json")
        )
        return (store, catalog)
    }

    private func preferences() -> BrandPreferences {
        BrandPreferences(defaults: UserDefaults(suiteName: "today.template-brand.\(UUID().uuidString)")!)
    }

    private func row(_ store: TodayStore, base: String) -> LoggedExercise? {
        store.activeWorkout?.exercises.first { $0.baseExerciseID == base }
    }

    @Test func aTemplateOpensOnTheMakerHeAlreadyPicked() throws {
        let prefs = preferences()
        prefs.remember(.cybex, for: "lat-pulldown")
        let (store, catalog) = makeStore(preferences: prefs)

        store.beginWorkout(kind: .upper, catalog: catalog)

        let pulldown = try #require(row(store, base: "lat-pulldown"))
        #expect(pulldown.brand == .cybex)
        #expect(pulldown.exerciseID == "lat-pulldown@cybex")
    }

    @Test func aMovementHeHasNeverChosenAMakerForStaysUnbranded() throws {
        let (store, catalog) = makeStore(preferences: preferences())

        store.beginWorkout(kind: .upper, catalog: catalog)

        let pulldown = try #require(row(store, base: "lat-pulldown"))
        #expect(pulldown.brand == nil)
        #expect(pulldown.exerciseID == "lat-pulldown")
    }

    /// A preference is per movement, so choosing a maker for one machine must not
    /// leak onto every other row in the template.
    @Test func onlyTheChosenMovementIsBranded() throws {
        let prefs = preferences()
        prefs.remember(.hammerStrength, for: "seated-machine-row")
        let (store, catalog) = makeStore(preferences: prefs)

        store.beginWorkout(kind: .upper, catalog: catalog)

        #expect(try #require(row(store, base: "seated-machine-row")).brand == .hammerStrength)
        #expect(try #require(row(store, base: "lat-pulldown")).brand == nil)
    }

    /// Free weights take no maker, so a preference left on one from an earlier
    /// build cannot produce a row the catalog does not have.
    @Test func aStalePreferenceCannotBrandAFreeWeightMovement() throws {
        let prefs = preferences()
        prefs.remember(.lifeFitness, for: "incline-dumbbell-curl")
        let (store, catalog) = makeStore(preferences: prefs)

        store.beginWorkout(kind: .upper, catalog: catalog)

        let curl = try #require(row(store, base: "incline-dumbbell-curl"))
        #expect(curl.brand == nil)
        #expect(curl.exerciseID == "incline-dumbbell-curl")
        // And every row still resolves, which is what a bogus id would break.
        for exercise in store.activeWorkout?.exercises ?? [] {
            #expect(catalog.exercise(id: exercise.exerciseID) != nil)
        }
    }

    /// The reason `starterExercises` had to stop calling `starterSets` directly.
    @Test func theFirstSessionOnANewMakerOpensOnHisRealNumbers() throws {
        let prefs = preferences()
        let (store, catalog) = makeStore(preferences: prefs)

        // Months of unbranded lat pulldowns.
        store.beginWorkout(kind: .upper, catalog: catalog)
        var workout = try #require(store.activeWorkout)
        let index = try #require(workout.exercises.firstIndex { $0.baseExerciseID == "lat-pulldown" })
        workout.exercises[index].sets = [
            LoggedSet(weight: 150, reps: 9, isComplete: true),
            LoggedSet(weight: 150, reps: 9, isComplete: true),
        ]
        store.updateActiveWorkout(workout)
        _ = store.finishActiveWorkout()

        // Then he picks a maker and starts the template again.
        prefs.remember(.cybex, for: "lat-pulldown")
        store.beginWorkout(kind: .upper, catalog: catalog)

        let pulldown = try #require(row(store, base: "lat-pulldown"))
        #expect(pulldown.brand == .cybex)
        #expect(pulldown.sets.first?.weight == 150)
        #expect(pulldown.sets.first?.reps == 9)
        // Borrowed, never pre-ticked.
        #expect(pulldown.sets.allSatisfy { !$0.isComplete })
    }

    /// Once the maker has its own history the borrowing stops, which is the whole
    /// point of separating them.
    @Test func aMakerWithItsOwnHistoryUsesItRatherThanTheUnbrandedNumbers() throws {
        let prefs = preferences()
        prefs.remember(.cybex, for: "lat-pulldown")
        let (store, catalog) = makeStore(preferences: prefs)

        store.beginWorkout(kind: .upper, catalog: catalog)
        var workout = try #require(store.activeWorkout)
        let index = try #require(workout.exercises.firstIndex { $0.baseExerciseID == "lat-pulldown" })
        #expect(workout.exercises[index].exerciseID == "lat-pulldown@cybex")
        workout.exercises[index].sets = [LoggedSet(weight: 130, reps: 8, isComplete: true)]
        store.updateActiveWorkout(workout)
        _ = store.finishActiveWorkout()

        store.beginWorkout(kind: .upper, catalog: catalog)

        #expect(try #require(row(store, base: "lat-pulldown")).sets.first?.weight == 130)
    }

    /// A deliberate "No brand" is a choice, and has to beat the maker carried on
    /// the previous session's ids or it could never be undone from a template.
    @Test func choosingNoBrandClearsTheMakerTheLastSessionUsed() throws {
        let prefs = preferences()
        prefs.remember(.cybex, for: "lat-pulldown")
        let (store, catalog) = makeStore(preferences: prefs)

        store.beginWorkout(kind: .upper, catalog: catalog)
        var workout = try #require(store.activeWorkout)
        let index = try #require(workout.exercises.firstIndex { $0.baseExerciseID == "lat-pulldown" })
        workout.exercises[index].sets = [LoggedSet(weight: 130, reps: 8, isComplete: true)]
        store.updateActiveWorkout(workout)
        _ = store.finishActiveWorkout()

        prefs.remember(nil, for: "lat-pulldown")
        store.beginWorkout(kind: .upper, catalog: catalog)

        #expect(try #require(row(store, base: "lat-pulldown")).exerciseID == "lat-pulldown")
    }

    /// With nothing on record the previous session's id is authoritative, so a
    /// brand chosen before this preference map existed is not stripped.
    @Test func aPriorSessionsMakerSurvivesWhenNoPreferenceWasEverRecorded() throws {
        let prefs = preferences()
        let (store, catalog) = makeStore(preferences: prefs)

        store.beginWorkout(kind: .upper, catalog: catalog)
        var workout = try #require(store.activeWorkout)
        let index = try #require(workout.exercises.firstIndex { $0.baseExerciseID == "lat-pulldown" })
        workout.exercises[index] = LoggedExercise(
            exerciseID: "lat-pulldown@precor",
            sets: [LoggedSet(weight: 140, reps: 8, isComplete: true)]
        )
        store.updateActiveWorkout(workout)
        _ = store.finishActiveWorkout()

        #expect(!prefs.hasChoice(for: "lat-pulldown"))
        store.beginWorkout(kind: .upper, catalog: catalog)

        let pulldown = try #require(row(store, base: "lat-pulldown"))
        #expect(pulldown.exerciseID == "lat-pulldown@precor")
        #expect(pulldown.sets.first?.weight == 140)
    }

    /// A store pointed at its own file must not read or write the real map, the
    /// same isolation the coach sync already has. Without this a test run would
    /// depend on, and rewrite, whatever is on the phone.
    @Test func aTestStoreDoesNotTouchTheSharedPreferences() throws {
        BrandPreferences.shared.remember(.technogym, for: "lat-pulldown")
        defer { BrandPreferences.shared.forget("lat-pulldown") }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("TemplateBrandTests-iso-\(UUID().uuidString).json")
        let store = TodayStore(storageURL: url)
        let catalog = ExerciseCatalog(
            cacheURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("TemplateBrandTests-iso-cat-\(UUID().uuidString).json")
        )

        store.beginWorkout(kind: .upper, catalog: catalog)

        #expect(try #require(row(store, base: "lat-pulldown")).brand == nil)
    }
}
