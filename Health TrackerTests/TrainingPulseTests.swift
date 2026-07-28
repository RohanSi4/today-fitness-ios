import Foundation
import Testing
@testable import Health_Tracker

@MainActor
struct TrainingPulseTests {
    @Test func combinesMuscleHeadsWithoutDoubleCountingOneRegion() {
        let catalog = ExerciseCatalog(cacheURL: temporaryPulseURL())
        let workout = WorkoutSession(
            kind: .upper,
            startedAt: .now,
            endedAt: .now,
            exercises: [
                LoggedExercise(
                    exerciseID: "machine-chest-fly",
                    sets: [
                        LoggedSet(weight: 235, reps: 8, isComplete: true),
                        LoggedSet(weight: 235, reps: 7, isComplete: true),
                    ]
                ),
            ]
        )

        let snapshot = TrainingPulseSnapshot.build(workouts: [workout], catalog: catalog)
        let chest = snapshot.regions.first { $0.region == .chest }

        #expect(chest?.estimatedSets == 2)
        #expect(chest?.exposureDays == 1)
        #expect(snapshot.hardSets == 2)
    }

    @Test func secondaryMusclesReceiveFractionalExposure() {
        let catalog = ExerciseCatalog(cacheURL: temporaryPulseURL())
        let workout = WorkoutSession(
            kind: .upper,
            startedAt: .now,
            endedAt: .now,
            exercises: [
                LoggedExercise(
                    exerciseID: "lat-pulldown",
                    sets: [LoggedSet(weight: 155, reps: 8, isComplete: true)]
                ),
            ]
        )

        let snapshot = TrainingPulseSnapshot.build(workouts: [workout], catalog: catalog)
        let back = snapshot.regions.first { $0.region == .back }
        let biceps = snapshot.regions.first { $0.region == .biceps }

        #expect(back?.estimatedSets == 1)
        #expect(biceps?.estimatedSets == 0.55)
    }
}

private func temporaryPulseURL() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("today-pulse-\(UUID().uuidString).json")
}
