import ActivityKit
import Combine
import Foundation

@MainActor
final class TodayLiveActivityManager: ObservableObject {
    static let shared = TodayLiveActivityManager()

    @Published private(set) var isPresented = false
    @Published private(set) var isUpdating = false
    @Published private(set) var errorMessage: String?

    /// Set only by tapping "Remove from Lock Screen", and the one thing that
    /// stops the card coming back on its own.
    ///
    /// Without it, `ensurePresented` would re-add the card the moment the app
    /// next came forward, which turns an explicit dismissal into a bug that
    /// looks like the app ignoring him.
    private static let optedOutKey = "today-live-activity-opted-out"
    private var hasOptedOut: Bool {
        get { UserDefaults.standard.bool(forKey: Self.optedOutKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.optedOutKey) }
    }

    private init() {
        refreshPresence()
    }

    /// Puts the card on the Lock Screen without being asked, and puts it back
    /// after iOS has taken it away.
    ///
    /// It used to appear only if he tapped "Pin today to Lock Screen" and then
    /// ended itself as soon as the day's work was done, so the surface he
    /// actually wanted mid-workout was the one least likely to be there. This
    /// runs on launch, on foreground, and whenever a workout starts.
    ///
    /// **iOS caps a Live Activity at roughly 8 hours** and there is no API to
    /// extend that, so "forever" is not something this can promise — the
    /// re-arm on foreground is what makes it feel permanent. The Lock Screen
    /// *widget* is the surface with no expiry at all.
    func ensurePresented(_ state: TodaySessionAttributes.ContentState) async {
        guard !hasOptedOut else { return }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        if !Activity<TodaySessionAttributes>.activities.isEmpty {
            await updateIfPresented(with: state)
            return
        }

        // Silent on failure, unlike `present`. This was not asked for at this
        // moment, so it has no business raising an error into the Today screen.
        _ = try? Activity.request(
            attributes: TodaySessionAttributes(),
            content: content(for: state),
            pushType: nil
        )
        refreshPresence()
    }

    func refreshPresence() {
        isPresented = !Activity<TodaySessionAttributes>.activities.isEmpty
    }

    func present(_ state: TodaySessionAttributes.ContentState) async {
        errorMessage = nil
        isUpdating = true
        hasOptedOut = false
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
            // Finishing the day used to end the card half an hour later. That is
            // defensible on its own and wrong next to a card he wants standing:
            // the day goes `.done` most evenings, so the thing kept retiring
            // itself and having to be re-pinned by hand. Only "Remove from Lock
            // Screen" ends it now.
            await activity.update(content(for: state))
        }
        refreshPresence()
    }

    func remove() async {
        errorMessage = nil
        isUpdating = true
        hasOptedOut = true
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
        catalog: ExerciseCatalog,
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
        let workout = TodayWidgetWorkoutBuilder.make(from: store.activeWorkout, catalog: catalog)
        let snapshot = TodayWidgetPublisher.makeSnapshot(
            weightLogged: store.weights.contains { calendar.isDate($0.date, inSameDayAs: now) },
            day: day,
            week: week,
            workout: workout,
            planLine: plan?.days.first {
                $0.date == TodayWidgetSnapshot.dayKey(for: now, calendar: calendar)
            }?.text,
            recap: TodayWidgetPublisher.recap(
                lift: store.workouts.first {
                    calendar.isDate($0.endedAt ?? $0.startedAt, inSameDayAs: now)
                },
                day: day,
                catalog: catalog
            ),
            now: now,
            calendar: calendar
        )
        return make(
            snapshot: snapshot,
            day: day,
            week: week,
            workout: workout,
            now: now
        )
    }

    static func make(
        snapshot: TodayWidgetSnapshot,
        day: WeeklyDaySnapshot?,
        week: WeeklyTrainingSnapshot,
        workout: TodayWidgetWorkout?,
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
        if let workout {
            headline = "\(workout.title) in progress"
            detail = workout.nextExercise.map { "Next: \($0)" }
                ?? "\(workout.completedSets) of \(workout.plannedSets) sets down"
            symbolName = "dumbbell.fill"
        } else if let recap = snapshot.recap {
            // After the lift, the card becomes the reminder of what it was.
            headline = "\(recap.title) done"
            detail = recap.summary
            symbolName = "checkmark.circle.fill"
        } else {
            headline = snapshot.headline
            // The coach's own words beat "Open Today for the private plan",
            // which is all this could say on a screen he cannot unlock.
            detail = snapshot.planLine ?? snapshot.detail
            symbolName = snapshot.symbolName
        }

        let phase: TodayWidgetPhase
        if workout != nil {
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
            plannedMiles: week.prescribedMiles,
            restAnchor: workout?.restAnchor,
            nextExercise: workout?.nextExercise,
            completedSets: workout?.completedSets ?? 0,
            plannedSets: workout?.plannedSets ?? 0
        )
    }

    private static func formatMiles(_ miles: Double) -> String {
        miles.formatted(.number.precision(.fractionLength(0...1)))
    }
}
