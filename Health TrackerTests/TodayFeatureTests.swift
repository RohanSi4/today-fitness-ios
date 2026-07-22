import Foundation
import Testing
@testable import Health_Tracker

@MainActor
struct TodayStoreTests {
    @Test func weightEntryReplacesTheSameDayWithoutLosingHistory() throws {
        let url = temporaryURL("weight")
        let store = TodayStore(storageURL: url, calendar: utcCalendar)
        let day = Date(timeIntervalSince1970: 1_753_075_200)

        store.recordWeight(184.4, on: day)
        store.recordWeight(184.1, on: day.addingTimeInterval(3600))
        store.recordWeight(183.9, on: day.addingTimeInterval(86_400))

        #expect(store.weights.count == 2)
        #expect(store.weights.contains { $0.pounds == 184.1 })
        #expect(!store.weights.contains { $0.pounds == 184.4 })
    }

    @Test func invalidWeightsAreIgnored() {
        let store = TodayStore(storageURL: temporaryURL("invalid-weight"))

        store.recordWeight(0)
        store.recordWeight(-2)
        store.recordWeight(.infinity)
        store.recordWeight(.nan)

        #expect(store.weights.isEmpty)
    }

    @Test func nextWorkoutAlwaysStartsWithTwoSets() throws {
        let store = TodayStore(storageURL: temporaryURL("sets"))
        let catalog = ExerciseCatalog(cacheURL: temporaryURL("catalog"))

        store.beginWorkout(kind: .upper, catalog: catalog)
        var first = try #require(store.activeWorkout)
        first.exercises[0].sets.append(LoggedSet(weight: 240, reps: 4, isComplete: true))
        first.exercises[0].sets[0].isComplete = true
        first.exercises[0].sets[1].isComplete = true
        store.updateActiveWorkout(first)
        _ = store.finishActiveWorkout()

        store.beginWorkout(kind: .upper, catalog: catalog)
        let next = try #require(store.activeWorkout)
        #expect(next.exercises[0].sets.count == 2)
    }

    @Test func anAddedExerciseReusesTheLastPerformedValues() throws {
        let store = TodayStore(storageURL: temporaryURL("starter-values"))
        let catalog = ExerciseCatalog(cacheURL: temporaryURL("starter-catalog"))
        store.beginWorkout(kind: .upper, catalog: catalog)
        var workout = try #require(store.activeWorkout)
        workout.exercises[0].sets = [
            LoggedSet(weight: 235, reps: 5, isComplete: true),
            LoggedSet(weight: 240, reps: 4, isComplete: true),
        ]
        store.updateActiveWorkout(workout)
        _ = store.finishActiveWorkout()

        let sets = store.starterSets(for: workout.exercises[0].exerciseID, catalog: catalog)

        #expect(sets.count == 2)
        #expect(sets[0].weight == 235)
        #expect(sets[0].reps == 5)
        #expect(sets[1].weight == 240)
        #expect(sets[1].reps == 4)
        #expect(sets.allSatisfy { !$0.isComplete })
    }

    @Test func zeroRepSetsDoNotCountAndCannotFinishAWorkout() throws {
        let store = TodayStore(storageURL: temporaryURL("zero-rep"))
        let catalog = ExerciseCatalog(cacheURL: temporaryURL("zero-rep-catalog"))
        store.beginWorkout(kind: .upper, catalog: catalog)
        var workout = try #require(store.activeWorkout)
        workout.exercises[0].sets[0] = LoggedSet(weight: 235, reps: 0, isComplete: true)
        store.updateActiveWorkout(workout)

        #expect(workout.completedSetCount == 0)
        #expect(store.finishActiveWorkout() == nil)
        #expect(store.activeWorkout != nil)
        #expect(store.workouts.isEmpty)
        #expect(store.muscleScores(for: workout, catalog: catalog).isEmpty)
    }

    @Test func lastPerformanceSkipsAnEntryWithNoPerformedSets() throws {
        let store = TodayStore(storageURL: temporaryURL("performed-history"))
        let catalog = ExerciseCatalog(cacheURL: temporaryURL("performed-catalog"))
        store.beginWorkout(kind: .upper, catalog: catalog)
        var performed = try #require(store.activeWorkout)
        let exerciseID = performed.exercises[0].exerciseID
        performed.exercises[0].sets[0] = LoggedSet(weight: 235, reps: 5, isComplete: true)
        store.updateActiveWorkout(performed)
        _ = store.finishActiveWorkout()

        store.beginWorkout(kind: .upper, catalog: catalog)
        var newer = try #require(store.activeWorkout)
        newer.exercises[0].sets[0] = LoggedSet(weight: 250, reps: 5, isComplete: false)
        newer.exercises[1].sets[0].isComplete = true
        store.updateActiveWorkout(newer)
        #expect(store.finishActiveWorkout() != nil)

        let history = store.lastPerformance(for: exerciseID)
        #expect(history.count == 1)
        #expect(history[0].sets.contains { $0.weight == 235 && $0.isPerformed })
    }

