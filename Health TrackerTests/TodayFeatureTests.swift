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

    @Test func temporaryStoresCannotReachTheRealCoachByDefault() {
        let store = TodayStore(storageURL: temporaryURL("isolated-sync"))

        #expect(!store.permitsExternalCoachSync)
    }

    @Test func anExplicitTestSyncReceivesFinishedWork() throws {
        let sync = CoachSyncSpy()
        let store = TodayStore(storageURL: temporaryURL("sync-spy"), syncService: sync)
        let catalog = ExerciseCatalog(cacheURL: temporaryURL("sync-spy-catalog"))
        store.beginWorkout(kind: .upper, catalog: catalog)
        var workout = try #require(store.activeWorkout)
        workout.exercises[0].sets[0].isComplete = true
        store.updateActiveWorkout(workout)

        _ = store.finishActiveWorkout()

        #expect(store.permitsExternalCoachSync)
        #expect(sync.scheduledSnapshots.count == 1)
        #expect(sync.scheduledSnapshots[0].workouts.count == 1)
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
        let storeURL = temporaryURL("delete-workout")
        let store = TodayStore(storageURL: storeURL)
        let catalog = ExerciseCatalog(cacheURL: temporaryURL("delete-catalog"))
        store.beginWorkout(kind: .upper, catalog: catalog)
        var workout = try #require(store.activeWorkout)
        workout.exercises[0].sets[0].isComplete = true
        store.updateActiveWorkout(workout)
        let finished = try #require(store.finishActiveWorkout())

        store.deleteWorkout(id: finished.id)

        #expect(store.workouts.isEmpty)
        #expect(store.syncSnapshot.deletedWorkoutIDs == [finished.id])

        let relaunched = TodayStore(storageURL: storeURL)
        #expect(relaunched.syncSnapshot.deletedWorkoutIDs == [finished.id])
    }

    @Test func finishedWorkoutCanBeReopenedWithoutLosingSets() throws {
        let store = TodayStore(storageURL: temporaryURL("reopen-workout"))
        let catalog = ExerciseCatalog(cacheURL: temporaryURL("reopen-catalog"))
        store.beginWorkout(template: HypertrophyProgramming.upperA, catalog: catalog)
        var workout = try #require(store.activeWorkout)
        workout.exercises[0].sets[0].isComplete = true
        workout.exercises[0].sets[0].completedAt = .now
        store.updateActiveWorkout(workout)
        let finished = try #require(store.finishActiveWorkout())

        #expect(store.reopenWorkout(id: finished.id))
        #expect(store.workouts.isEmpty)
        #expect(store.activeWorkout?.id == finished.id)
        #expect(store.activeWorkout?.endedAt == nil)
        #expect(store.activeWorkout?.exercises[0].sets[0].completedAt != nil)
    }

    @Test func completedWorkoutCorrectionsPersist() throws {
        let url = temporaryURL("correct-workout")
        let store = TodayStore(storageURL: url)
        let catalog = ExerciseCatalog(cacheURL: temporaryURL("correct-catalog"))
        store.beginWorkout(kind: .upper, catalog: catalog)
        var workout = try #require(store.activeWorkout)
        workout.exercises[0].sets[0].isComplete = true
        store.updateActiveWorkout(workout)
        var finished = try #require(store.finishActiveWorkout())
        finished.exercises[0].sets[0].reps = 11
        finished.exercises[0].sets[0].setType = .backoff

        store.updateWorkout(finished)

        let reopened = TodayStore(storageURL: url)
        #expect(reopened.workouts[0].exercises[0].sets[0].reps == 11)
        #expect(reopened.workouts[0].exercises[0].sets[0].setType == .backoff)
    }

    @Test func routineEditsAndGoalWeightPersist() throws {
        let url = temporaryURL("routine-persistence")
        let store = TodayStore(storageURL: url)
        var routine = try #require(store.routine(id: "upper-a"))
        routine.title = "Upper Prime"
        routine.exercises[0].sets = 3

        store.updateRoutine(routine)
        store.updateGoalWeight(181.5)

        let reopened = TodayStore(storageURL: url)
        #expect(reopened.routine(id: "upper-a")?.title == "Upper Prime")
        #expect(reopened.routine(id: "upper-a")?.exercises[0].sets == 3)
        #expect(reopened.goalWeight == 181.5)
    }

    @Test func warmupOnlyWorkoutCannotFinish() throws {
        let store = TodayStore(storageURL: temporaryURL("warmup-only"))
        let catalog = ExerciseCatalog(cacheURL: temporaryURL("warmup-only-catalog"))
        store.beginWorkout(kind: .upper, catalog: catalog)
        var workout = try #require(store.activeWorkout)
        workout.exercises[0].sets[0].setType = .warmup
        workout.exercises[0].sets[0].isComplete = true
        workout.exercises[0].sets[0].completedAt = .now
        store.updateActiveWorkout(workout)

        #expect(store.finishActiveWorkout() == nil)
        #expect(store.activeWorkout != nil)
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

@MainActor
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

    @Test func planValidationAllowsBridgeDaysButRejectsStaleOrFuturePayloads() {
        let valid = TrainingPlan(
            weekStart: "2026-07-20",
            weekEnd: "2026-07-26",
            prescribedMiles: 35.5,
            days: [
                TrainingPlanDay(
                    date: "2026-07-21",
                    dayLabel: "Tue 7/21",
                    text: "6 mile run + lower body lift",
                    isKeyDay: false,
                    details: ["Keep it easy."]
                ),
            ]
        )
        let invalid = TrainingPlan(
            weekStart: valid.weekStart,
            weekEnd: valid.weekEnd,
            prescribedMiles: valid.prescribedMiles,
            days: [
                TrainingPlanDay(
                    date: "2027-01-01",
                    dayLabel: "Bad",
                    text: "run",
                    isKeyDay: false,
                    details: []
                ),
            ]
        )
        let bridged = TrainingPlan(
            weekStart: "2026-08-10",
            weekEnd: "2026-08-16",
            prescribedMiles: 38,
            days: [
                TrainingPlanDay(
                    date: "2026-08-09",
                    dayLabel: "Sun 8/9",
                    text: "13 mile long run",
                    isKeyDay: true,
                    details: []
                ),
            ]
        )
        let tooOld = TrainingPlan(
            weekStart: bridged.weekStart,
            weekEnd: bridged.weekEnd,
            prescribedMiles: bridged.prescribedMiles,
            days: [
                TrainingPlanDay(
                    date: "2026-08-02",
                    dayLabel: "Sun 8/2",
                    text: "8 mile run",
                    isKeyDay: true,
                    details: []
                ),
            ]
        )

        #expect(TrainingPlanService.isPlausible(valid))
        #expect(TrainingPlanService.isPlausible(bridged))
        #expect(!TrainingPlanService.isPlausible(tooOld))
        #expect(!TrainingPlanService.isPlausible(invalid))
    }
}

