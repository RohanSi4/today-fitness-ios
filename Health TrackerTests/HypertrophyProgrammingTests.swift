import Foundation
import Testing
@testable import Health_Tracker

@MainActor
struct HypertrophyProgrammingTests {
    @Test func everyTemplateExerciseExistsInTheCuratedCatalog() {
        let catalog = ExerciseCatalog(cacheURL: hypertrophyTemporaryURL("catalog"))

        for template in HypertrophyProgramming.templates {
            #expect(Set(template.exercises.map(\.exerciseID)).count == template.exercises.count)
            for item in template.exercises {
                #expect(catalog.exercise(id: item.exerciseID) != nil)
                #expect(item.sets >= 1)
            }
        }
    }

    @Test func upperTemplatesMatchAvailableGymEquipment() {
        #expect(HypertrophyProgramming.upperA.exercises.map(\.exerciseID) == [
            "smith-machine-incline-press",
            "chest-supported-t-bar-row",
            "machine-chest-fly",
            "machine-pulldown",
            "single-arm-cable-lateral-raise",
            "overhead-bar-cable-triceps-extension",
            "alternating-standing-dumbbell-curl",
        ])
        #expect(HypertrophyProgramming.upperB.exercises.map(\.exerciseID) == [
            "lat-pulldown",
            "machine-chest-fly",
            "seated-cable-row",
            "single-arm-cable-lateral-raise",
            "straight-bar-triceps-pushdown",
            "bayesian-cable-curl",
            "reverse-pec-deck",
        ])
    }

    @Test func oldSetsWithoutRIRRemainUnknown() throws {
        let id = UUID()
        let json = """
        {"id":"\(id.uuidString)","weight":235,"reps":5,"isComplete":true}
        """

        let set = try JSONDecoder().decode(LoggedSet.self, from: Data(json.utf8))

        #expect(set.rir == nil)
        #expect(set.setType == .working)
        #expect(set.completedAt == nil)
    }

    @Test func topOfRangeSetsEarnTheNextMachineIncrement() {
        let prescription = HypertrophyProgramming.prescription(for: "machine-chest-fly")
        let history = LoggedExercise(
            exerciseID: "machine-chest-fly",
            sets: [
                LoggedSet(weight: 235, reps: 15, isComplete: true),
                LoggedSet(weight: 235, reps: 15, isComplete: true),
            ]
        )

        let suggestion = HypertrophyProgramming.progressionSuggestion(
            history: history,
            prescription: prescription,
            weightIncrement: 5
        )

        #expect(suggestion.contains("+5 lb"))
    }

    @Test func prescriptionsUseLowRepsOnlyWhereLoadingIsStable() {
        let machinePress = HypertrophyProgramming.prescription(for: "machine-chest-press")
        let machineFly = HypertrophyProgramming.prescription(for: "machine-chest-fly")
        let lateralRaise = HypertrophyProgramming.prescription(for: "single-arm-cable-lateral-raise")
        let romanianDeadlift = HypertrophyProgramming.prescription(for: "romanian-deadlift")

        #expect(machinePress.reps == RepRange(lower: 6, upper: 10))
        #expect(machineFly.reps == RepRange(lower: 8, upper: 15))
        #expect(lateralRaise.reps == RepRange(lower: 10, upper: 20))
        #expect(romanianDeadlift.targetRIR == 2...3)
    }

    @Test func upperAndLowerTemplatesAlternateIndependently() {
        let completedUpper = WorkoutSession(
            kind: .upper,
            routineID: "upper-a",
            startedAt: .now,
            endedAt: .now,
            exercises: []
        )

        #expect(HypertrophyProgramming.nextTemplate(for: .upper, workouts: [])?.id == "upper-a")
        #expect(HypertrophyProgramming.nextTemplate(for: .upper, workouts: [completedUpper])?.id == "upper-b")
        #expect(HypertrophyProgramming.nextTemplate(for: .lower, workouts: [completedUpper])?.id == "lower-a")
    }

    @Test func customUpperWorkoutDoesNotFlipTheABRotation() {
        let custom = WorkoutSession(
            kind: .upper,
            startedAt: .now,
            endedAt: .now,
            exercises: []
        )

        #expect(HypertrophyProgramming.nextTemplate(for: .upper, workouts: [custom])?.id == "upper-a")
    }

    @Test func nextSetTargetAddsARepBeforeLoad() throws {
        let catalog = ExerciseCatalog(cacheURL: hypertrophyTemporaryURL("next-set-catalog"))
        let exercise = try #require(catalog.exercise(id: "machine-chest-fly"))
        let history = LoggedExercise(
            exerciseID: exercise.id,
            sets: [LoggedSet(weight: 235, reps: 8, isComplete: true)]
        )
        let current = LoggedExercise(
            exerciseID: exercise.id,
            sets: [LoggedSet(weight: 235, reps: 8, isComplete: false)]
        )

        let target = HypertrophyProgramming.nextSetTarget(
            current: current,
            history: history,
            exercise: exercise
        )

        #expect(target?.weight == 235)
        #expect(target?.reps == 9)
        #expect(target?.confidence == .low)
    }

    @Test func loadOnlyAdvancesAfterTwoComparableTopRangeExposures() throws {
        let catalog = ExerciseCatalog(cacheURL: hypertrophyTemporaryURL("two-exposure-catalog"))
        let exercise = try #require(catalog.exercise(id: "machine-chest-fly"))
        let top = LoggedExercise(
            exerciseID: exercise.id,
            sets: [
                LoggedSet(weight: 235, reps: 15, isComplete: true),
                LoggedSet(weight: 235, reps: 15, isComplete: true),
            ]
        )
        let current = LoggedExercise(
            exerciseID: exercise.id,
            sets: [LoggedSet(weight: 235, reps: 15, isComplete: false)]
        )

        let oneExposure = HypertrophyProgramming.nextSetTarget(
            current: current,
            history: [top],
            exercise: exercise
        )
        let twoExposures = HypertrophyProgramming.nextSetTarget(
            current: current,
            history: [top, top],
            exercise: exercise
        )

        #expect(oneExposure?.weight == 235)
        #expect(twoExposures?.weight == 240)
        #expect(twoExposures?.confidence == .medium)
    }

    @Test func warmupsNeverDriveProgressionOrCoverage() throws {
        let catalog = ExerciseCatalog(cacheURL: hypertrophyTemporaryURL("warmup-catalog"))
        let warmup = LoggedSet(
            weight: 100,
            reps: 20,
            isComplete: true,
            completedAt: .now,
            setType: .warmup
        )
        let logged = LoggedExercise(exerciseID: "machine-chest-fly", sets: [warmup])
        let workout = WorkoutSession(kind: .upper, startedAt: .now, endedAt: .now, exercises: [logged])

        #expect(workout.completedSetCount == 0)
        #expect(workout.performedSetCount == 1)
        #expect(WorkoutMuscleCoverage.completed(in: workout, catalog: catalog).isEmpty)
    }

    @Test func exactTemplateStartsWithItsIdentityAndExerciseList() throws {
        let store = TodayStore(storageURL: hypertrophyTemporaryURL("template-store"))
        let catalog = ExerciseCatalog(cacheURL: hypertrophyTemporaryURL("template-catalog"))

        store.beginWorkout(template: HypertrophyProgramming.upperB, catalog: catalog)

        let workout = try #require(store.activeWorkout)
        #expect(workout.routineID == "upper-b")
        #expect(workout.workoutTitle == "Upper B workout")
        #expect(workout.exercises.map(\.baseExerciseID) == HypertrophyProgramming.upperB.exercises.map(\.exerciseID))
    }

    @Test func coverageKeepsLatsOutstandingUntilAPullingSetIsCompleted() throws {
        let store = TodayStore(storageURL: hypertrophyTemporaryURL("coverage-store"))
        let catalog = ExerciseCatalog(cacheURL: hypertrophyTemporaryURL("coverage-catalog"))
        store.beginWorkout(template: HypertrophyProgramming.upperA, catalog: catalog)
        var workout = try #require(store.activeWorkout)

        workout.exercises[0].sets[0].isComplete = true
        #expect(!WorkoutMuscleCoverage.completed(in: workout, catalog: catalog).contains(.lats))

        let pulldownIndex = try #require(
            workout.exercises.firstIndex { $0.baseExerciseID == "machine-pulldown" }
        )
        workout.exercises[pulldownIndex].sets[0].isComplete = true
        let afterPulldown = WorkoutMuscleCoverage.completed(in: workout, catalog: catalog)
        #expect(afterPulldown.contains(.lats))
        #expect(!afterPulldown.contains(.biceps))

        let curlIndex = try #require(
            workout.exercises.firstIndex { $0.baseExerciseID == "alternating-standing-dumbbell-curl" }
        )
        workout.exercises[curlIndex].sets[0].isComplete = true
        #expect(WorkoutMuscleCoverage.completed(in: workout, catalog: catalog).contains(.biceps))
    }
}

private func hypertrophyTemporaryURL(_ name: String) -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("today-hypertrophy-\(name)-\(UUID().uuidString).json")
}