    @Test func completedWorkoutCanBeDeleted() throws {
        let store = TodayStore(storageURL: temporaryURL("delete-workout"))
        let catalog = ExerciseCatalog(cacheURL: temporaryURL("delete-catalog"))
        store.beginWorkout(kind: .upper, catalog: catalog)
        var workout = try #require(store.activeWorkout)
        workout.exercises[0].sets[0].isComplete = true
        store.updateActiveWorkout(workout)
        let finished = try #require(store.finishActiveWorkout())

        store.deleteWorkout(id: finished.id)

        #expect(store.workouts.isEmpty)
    }

    @Test func activeWorkoutSurvivesStoreRelaunch() throws {
        let url = temporaryURL("active-relaunch")
        let catalog = ExerciseCatalog(cacheURL: temporaryURL("active-relaunch-catalog"))
        let firstStore = TodayStore(storageURL: url)
        firstStore.beginWorkout(kind: .lower, catalog: catalog)
        var workout = try #require(firstStore.activeWorkout)
        workout.exercises[0].sets[0].weight = 125
        firstStore.updateActiveWorkout(workout)
        firstStore.flushPersistence()

        let relaunched = TodayStore(storageURL: url)

        #expect(relaunched.activeWorkout?.kind == .lower)
        #expect(relaunched.activeWorkout?.exercises[0].sets[0].weight == 125)
    }

    @Test func corruptPrimaryRestoresTheLastGoodBackup() throws {
        let url = temporaryURL("backup-recovery")
        let store = TodayStore(storageURL: url, calendar: utcCalendar)
        let firstDay = Date(timeIntervalSince1970: 1_753_075_200)
        store.recordWeight(184.4, on: firstDay)
        store.recordWeight(183.9, on: firstDay.addingTimeInterval(86_400))
        try Data("not-json".utf8).write(to: url, options: .atomic)

        let recovered = TodayStore(storageURL: url, calendar: utcCalendar)

        #expect(recovered.weights.count == 1)
        #expect(recovered.weights[0].pounds == 184.4)
        #expect(recovered.dataRecoveryMessage != nil)
    }

    @Test func everyWorkoutStartingPointIsAvailable() {
        let catalog = ExerciseCatalog(cacheURL: temporaryURL("split-catalog"))
        let expectedKinds: Set<WorkoutKind> = [
            .upper, .lower, .push, .pull, .legs, .chest, .back, .other,
        ]

        #expect(Set(WorkoutKind.allCases) == expectedKinds)
        #expect(!catalog.defaultExerciseIDs(for: .push).isEmpty)
        #expect(!catalog.defaultExerciseIDs(for: .pull).isEmpty)
        #expect(!catalog.defaultExerciseIDs(for: .legs).isEmpty)
        #expect(!catalog.defaultExerciseIDs(for: .chest).isEmpty)
        #expect(!catalog.defaultExerciseIDs(for: .back).isEmpty)
        #expect(catalog.defaultExerciseIDs(for: .other).isEmpty)
    }

    @Test func blankWorkoutAlwaysStartsEmpty() throws {
        let store = TodayStore(storageURL: temporaryURL("blank-workout"))
        let catalog = ExerciseCatalog(cacheURL: temporaryURL("blank-catalog"))

        store.beginWorkout(kind: .other, catalog: catalog)
        var first = try #require(store.activeWorkout)
        #expect(first.exercises.isEmpty)

        first.exercises = [
            LoggedExercise(exerciseID: "machine-chest-fly", sets: catalog.defaultSets(for: "machine-chest-fly")),
        ]
        first.exercises[0].sets[0].isComplete = true
        store.updateActiveWorkout(first)
        _ = store.finishActiveWorkout()

        store.beginWorkout(kind: .other, catalog: catalog)
        let next = try #require(store.activeWorkout)
        #expect(next.exercises.isEmpty)
    }