struct PlanProgressPresentationTests {
    @Test func completedRunInstructionsDisappearWhileLiftAndSwimStayActionable() {
        let day = mixedDay()

        let tasks = day.remainingTasks(runCompleted: true, liftCompleted: false)
        let details = day.remainingDetails(runCompleted: true, liftCompleted: false)

        #expect(tasks == ["lower body lift", "swim"])
        #expect(!details.contains("Keep the run easy and conversational."))
        #expect(!details.contains("Run outdoors in the morning."))
        #expect(!details.contains("Take a gel around 40 minutes."))
        #expect(details.contains("Complete lower body lift #1 as the main lower session."))
        #expect(details.contains("Skip heavy calf work in this lift."))
        #expect(details.contains("Swim 35 to 40 minutes, technique only with no hard sets."))
        #expect(details.contains("Count strokes: aim for 14 per 25 yard length, holding your time per length."))
    }

    @Test func completedLiftInstructionsDisappearWhileTheRunAndSwimStay() {
        let day = mixedDay()

        let tasks = day.remainingTasks(runCompleted: false, liftCompleted: true)
        let details = day.remainingDetails(runCompleted: false, liftCompleted: true)

        #expect(tasks == ["5 mile run", "swim"])
        #expect(details.contains("Keep the run easy and conversational."))
        #expect(!details.contains("Complete lower body lift #1 as the main lower session."))
        #expect(!details.contains("Skip heavy calf work in this lift."))
        #expect(details.contains("Swim 35 to 40 minutes, technique only with no hard sets."))
    }

