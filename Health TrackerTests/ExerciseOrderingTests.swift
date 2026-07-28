import Testing
@testable import Health_Tracker

struct ExerciseOrderingTests {
    @Test func draggingLastExerciseUpPlacesItBeforeTheCrossedCard() {
        var exercises = fixtures
        let draggedID = exercises[3].id
        let targetID = exercises[1].id

        ExerciseOrdering.move(draggedID, over: targetID, in: &exercises)

        #expect(exercises.map(\.exerciseID) == ["a", "d", "b", "c"])
    }

    @Test func draggingFirstExerciseDownPlacesItAfterTheCrossedCard() {
        var exercises = fixtures
        let draggedID = exercises[0].id
        let targetID = exercises[2].id

        ExerciseOrdering.move(draggedID, over: targetID, in: &exercises)

        #expect(exercises.map(\.exerciseID) == ["b", "c", "a", "d"])
    }

    private var fixtures: [LoggedExercise] {
        ["a", "b", "c", "d"].map { LoggedExercise(exerciseID: $0, sets: []) }
    }
}
