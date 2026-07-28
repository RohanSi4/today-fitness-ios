import Combine
import Foundation
import HealthKit
import WidgetKit

struct RunningWorkoutSummary: Codable, Equatable, Identifiable {
    let id: UUID
    let startedAt: Date
    let endedAt: Date
    let miles: Double
    let duration: TimeInterval

    var paceSecondsPerMile: Double? {
        guard miles > 0 else { return nil }
        return duration / miles
    }
}

protocol RunningWorkoutProviding {
    var isHealthDataAvailable: Bool { get }
    func requestWorkoutAuthorization() async throws
    func fetchRunningWorkouts(start: Date, end: Date) async throws -> [RunningWorkoutSummary]
    func startWorkoutMonitoring(onChange: @escaping @Sendable () -> Void)
}

@MainActor
final class RunningWorkoutService: ObservableObject {
    static let shared = RunningWorkoutService()

    @Published private(set) var workouts: [RunningWorkoutSummary] = []
    @Published private(set) var lastUpdated: Date?

    /// True when the last read of Apple Health failed or was refused.
    ///
    /// `refresh` used to drop the error on the floor with `try?`, which left the
    /// week showing a confident "0 of 26.1 miles". That is the same failure the
    /// widget had: nothing on screen distinguished an unread Health store from a
    /// week he genuinely did not run. Only meaningful while `workouts` is still
    /// empty, since a later failure keeps the last good list rather than
    /// clearing it.
    @Published private(set) var lastReadFailed = false

    private let healthStore: any RunningWorkoutProviding
    private var isMonitoring = false

    init(healthStore: any RunningWorkoutProviding = HealthKitManager.shared) {
        self.healthStore = healthStore
    }

    func start() async {
        if ProcessInfo.processInfo.arguments.contains("-useMockData") { return }
        guard healthStore.isHealthDataAvailable else { return }

        // Authorization first. Background delivery cannot be enabled before the
        // Health prompt is answered, so registering the observer first meant a fresh
        // install silently never got watch runs delivered in the background.
        try? await healthStore.requestWorkoutAuthorization()

        if !isMonitoring {
            isMonitoring = true
            healthStore.startWorkoutMonitoring { [weak self] in
                Task { @MainActor in
                    await self?.refresh()
                }
            }
        }
        await refresh()
    }

    func refresh() async {
        guard healthStore.isHealthDataAvailable else { return }
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: .now)
        let start = calendar.date(byAdding: .day, value: -14, to: startOfToday) ?? startOfToday
        let end = Date().addingTimeInterval(60)
        do {
            let fetched = try await healthStore.fetchRunningWorkouts(start: start, end: end)
            workouts = fetched.sorted { $0.startedAt > $1.startedAt }
            lastUpdated = .now
            lastReadFailed = false
        } catch {
            // The list is deliberately left alone. Stale runs beat blank ones,
            // and the flag is what tells the week not to claim a zero.
            lastReadFailed = true
        }
    }

    /// Whether the week's run totals should be presented as fact.
    ///
    /// False only when nothing has ever been read successfully, which is the one
    /// case where a zero on screen is a guess rather than a number.
    var hasTrustworthyRunData: Bool { !(lastReadFailed && lastUpdated == nil) }
}

struct WeeklyDaySnapshot: Identifiable, Equatable {
    let date: Date
    let dateKey: String
    let dayLabel: String
    let plannedRunMiles: Double?
    let plannedLift: WorkoutKind?
    let plannedOther: String?
    let run: RunningWorkoutSummary?
    let lift: WorkoutSession?
    let extraLift: WorkoutSession?

    var id: String { dateKey }
    var runCompleted: Bool {
        guard let plannedRunMiles else { return false }
        return (run?.miles ?? 0) >= max(0.5, plannedRunMiles * 0.9)
    }
    var liftCompleted: Bool { plannedLift != nil && lift != nil }
    var isFullyComplete: Bool {
        let planned = plannedRunMiles != nil || plannedLift != nil
        guard planned else { return false }
        return (plannedRunMiles == nil || runCompleted) && (plannedLift == nil || liftCompleted)
    }
}

struct WeeklyTrainingSnapshot: Equatable {
    let startDate: Date
    let endDate: Date
    let prescribedMiles: Double
    let days: [WeeklyDaySnapshot]

    var completedMiles: Double {
        days.compactMap(\.run).reduce(0) { $0 + $1.miles }
    }

    var completedRuns: Int { days.compactMap(\.run).count }