    @Test func aSwimStillRemainsAfterTrackedRunAndLiftWorkAreDone() {
        let day = mixedDay()

        #expect(day.remainingTasks(runCompleted: true, liftCompleted: true) == ["swim"])
        #expect(
            day.remainingDetails(runCompleted: true, liftCompleted: true) == [
                "Swim 35 to 40 minutes, technique only with no hard sets.",
                "Count strokes: aim for 14 per 25 yard length, holding your time per length.",
            ]
        )
    }

    @Test func unknownFutureInstructionsArePreservedRatherThanSilentlyHidden() {
        let day = TrainingPlanDay(
            date: "2026-08-09",
            dayLabel: "Sun 8/9",
            text: "5 mile run",
            isKeyDay: false,
            details: ["New coach instruction the app does not classify yet."]
        )

        #expect(day.remainingDetails(runCompleted: true, liftCompleted: false) == day.details)
    }

    @Test func postRunSummaryIsFactualAndShowsPlanAndWeeklyImpact() {
        let start = Date(timeIntervalSince1970: 1_786_200_000)
        let run = RunningWorkoutSummary(
            id: UUID(),
            startedAt: start,
            endedAt: start.addingTimeInterval(2_400),
            miles: 5.1,
            duration: 2_400
        )
        let summary = PostRunSummary(
            run: run,
            plannedMiles: 5,
            completedWeekMiles: 12,
            prescribedWeekMiles: 35
        )

        #expect(summary.distance == "5.1 mi")
        #expect(summary.duration == "40m")
        #expect(summary.pace == "7:51")
        #expect(summary.planInsight == "You matched today’s 5 mile outline.")
        #expect(summary.weekProgress == 12.0 / 35.0)
        #expect(summary.weekProgressLabel == "12 of 35 mi")
        #expect(summary.weekInsight == "This run supplied 15% of the weekly outline. 23 mi remain this week.")
    }

    private func mixedDay() -> TrainingPlanDay {
        TrainingPlanDay(
            date: "2026-08-09",
            dayLabel: "Sun 8/9",
            text: "5 mile run + lower body lift + swim",
            isKeyDay: false,
            details: [
                "Keep the run easy and conversational.",
                "Run outdoors in the morning.",
                "Take a gel around 40 minutes.",
                "Complete lower body lift #1 as the main lower session.",
                "Skip heavy calf work in this lift.",
                "Swim 35 to 40 minutes, technique only with no hard sets.",
                "Count strokes: aim for 14 per 25 yard length, holding your time per length.",
            ]
        )
    }
}

