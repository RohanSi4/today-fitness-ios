import ActivityKit
import Combine
import Foundation

@MainActor
final class TodayLiveActivityManager: ObservableObject {
    static let shared = TodayLiveActivityManager()

    @Published private(set) var isPresented = false
    @Published private(set) var isUpdating = false
    @Published private(set) var errorMessage: String?

    private init() {
        refreshPresence()
    }

    func refreshPresence() {
        isPresented = !Activity<TodaySessionAttributes>.activities.isEmpty
    }

    func present(_ state: TodaySessionAttributes.ContentState) async {
        errorMessage = nil
        isUpdating = true
        defer { isUpdating = false }

        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            errorMessage = "Allow Live Activities for Today in Settings to use the large Lock Screen card."
            return
        }

        if let current = Activity<TodaySessionAttributes>.activities.first {
            await current.update(content(for: state))
            refreshPresence()
            return
        }

        do {
            _ = try Activity.request(
                attributes: TodaySessionAttributes(),
                content: content(for: state),
                pushType: nil
            )
            refreshPresence()
        } catch {
            errorMessage = "Today could not add the Lock Screen card: \(error.localizedDescription)"
        }
    }

    func updateIfPresented(with state: TodaySessionAttributes.ContentState) async {
        guard !Activity<TodaySessionAttributes>.activities.isEmpty else {
            refreshPresence()
            return
        }

        for activity in Activity<TodaySessionAttributes>.activities {
            if state.phase == .done {
                await activity.end(
                    content(for: state),
                    dismissalPolicy: .after(Date().addingTimeInterval(30 * 60))
                )
            } else {
                await activity.update(content(for: state))
            }
        }
        refreshPresence()
    }

    func remove() async {
        errorMessage = nil
        isUpdating = true
        defer { isUpdating = false }

        for activity in Activity<TodaySessionAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        refreshPresence()
    }

    private func content(
        for state: TodaySessionAttributes.ContentState
    ) -> ActivityContent<TodaySessionAttributes.ContentState> {
        ActivityContent(
            state: state,
            staleDate: Calendar.current.date(byAdding: .day, value: 1, to: .now)
        )
    }
}

@MainActor
enum TodayLiveActivityStateBuilder {
    static func make(
        store: TodayStore,
        plan: TrainingPlan?,
        runs: [RunningWorkoutSummary],
        now: Date = .now,
        calendar: Calendar = .current
    ) -> TodaySessionAttributes.ContentState? {
        guard store.hasReliableData else { return nil }
        let week = WeeklyTrainingBuilder.build(
            plan: plan,
            runs: runs,
            lifts: store.workouts,
            now: now,
            calendar: calendar
        )
        let day = week.day(for: now, calendar: calendar)
        let snapshot = TodayWidgetPublisher.makeSnapshot(
            weightLogged: store.weights.contains { calendar.isDate($0.date, inSameDayAs: now) },
            day: day,
            week: week,
            now: now,
            calendar: calendar
        )
        return make(
            snapshot: snapshot,
            day: day,
            week: week,
            activeWorkout: store.activeWorkout,
            now: now
        )
    }

    static func make(
        snapshot: TodayWidgetSnapshot,
        day: WeeklyDaySnapshot?,
        week: WeeklyTrainingSnapshot,
        activeWorkout: WorkoutSession?,
        now: Date = .now
    ) -> TodaySessionAttributes.ContentState {
        var tasks: [TodayActivityTask] = []

        if let miles = day?.plannedRunMiles {
            tasks.append(TodayActivityTask(
                title: "\(formatMiles(miles)) mi run",
                symbolName: "figure.run",
                isComplete: day?.runCompleted == true
            ))
        }
        if let lift = day?.plannedLift {
            tasks.append(TodayActivityTask(
                title: lift.title,
                symbolName: "dumbbell.fill",
                isComplete: day?.liftCompleted == true
            ))
        }
        if let other = day?.plannedOther, !other.isEmpty {
            tasks.append(TodayActivityTask(
                title: other,
                symbolName: other.localizedCaseInsensitiveContains("swim")
                    ? "figure.pool.swim"
                    : "figure.mixed.cardio",
                isComplete: false
            ))
        }

        let headline: String
        let detail: String
        let symbolName: String
        if let active = activeWorkout {
            headline = "\(active.workoutTitle) in progress"
            let sets = active.completedSetCount
            detail = "\(sets) working \(sets == 1 ? "set" : "sets") checked off"
            symbolName = "dumbbell.fill"
        } else {
            headline = snapshot.headline
            detail = snapshot.detail
            symbolName = snapshot.symbolName
        }

        let phase: TodayWidgetPhase
        if activeWorkout != nil {
            phase = .remaining
        } else if !tasks.isEmpty && tasks.allSatisfy(\.isComplete) {
            phase = .done
        } else {
            phase = snapshot.phase
        }

        return TodaySessionAttributes.ContentState(
            updatedAt: now,
            phase: phase,
            headline: headline,
            detail: detail,
            symbolName: symbolName,
            tasks: Array(tasks.prefix(3)),
            completedMiles: week.completedMiles,
            plannedMiles: week.prescribedMiles
        )
    }

    private static func formatMiles(_ miles: Double) -> String {
        miles.formatted(.number.precision(.fractionLength(0...1)))
    }
}