    var completedLifts: Int {
        days.reduce(0) { total, day in
            total + (day.lift == nil ? 0 : 1) + (day.extraLift == nil ? 0 : 1)
        }
    }

    var workingSets: Int {
        days.reduce(0) { total, day in
            total + (day.lift?.completedSetCount ?? 0) + (day.extraLift?.completedSetCount ?? 0)
        }
    }

    func day(for date: Date, calendar: Calendar = .current) -> WeeklyDaySnapshot? {
        days.first { calendar.isDate($0.date, inSameDayAs: date) }
    }
}

enum WeeklyTrainingBuilder {
    static func build(
        plan: TrainingPlan?,
        runs: [RunningWorkoutSummary],
        lifts: [WorkoutSession],
        now: Date = .now,
        calendar: Calendar = .current
    ) -> WeeklyTrainingSnapshot {
        let plannedDays = plan?.days
            .compactMap { day -> (TrainingPlanDay, Date)? in
                guard let date = date(from: day.date, calendar: calendar) else { return nil }
                return (day, date)
            }
            .sorted { $0.1 < $1.1 }

        let dates: [Date]
        if let plannedDays, !plannedDays.isEmpty {
            dates = plannedDays.map(\.1)
        } else {
            let interval = calendar.dateInterval(of: .weekOfYear, for: now)
            let start = interval?.start ?? calendar.startOfDay(for: now)
            dates = (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
        }

        let days = dates.map { date -> WeeklyDaySnapshot in
            let key = TodayWidgetSnapshot.dayKey(for: date, calendar: calendar)
            let planned = plan?.days.first { $0.date == key }
            let dayRuns = runs.filter { calendar.isDate($0.startedAt, inSameDayAs: date) }
            let combinedRun = combine(dayRuns)
            let dayLifts = lifts
                .filter { calendar.isDate($0.endedAt ?? $0.startedAt, inSameDayAs: date) }
                .sorted { $0.startedAt < $1.startedAt }
            let matchedLift = planned?.workoutKind.flatMap { kind in
                dayLifts.first { $0.kind == kind }
            }
            let extraLift = dayLifts.first { $0.id != matchedLift?.id }

            return WeeklyDaySnapshot(
                date: date,
                dateKey: key,
                dayLabel: date.formatted(.dateTime.weekday(.abbreviated)),
                plannedRunMiles: planned?.plannedRunMiles,
                plannedLift: planned?.workoutKind,
                plannedOther: planned?.isRestOnly == true ? "Recovery" : nil,
                run: combinedRun,
                lift: matchedLift,
                extraLift: extraLift
            )
        }

        return WeeklyTrainingSnapshot(
            startDate: dates.first ?? now,
            endDate: dates.last ?? now,
            prescribedMiles: plan?.prescribedMiles ?? days.compactMap(\.plannedRunMiles).reduce(0, +),
            days: days
        )
    }

    private static func combine(_ runs: [RunningWorkoutSummary]) -> RunningWorkoutSummary? {
        guard let first = runs.min(by: { $0.startedAt < $1.startedAt }),
              let last = runs.max(by: { $0.endedAt < $1.endedAt }) else { return nil }
        return RunningWorkoutSummary(
            id: first.id,
            startedAt: first.startedAt,
            endedAt: last.endedAt,
            miles: runs.reduce(0) { $0 + $1.miles },
            duration: runs.reduce(0) { $0 + $1.duration }
        )
    }

    private static func date(from key: String, calendar: Calendar) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var components = DateComponents()
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        components.year = parts[0]
        components.month = parts[1]
        components.day = parts[2]
        return components.date
    }
}