@MainActor
struct WeeklyTrainingSnapshotTests {
    @Test func bridgeDayRemainsVisibleWithoutPollutingTheDeclaredWeek() throws {
        let calendar = utcCalendar
        let bridgeDate = try #require(date("2026-08-09T08:00:00Z"))
        let run = RunningWorkoutSummary(
            id: UUID(),
            startedAt: bridgeDate,
            endedAt: bridgeDate.addingTimeInterval(7_800),
            miles: 13,
            duration: 7_800
        )
        let plan = TrainingPlan(
            weekStart: "2026-08-10",
            weekEnd: "2026-08-16",
            prescribedMiles: 38,
            days: [
                TrainingPlanDay(
                    date: "2026-08-09",
                    dayLabel: "Sun 8/9",
                    text: "13 mile long run + optional walk",
                    isKeyDay: true,
                    details: ["Keep the long run conversational."]
                ),
                TrainingPlanDay(
                    date: "2026-08-10",
                    dayLabel: "Mon 8/10",
                    text: "4 mile run",
                    isKeyDay: false,
                    details: []
                ),
            ]
        )

        let snapshot = WeeklyTrainingBuilder.build(
            plan: plan,
            runs: [run],
            lifts: [],
            now: bridgeDate,
            calendar: calendar
        )

        #expect(snapshot.day(for: bridgeDate, calendar: calendar)?.runCompleted == true)
        #expect(!snapshot.containsInDeclaredWeek(bridgeDate, calendar: calendar))
        #expect(snapshot.completedMiles == 0)
        #expect(snapshot.completedRuns == 0)
        #expect(snapshot.startDate == date("2026-08-10T00:00:00Z"))
        #expect(snapshot.endDate == date("2026-08-16T00:00:00Z"))
    }

    @Test func weeklySnapshotCombinesPlanRunsAndLifts() throws {
        let calendar = utcCalendar
        let now = try #require(date("2026-07-22T12:00:00Z"))
        let runStart = try #require(date("2026-07-22T08:00:00Z"))
        let plan = samplePlan(todayText: "5 mile run + upper body lift")
        let run = RunningWorkoutSummary(
            id: UUID(),
            startedAt: runStart,
            endedAt: runStart.addingTimeInterval(2_400),
            miles: 5.1,
            duration: 2_400
        )
        let lift = WorkoutSession(
            kind: .upper,
            startedAt: runStart.addingTimeInterval(4_000),
            endedAt: runStart.addingTimeInterval(6_000),
            exercises: [
                LoggedExercise(
                    exerciseID: "machine-chest-fly",
                    sets: [
                        LoggedSet(weight: 235, reps: 5, isComplete: true),
                        LoggedSet(weight: 235, reps: 4, isComplete: true),
                    ]
                ),
            ]
        )

        let snapshot = WeeklyTrainingBuilder.build(
            plan: plan,
            runs: [run],
            lifts: [lift],
            now: now,
            calendar: calendar
        )
        let today = try #require(snapshot.day(for: now, calendar: calendar))

        #expect(today.runCompleted)
        #expect(today.liftCompleted)
        #expect(today.isFullyComplete)
        #expect(snapshot.completedMiles == 5.1)
        #expect(snapshot.completedRuns == 1)
        #expect(snapshot.completedLifts == 1)
        #expect(snapshot.workingSets == 2)
    }