    @Test func chestFlyMapsToDetailedMuscles() throws {
        let catalog = ExerciseCatalog(cacheURL: temporaryURL("muscles"))
        let exercise = try #require(catalog.exercise(id: "machine-chest-fly"))
        let groups = Set(exercise.muscles.map(\.muscle))

        #expect(groups.contains(.upperChest))
        #expect(groups.contains(.middleChest))
        #expect(groups.contains(.lowerChest))
    }

    @Test func armExercisesKeepLongAndShortHeadsSeparate() throws {
        let catalog = ExerciseCatalog(cacheURL: temporaryURL("heads"))
        let curl = try #require(catalog.exercise(id: "incline-dumbbell-curl"))
        let pushdown = try #require(catalog.exercise(id: "rope-triceps-pushdown"))

        #expect(curl.muscles.contains { $0.muscle == .bicepsLongHead })
        #expect(curl.muscles.contains { $0.muscle == .bicepsShortHead })
        #expect(pushdown.muscles.contains { $0.muscle == .tricepsLongHead })
        #expect(pushdown.muscles.contains { $0.muscle == .tricepsLateralHead })
        #expect(pushdown.muscles.contains { $0.muscle == .tricepsMedialHead })
    }

    @Test func strapsKeepIncidentalForearmWorkOutOfBackExercises() throws {
        let catalog = ExerciseCatalog(cacheURL: temporaryURL("strap-catalog"))
        let pulldown = try #require(catalog.exercise(id: "lat-pulldown"))
        let row = try #require(catalog.exercise(id: "seated-machine-row"))
        let wristCurl = try #require(catalog.exercise(id: "dumbbell-wrist-curl"))
        let importedBackExercise = ExerciseCatalog.detailedFallback(
            primary: ["lats"],
            secondary: ["forearms", "biceps"]
        )
        let importedCurl = ExerciseCatalog.detailedFallback(
            primary: ["biceps"],
            secondary: ["forearms"]
        )

        #expect(!pulldown.muscles.contains { $0.muscle == .forearms })
        #expect(!row.muscles.contains { $0.muscle == .forearms })
        #expect(wristCurl.muscles.contains { $0.muscle == .forearms && $0.intensity == 1 })
        #expect(!importedBackExercise.contains { $0.muscle == .forearms })
        #expect(importedCurl.contains { $0.muscle == .forearms && $0.intensity == 0.45 })
    }

    @Test func calfRaisesLightBothCalfRegions() throws {
        let store = TodayStore(storageURL: temporaryURL("calf-map"))
        let catalog = ExerciseCatalog(cacheURL: temporaryURL("calf-catalog"))
        let completed = LoggedExercise(
            exerciseID: "calf-raise",
            sets: [LoggedSet(weight: 100, reps: 12, isComplete: true)]
        )
        let workout = WorkoutSession(kind: .lower, startedAt: .now, endedAt: nil, exercises: [completed])
        let scores = store.muscleScores(for: workout, catalog: catalog)

        #expect(scores[.gastrocnemius] == 1)
        #expect(scores[.soleus] == 0.75)
    }

    @Test func setsCanBeAddedAndRemovedWithoutDroppingCompletedWorkFirst() {
        let completed = LoggedSet(weight: 235, reps: 5, isComplete: true)
        let planned = LoggedSet(weight: 235, reps: 5, isComplete: false)
        var exercise = LoggedExercise(exerciseID: "machine-chest-fly", sets: [completed, planned])

        exercise.removeOneSet()
        #expect(exercise.sets.count == 1)
        #expect(exercise.sets[0].isComplete)

        exercise.removeOneSet()
        #expect(exercise.sets.count == 1)

        exercise.addSet()
        #expect(exercise.sets.count == 2)
        #expect(exercise.sets[1].weight == 235)
        #expect(exercise.sets[1].reps == 5)
        #expect(!exercise.sets[1].isComplete)
    }

    private func temporaryURL(_ name: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("TodayTests-\(name)-\(UUID().uuidString).json")
    }

    private var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }
}

struct TrainingPlanModelTests {
    @Test func dayDetectsTheCoachChosenLiftWithoutExercisePrescription() throws {
        let day = TrainingPlanDay(
            date: "2026-07-21",
            dayLabel: "Tue 7/21",
            text: "6 mile run + lower body lift",
            isKeyDay: false,
            details: ["Keep the run easy."]
        )

        #expect(day.workoutKind == .lower)
        #expect(day.hasRun)
    }
}
