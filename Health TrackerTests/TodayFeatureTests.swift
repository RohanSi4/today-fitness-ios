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

    @Test func planValidationRejectsOversizedOrOutOfWeekPayloads() {
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

        #expect(TrainingPlanService.isPlausible(valid))
        #expect(!TrainingPlanService.isPlausible(invalid))
    }
}

@MainActor
struct WeeklyTrainingSnapshotTests {
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
        #expect(planState.headline == "5 mi run + Lower lift")

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
        #expect(remainingState.headline == "Lower lift")
        #expect(remainingState.detail.contains("5 mi in 40m"))
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
        #expect(doneState.detail == "5 mi in 40m · 1 set")
        #expect(doneState.deepLink.host == "history")
    }

    @Test func widgetPayloadCannotContainExactWeightOrExerciseDetails() throws {
        let snapshot = TodayWidgetSnapshot.placeholder
        let encoded = try JSONEncoder().encode(snapshot)
        let json = try #require(String(data: encoded, encoding: .utf8))

        #expect(!json.contains("184.4"))
        #expect(!json.contains("machine-chest-fly"))
        #expect(!json.contains("exercise"))
        #expect(!json.contains("pounds"))
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