    @Test func widgetPrioritizesWeightThenShowsRemainingWorkThenCompletion() throws {
        let calendar = utcCalendar
        let now = try #require(date("2026-07-22T12:00:00Z"))
        let plan = samplePlan(todayText: "5 mile run + lower body lift")
        let emptyWeek = WeeklyTrainingBuilder.build(
            plan: plan,
            runs: [],
            lifts: [],
            now: now,
            calendar: calendar
        )
        let emptyDay = try #require(emptyWeek.day(for: now, calendar: calendar))

        let weightState = TodayWidgetPublisher.makeSnapshot(
            weightLogged: false,
            day: emptyDay,
            week: emptyWeek,
            now: now,
            calendar: calendar
        )
        #expect(weightState.phase == .weight)
        #expect(weightState.headline == "Log morning weight")
        #expect(weightState.deepLink.host == "weight")

        let planState = TodayWidgetPublisher.makeSnapshot(
            weightLogged: true,
            day: emptyDay,
            week: emptyWeek,
            now: now,
            calendar: calendar
        )
        #expect(planState.phase == .plan)
        #expect(planState.headline == "Run + strength")
        #expect(planState.detail == "Open Today for the private plan")

        let runStart = try #require(date("2026-07-22T08:00:00Z"))
        let run = RunningWorkoutSummary(
            id: UUID(),
            startedAt: runStart,
            endedAt: runStart.addingTimeInterval(2_400),
            miles: 5,
            duration: 2_400
        )
        let runWeek = WeeklyTrainingBuilder.build(
            plan: plan,
            runs: [run],
            lifts: [],
            now: now,
            calendar: calendar
        )
        let runDay = try #require(runWeek.day(for: now, calendar: calendar))
        let remainingState = TodayWidgetPublisher.makeSnapshot(
            weightLogged: true,
            day: runDay,
            week: runWeek,
            now: now,
            calendar: calendar
        )
        #expect(remainingState.phase == .remaining)
        #expect(remainingState.headline == "Strength remaining")
        #expect(remainingState.detail == "Open Today for the private plan")
        #expect(remainingState.deepLink.host == "workout")

        let lift = WorkoutSession(
            kind: .lower,
            startedAt: runStart.addingTimeInterval(4_000),
            endedAt: runStart.addingTimeInterval(5_000),
            exercises: [
                LoggedExercise(
                    exerciseID: "leg-extension",
                    sets: [LoggedSet(weight: 100, reps: 10, isComplete: true)]
                ),
            ]
        )
        let doneWeek = WeeklyTrainingBuilder.build(
            plan: plan,
            runs: [run],
            lifts: [lift],
            now: now,
            calendar: calendar
        )
        let doneDay = try #require(doneWeek.day(for: now, calendar: calendar))
        let doneState = TodayWidgetPublisher.makeSnapshot(
            weightLogged: true,
            day: doneDay,
            week: doneWeek,
            now: now,
            calendar: calendar
        )
        #expect(doneState.phase == .done)
        #expect(doneState.headline == "Done for the day")
        #expect(doneState.detail == "Everything is checked off")
        #expect(doneState.deepLink.host == "history")
    }