@MainActor
enum TodayWidgetPublisher {
    static func publish(
        store: TodayStore,
        plan: TrainingPlan?,
        runs: [RunningWorkoutSummary],
        now: Date = .now,
        calendar: Calendar = .current
    ) {
        guard let snapshot = makeSnapshot(
            store: store,
            plan: plan,
            runs: runs,
            now: now,
            calendar: calendar
        ) else { return }

        guard let defaults = UserDefaults(suiteName: TodayWidgetSnapshot.appGroupIdentifier),
              let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: TodayWidgetSnapshot.defaultsKey)
        WidgetCenter.shared.reloadTimelines(ofKind: TodayWidgetSnapshot.widgetKind)
    }

    /// Nil when the store could not read its file. A background launch on a locked
    /// phone - a watch run syncing at 6am - brings the store up empty under
    /// `.completeFileProtection`. Publishing that told the Lock Screen to "Log
    /// morning weight" for a day already logged and zeroed the week's mileage.
    /// Keeping yesterday's payload is strictly better than publishing a lie.
    static func makeSnapshot(
        store: TodayStore,
        plan: TrainingPlan?,
        runs: [RunningWorkoutSummary],
        now: Date = .now,
        calendar: Calendar = .current
    ) -> TodayWidgetSnapshot? {
        guard store.hasReliableData else { return nil }
        let week = WeeklyTrainingBuilder.build(
            plan: plan,
            runs: runs,
            lifts: store.workouts,
            now: now,
            calendar: calendar
        )
        return makeSnapshot(
            weightLogged: store.weights.contains { calendar.isDate($0.date, inSameDayAs: now) },
            day: week.day(for: now, calendar: calendar),
            week: week,
            now: now,
            calendar: calendar
        )
    }

    static func makeSnapshot(
        weightLogged: Bool,
        day: WeeklyDaySnapshot?,
        week: WeeklyTrainingSnapshot,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> TodayWidgetSnapshot {
        let display = displayState(weightLogged: weightLogged, day: day)
        return TodayWidgetSnapshot(
            generatedAt: now,
            dateKey: TodayWidgetSnapshot.dayKey(for: now, calendar: calendar),
            phase: display.phase,
            headline: display.headline,
            detail: display.detail,
            symbolName: display.symbol,
            deepLink: display.deepLink,
            week: TodayWidgetWeek(
                completedMiles: week.completedMiles,
                plannedMiles: week.prescribedMiles,
                completedRuns: week.completedRuns,
                completedLifts: week.completedLifts
            ),
            // Stamped from the week the totals were actually built from, which is
            // the coach plan's Monday-to-Sunday week when a plan is loaded. The
            // widget cannot derive this itself, and guessing it from the locale
            // calendar made Sunday and the next Monday look like one week.
            weekStartKey: TodayWidgetSnapshot.dayKey(for: week.startDate, calendar: calendar),
            weekEndKey: TodayWidgetSnapshot.dayKey(for: week.endDate, calendar: calendar)
        )
    }

    private static func displayState(
        weightLogged: Bool,
        day: WeeklyDaySnapshot?
    ) -> (phase: TodayWidgetPhase, headline: String, detail: String, symbol: String, deepLink: URL) {
        if !weightLogged {
            return (
                .weight,
                "Log morning weight",
                "Then see what is on for today",
                "scalemass.fill",
                URL(string: "today://weight")!
            )
        }

        guard let day else {
            return (
                .unavailable,
                "Open Today",
                "Refresh your plan",
                "arrow.clockwise",
                URL(string: "today://")!
            )
        }

        let needsRun = day.plannedRunMiles != nil && !day.runCompleted
        let needsLift = day.plannedLift != nil && !day.liftCompleted
        let hasPlannedWork = day.plannedRunMiles != nil || day.plannedLift != nil

        if !hasPlannedWork {
            return (
                .recovery,
                day.plannedOther ?? "Nothing planned",
                "Recovery counts too",
                "moon.stars.fill",
                URL(string: "today://")!
            )
        }

        if !needsRun && !needsLift {
            let stats = completedStats(day)
            return (
                .done,
                "Done for the day",
                stats.isEmpty ? "Everything is checked off" : stats,
                "checkmark.circle.fill",
                URL(string: "today://history")!
            )
        }

        var work: [String] = []
        if needsRun, let miles = day.plannedRunMiles {
            work.append("\(formatMiles(miles)) mi run")
        }
        if needsLift, let lift = day.plannedLift {
            work.append("\(lift.title) lift")
        }
        let completed = completedStats(day)
        return (
            needsRun && needsLift ? .plan : .remaining,
            work.joined(separator: " + "),
            completed.isEmpty ? "Tap to open Today" : "Done: \(completed)",
            needsLift && !needsRun ? "dumbbell.fill" : "figure.run",
            needsLift && !needsRun ? URL(string: "today://workout")! : URL(string: "today://")!
        )
    }

    private static func completedStats(_ day: WeeklyDaySnapshot) -> String {
        var values: [String] = []
        if let run = day.run, day.runCompleted {
            let minutes = Int((run.duration / 60).rounded())
            values.append("\(formatMiles(run.miles)) mi in \(minutes)m")
        }
        if let lift = day.lift {
            let sets = lift.completedSetCount
            values.append("\(sets) \(sets == 1 ? "set" : "sets")")
        }
        return values.joined(separator: " · ")
    }

    private static func formatMiles(_ miles: Double) -> String {
        miles.formatted(.number.precision(.fractionLength(miles.rounded() == miles ? 0 : 1)))
    }
}
