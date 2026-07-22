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