    @Test func liveActivityShowsPlanTasksAndEndsWhenTrainingIsComplete() throws {
        let calendar = utcCalendar
        let now = try #require(date("2026-07-22T12:00:00Z"))
        let plan = samplePlan(todayText: "5 mile run + lower body lift")
        let runStart = try #require(date("2026-07-22T08:00:00Z"))
        let run = RunningWorkoutSummary(
            id: UUID(),
            startedAt: runStart,
            endedAt: runStart.addingTimeInterval(2_400),
            miles: 5,
            duration: 2_400
        )
        let lift = WorkoutSession(
            kind: .lower,
            startedAt: runStart.addingTimeInterval(4_000),
            endedAt: runStart.addingTimeInterval(5_000),
            exercises: [
                LoggedExercise(
                    exerciseID: "leg-extension",
                    sets: [LoggedSet(weight: 100, reps: 10, isComplete: true)]
                ),
            ]
        )
        let week = WeeklyTrainingBuilder.build(
            plan: plan,
            runs: [run],
            lifts: [lift],
            now: now,
            calendar: calendar
        )
        let day = try #require(week.day(for: now, calendar: calendar))
        let weightFirstSnapshot = TodayWidgetPublisher.makeSnapshot(
            weightLogged: false,
            day: day,
            week: week,
            now: now,
            calendar: calendar
        )

        let state = TodayLiveActivityStateBuilder.make(
            snapshot: weightFirstSnapshot,
            day: day,
            week: week,
            activeWorkout: nil,
            now: now
        )

        #expect(state.phase == .done)
        #expect(state.tasks.map(\.title) == ["5 mi run", "Lower"])
        let allTasksComplete = state.tasks.allSatisfy(\.isComplete)
        #expect(allTasksComplete)
        #expect(try JSONDecoder().decode(
            TodaySessionAttributes.ContentState.self,
            from: JSONEncoder().encode(state)
        ) == state)
    }

    @Test func liveActivityUsesActiveStrengthProgressWithoutMarkingTheDayDone() throws {
        let calendar = utcCalendar
        let now = try #require(date("2026-07-22T12:00:00Z"))
        let plan = samplePlan(todayText: "5 mile run + lower body lift")
        let week = WeeklyTrainingBuilder.build(
            plan: plan,
            runs: [],
            lifts: [],
            now: now,
            calendar: calendar
        )
        let day = try #require(week.day(for: now, calendar: calendar))
        let snapshot = TodayWidgetPublisher.makeSnapshot(
            weightLogged: true,
            day: day,
            week: week,
            now: now,
            calendar: calendar
        )
        let active = WorkoutSession(
            kind: .lower,
            startedAt: now,
            endedAt: nil,
            exercises: [
                LoggedExercise(
                    exerciseID: "leg-extension",
                    sets: [LoggedSet(weight: 100, reps: 10, isComplete: true)]
                ),
            ]
        )

        let state = TodayLiveActivityStateBuilder.make(
            snapshot: snapshot,
            day: day,
            week: week,
            activeWorkout: active,
            now: now
        )

        #expect(state.phase == .remaining)
        #expect(state.headline == "Lower workout in progress")
        #expect(state.detail == "1 working set checked off")
    }

    @Test func widgetPayloadCannotContainExactWeightOrExerciseDetails() throws {
        let calendar = utcCalendar
        let now = try #require(date("2026-07-22T12:00:00Z"))
        let plan = samplePlan(todayText: "5 mile run + lower body lift")
        let runStart = try #require(date("2026-07-22T08:00:00Z"))
        let run = RunningWorkoutSummary(
            id: UUID(),
            startedAt: runStart,
            endedAt: runStart.addingTimeInterval(2_400),
            miles: 5,
            duration: 2_400
        )
        let lift = WorkoutSession(
            kind: .lower,
            startedAt: runStart.addingTimeInterval(4_000),
            endedAt: runStart.addingTimeInterval(5_000),
            exercises: [
                LoggedExercise(
                    exerciseID: "leg-extension",
                    sets: [LoggedSet(weight: 100, reps: 10, isComplete: true)]
                ),
            ]
        )
        let week = WeeklyTrainingBuilder.build(
            plan: plan,
            runs: [run],
            lifts: [lift],
            now: now,
            calendar: calendar
        )
        let day = try #require(week.day(for: now, calendar: calendar))
        let snapshot = TodayWidgetPublisher.makeSnapshot(
            weightLogged: true,
            day: day,
            week: week,
            now: now,
            calendar: calendar
        )
        let encoded = try JSONEncoder().encode(snapshot)
        let json = try #require(String(data: encoded, encoding: .utf8))
        let normalized = json.lowercased()

        #expect(!json.contains("184.4"))
        #expect(!normalized.contains("machine-chest-fly"))
        #expect(!normalized.contains("leg-extension"))
        #expect(!normalized.contains("leg extension"))
        #expect(!normalized.contains("exercise"))
        #expect(!normalized.contains("pounds"))
        #expect(!normalized.contains("lower body lift"))
        #expect(!normalized.contains("5 mile run"))
        #expect(!normalized.contains("10 reps"))
        #expect(!normalized.contains("1 set"))
        #expect(!normalized.contains("5 mi in 40m"))
    }

    @Test func theTimeTrialDayCountsAsDoneOnceTheHardEffortIsRun() throws {
        // The real Jul 29 2026 case. The plan read "6.1 mile run" — 2mi warmup, a 5K
        // all-out, and a cooldown mile the plan itself said to WALK back to the car.
        // Three separate watch recordings came to 5.39mi, or 88.4% of 6.1, and the old
        // flat 90% bar meant the widget spent the rest of the day asking for another
        // run after a maximal effort.
        let calendar = utcCalendar
        let now = try #require(date("2026-07-22T18:00:00Z"))
        let plan = keyDayPlan(todayText: "6.1 mile run")
        let start = try #require(date("2026-07-22T15:00:00Z"))
        let warmup = RunningWorkoutSummary(
            id: UUID(), startedAt: start, endedAt: start.addingTimeInterval(1_270),
            miles: 2.01, duration: 1_270
        )
        let timeTrial = RunningWorkoutSummary(
            id: UUID(),
            startedAt: start.addingTimeInterval(1_500),
            endedAt: start.addingTimeInterval(2_764),
            miles: 3.11, duration: 1_264
        )
        let jogBack = RunningWorkoutSummary(
            id: UUID(),
            startedAt: start.addingTimeInterval(3_000),
            endedAt: start.addingTimeInterval(3_135),
            miles: 0.27, duration: 135
        )

        let snapshot = WeeklyTrainingBuilder.build(
            plan: plan, runs: [warmup, timeTrial, jogBack], lifts: [],
            now: now, calendar: calendar
        )
        let today = try #require(snapshot.day(for: now, calendar: calendar))

        #expect(today.isKeyDay)
        // Summed Doubles: 2.01 + 3.11 + 0.27 is 5.389999999999999, not 5.39.
        #expect(abs((today.run?.miles ?? 0) - 5.39) < 0.001)
        #expect(today.runCompleted)
        #expect(today.isFullyComplete)
    }

    @Test func anEasyDayStillHasToBeMostlyRun() throws {
        // The looser bar is for key days, whose total is padded with warmup and
        // cooldown. On an easy day the mileage IS the session, so half of it is not
        // the day done — otherwise the tick stops meaning anything.
        let calendar = utcCalendar
        let now = try #require(date("2026-07-22T18:00:00Z"))
        let plan = samplePlan(todayText: "6 mile run")
        let start = try #require(date("2026-07-22T15:00:00Z"))
        let short = RunningWorkoutSummary(
            id: UUID(), startedAt: start, endedAt: start.addingTimeInterval(1_800),
            miles: 3.0, duration: 1_800
        )
        let most = RunningWorkoutSummary(
            id: UUID(), startedAt: start, endedAt: start.addingTimeInterval(2_700),
            miles: 4.7, duration: 2_700
        )

        let bailed = WeeklyTrainingBuilder.build(
            plan: plan, runs: [short], lifts: [], now: now, calendar: calendar
        )
        #expect(try !#require(bailed.day(for: now, calendar: calendar)).runCompleted)

        let closeEnough = WeeklyTrainingBuilder.build(
            plan: plan, runs: [most], lifts: [], now: now, calendar: calendar
        )
        #expect(try #require(closeEnough.day(for: now, calendar: calendar)).runCompleted)
    }

    private func keyDayPlan(todayText: String) -> TrainingPlan {
        let plan = samplePlan(todayText: todayText)
        return TrainingPlan(
            weekStart: plan.weekStart,
            weekEnd: plan.weekEnd,
            prescribedMiles: plan.prescribedMiles,
            days: plan.days.map { day in
                TrainingPlanDay(
                    date: day.date,
                    dayLabel: day.dayLabel,
                    text: day.text,
                    isKeyDay: day.date == "2026-07-22",
                    details: day.details
                )
            }
        )
    }

    private func samplePlan(todayText: String) -> TrainingPlan {
        TrainingPlan(
            weekStart: "2026-07-20",
            weekEnd: "2026-07-26",
            prescribedMiles: 35,
            days: [
                TrainingPlanDay(
                    date: "2026-07-20",
                    dayLabel: "Mon 7/20",
                    text: "Rest",
                    isKeyDay: false,
                    details: []
                ),
                TrainingPlanDay(
                    date: "2026-07-21",
                    dayLabel: "Tue 7/21",
                    text: "4 mile run + upper body lift",
                    isKeyDay: false,
                    details: []
                ),
                TrainingPlanDay(
                    date: "2026-07-22",
                    dayLabel: "Wed 7/22",
                    text: todayText,
                    isKeyDay: true,
                    details: []
                ),
                TrainingPlanDay(
                    date: "2026-07-23",
                    dayLabel: "Thu 7/23",
                    text: "Rest",
                    isKeyDay: false,
                    details: []
                ),
                TrainingPlanDay(
                    date: "2026-07-24",
                    dayLabel: "Fri 7/24",
                    text: "6 mile run + lower body lift",
                    isKeyDay: false,
                    details: []
                ),
                TrainingPlanDay(
                    date: "2026-07-25",
                    dayLabel: "Sat 7/25",
                    text: "12 mile long run",
                    isKeyDay: true,
                    details: []
                ),
                TrainingPlanDay(
                    date: "2026-07-26",
                    dayLabel: "Sun 7/26",
                    text: "Rest",
                    isKeyDay: false,
                    details: []
                ),
            ]
        )
    }

    private func date(_ value: String) -> Date? {
        ISO8601DateFormatter().date(from: value)
    }

    private var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }
}

