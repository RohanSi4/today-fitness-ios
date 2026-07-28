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
            startedAt: .now,
            endedAt: .now,
            exercises: []
        )

        #expect(HypertrophyProgramming.nextTemplate(for: .upper, workouts: [])?.id == "upper-a")
        #expect(HypertrophyProgramming.nextTemplate(for: .upper, workouts: [completedUpper])?.id == "upper-b")
        #expect(HypertrophyProgramming.nextTemplate(for: .lower, workouts: [completedUpper])?.id == "lower-a")
    }
}

private func hypertrophyTemporaryURL(_ name: String) -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("today-hypertrophy-\(name)-\(UUID().uuidString).json")
}
