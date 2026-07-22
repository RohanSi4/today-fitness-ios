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