@MainActor
private final class CoachSyncSpy: CoachSyncing {
    private(set) var scheduledSnapshots: [StoredTodayData] = []

    func scheduleSync(snapshot: StoredTodayData, catalog: ExerciseCatalog) {
        scheduledSnapshots.append(snapshot)
    }

    func sync(snapshot: StoredTodayData, catalog: ExerciseCatalog) async {}
}

@MainActor
struct CoachSyncSecurityTests {
    @Test func pairingAcceptsOnlyTheProductionSyncBoundary() {
        #expect(CoachSyncService.isAllowedEndpoint(
            URL(string: "https://rohansingh04.com/api/fitness/private-sync")!
        ))
        #expect(!CoachSyncService.isAllowedEndpoint(
            URL(string: "https://rohansingh04.com.evil.example/api/fitness/private-sync")!
        ))
        #expect(!CoachSyncService.isAllowedEndpoint(
            URL(string: "http://rohansingh04.com/api/fitness/private-sync")!
        ))
        #expect(!CoachSyncService.isAllowedEndpoint(
            URL(string: "https://rohansingh04.com/api/fitness/private-sync?forward=true")!
        ))
    }
}

@MainActor
struct WatchWorkoutTests {
    @Test func runDistanceExtractionIgnoresStrideDurations() {
        #expect(WatchWorkoutService.runMiles(from: "Easy 6 mile run + 4×20s strides") == 6)
        #expect(WatchWorkoutService.runMiles(from: "13.5 mi long run outdoors") == 13.5)
        #expect(WatchWorkoutService.runMiles(from: "Rest + upper body lift") == nil)
    }

    /// A fragment of a longer number is not a distance.
    ///
    /// The old pattern let the engine backtrack into the middle of one:
    /// "100.1 miles" came back as 1.0 and "120.5 miles" as 5.0. Both are
    /// plausible-looking values that would have gone to the Watch as a real
    /// distance goal, which is the worst way for a parser to fail. Refusing the
    /// match sends it down the "no safe distance goal" path instead.
    @Test func aDistanceInsideALongerNumberIsRefusedRatherThanTruncated() {
        #expect(WatchWorkoutService.runMiles(from: "100.1 miles") == nil)
        #expect(WatchWorkoutService.runMiles(from: "120.5 miles") == nil)
        #expect(WatchWorkoutService.runMiles(from: "100 mile run") == nil)
        #expect(WatchWorkoutService.runMiles(from: "105 miles") == nil)
        // The distances he actually runs are untouched.
        #expect(WatchWorkoutService.runMiles(from: "26.2 mile race") == 26.2)
        #expect(WatchWorkoutService.runMiles(from: "0.5 mile jog") == 0.5)
        #expect(WatchWorkoutService.runMiles(from: "20 mile long run") == 20)
    }

    @Test func indoorAndOutdoorPlansMapToTheRightWatchLocation() {
        #expect(WatchWorkoutService.location(from: "6 mile treadmill run") == .indoor)
        #expect(WatchWorkoutService.location(from: "6 mile run outdoors") == .outdoor)
        #expect(WatchWorkoutService.location(from: "6 mile run") == .unknown)
    }

    @Test func scheduledRunIDsAreStablePerPlanDate() {
        #expect(WatchWorkoutService.planID(for: "2026-07-21") == WatchWorkoutService.planID(for: "2026-07-21"))
        #expect(WatchWorkoutService.planID(for: "2026-07-21") != WatchWorkoutService.planID(for: "2026-07-22"))
    }
}
