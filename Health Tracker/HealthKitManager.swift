import Foundation
import HealthKit

enum HealthKitError: Error, LocalizedError {
    case healthDataNotAvailable
    case authorizationDenied
    case unsupportedType
    case noSleepData

    var errorDescription: String? {
        switch self {
        case .healthDataNotAvailable:
            "Health data is not available here. Run on an iPhone to use your data."
        case .authorizationDenied:
            "Health access was not granted. You can change access in Settings."
        case .unsupportedType:
            "A required Health data type is unavailable."
        case .noSleepData:
            "No recent sleep session was found."
        }
    }
}

protocol HealthDataProviding: Sendable {
    var isHealthDataAvailable: Bool { get }
    func requestAuthorization() async throws
    func fetchSleepSessions(start: Date, end: Date) async throws -> [SleepSession]
    func fetchDailyCumulativeStatistics(
        for kind: MovementKind,
        start: Date,
        end: Date
    ) async throws -> [Date: Double]
}

protocol BodyWeightHealthStoring: Sendable {
    var isHealthDataAvailable: Bool { get }
    func requestBodyWeightAuthorization() async throws
    func saveBodyWeight(pounds: Double, date: Date) async throws -> UUID
    func fetchBodyWeights(start: Date, end: Date) async throws -> [WeightEntry]
}

protocol BodyWeightHealthDeleting: Sendable {
    func deleteBodyWeight(id: UUID) async throws
}

/// `@unchecked` rather than plain `Sendable`, because the safety here is real but
/// not expressible to the compiler:
///
/// - every one of the four mutable properties below is read and written only
///   inside `withMonitorLock`, which is what makes the unchecked claim true
///   rather than a silencer;
/// - `store` is an `HKHealthStore`, which Apple documents as safe to use from
///   any thread but has not annotated `Sendable`;
/// - `sessionAssembler` is a struct holding one `TimeInterval`, so it is
///   implicitly `Sendable` already.
///
/// If a mutable property is ever added here, it belongs behind `monitorLock`
/// too, or this annotation becomes a lie.
final class HealthKitManager: HealthDataProviding, BodyWeightHealthStoring, BodyWeightHealthDeleting, RunningWorkoutProviding, @unchecked Sendable {
    static let shared = HealthKitManager()

    var isHealthDataAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    private let store: HKHealthStore
    private let sessionAssembler = SleepSessionAssembler()

    // Touched from observer callbacks on HealthKit's own queues as well as from the
    // main actor, so all of it sits behind one lock.
    private let monitorLock = NSLock()
    private var sleepObserverQuery: HKObserverQuery?
    private var workoutObserverQuery: HKObserverQuery?
    private var sleepBackgroundDeliveryEnabled = false
    private var workoutBackgroundDeliveryEnabled = false

    private init(store: HKHealthStore = HKHealthStore()) {
        self.store = store
    }

    private func withMonitorLock<T>(_ body: () -> T) -> T {
        monitorLock.lock()
        defer { monitorLock.unlock() }
        return body()
    }

    /// Background delivery cannot be turned on until Health authorization has been
    /// answered, and both observers are started from `App.init`, before any prompt.
    /// The old code fired and forgot, so on a fresh install the failure was
    /// permanent: no watch run or sleep sample ever woke the app again. Record
    /// success and retry on every later call instead.
    private func enableBackgroundDelivery(for type: HKObjectType, isSleep: Bool) {
        let alreadyEnabled = withMonitorLock {
            isSleep ? sleepBackgroundDeliveryEnabled : workoutBackgroundDeliveryEnabled
        }
        guard !alreadyEnabled else { return }
        store.enableBackgroundDelivery(for: type, frequency: .immediate) { [weak self] success, _ in
            guard success, let self else { return }
            self.withMonitorLock {
                if isSleep {
                    self.sleepBackgroundDeliveryEnabled = true
                } else {
                    self.workoutBackgroundDeliveryEnabled = true
                }
            }
        }
    }

    func requestAuthorization() async throws {
        guard isHealthDataAvailable else {
            throw HealthKitError.healthDataNotAvailable
        }

        guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis),
              let stepsType = HKObjectType.quantityType(forIdentifier: .stepCount),
              let distanceType = HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning),
              let energyType = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned) else {
            throw HealthKitError.unsupportedType
        }

        let readTypes: Set<HKObjectType> = [
            sleepType,
            stepsType,
            distanceType,
            energyType,
            HKWorkoutType.workoutType(),
        ]

        try await requestAuthorization(toShare: [], read: readTypes)
        // Now that the prompt has been answered, a sleep observer registered at
        // launch can finally get background delivery turned on.
        let hasSleepObserver = withMonitorLock { sleepObserverQuery != nil }
        if hasSleepObserver {
            enableBackgroundDelivery(for: sleepType, isSleep: true)
        }
    }

    func requestBodyWeightAuthorization() async throws {
        guard isHealthDataAvailable else {
            throw HealthKitError.healthDataNotAvailable
        }
        guard let bodyMass = HKObjectType.quantityType(forIdentifier: .bodyMass) else {
            throw HealthKitError.unsupportedType
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            store.requestAuthorization(toShare: [bodyMass], read: [bodyMass]) { success, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if success {
                    continuation.resume(returning: ())
                } else {
                    continuation.resume(throwing: HealthKitError.authorizationDenied)
                }
            }
        }
    }

    func requestWorkoutAuthorization() async throws {
        guard isHealthDataAvailable else {
            throw HealthKitError.healthDataNotAvailable
        }
        try await requestAuthorization(toShare: [], read: [HKWorkoutType.workoutType()])
        // Best effort. A background-delivery failure is not an authorization
        // failure, and throwing it made callers treat a granted prompt as denied.
        enableBackgroundDelivery(for: HKWorkoutType.workoutType(), isSleep: false)
    }

    func saveBodyWeight(pounds: Double, date: Date) async throws -> UUID {
        guard let bodyMass = HKObjectType.quantityType(forIdentifier: .bodyMass) else {
            throw HealthKitError.unsupportedType
        }
        let quantity = HKQuantity(unit: .pound(), doubleValue: pounds)
        let sample = HKQuantitySample(type: bodyMass, quantity: quantity, start: date, end: date)

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            store.save(sample) { success, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if success {
                    continuation.resume(returning: ())
                } else {
                    continuation.resume(throwing: HealthKitError.authorizationDenied)
                }
            }
        }
        return sample.uuid
    }

    func deleteBodyWeight(id: UUID) async throws {
        guard let bodyMass = HKObjectType.quantityType(forIdentifier: .bodyMass) else {
            throw HealthKitError.unsupportedType
        }
        let predicate = HKQuery.predicateForObject(with: id)
        let samples: [HKQuantitySample] = try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: bodyMass,
                predicate: predicate,
                limit: 1,
                sortDescriptors: nil
            ) { _, results, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: (results as? [HKQuantitySample]) ?? [])
                }
            }
            store.execute(query)
        }
        guard let sample = samples.first else { return }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            store.delete(sample) { success, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if success {
                    continuation.resume(returning: ())
                } else {
                    continuation.resume(throwing: HealthKitError.authorizationDenied)
                }
            }
        }
    }

    func fetchBodyWeights(start: Date, end: Date) async throws -> [WeightEntry] {
        guard let bodyMass = HKObjectType.quantityType(forIdentifier: .bodyMass) else {
            throw HealthKitError.unsupportedType
        }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)

        let samples: [HKQuantitySample] = try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: bodyMass,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sort]
            ) { _, results, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: (results as? [HKQuantitySample]) ?? [])
                }
            }
            store.execute(query)
        }

        return samples.map {
            WeightEntry(
                date: $0.startDate,
                pounds: $0.quantity.doubleValue(for: .pound()),
                healthKitID: $0.uuid
            )
        }
    }

    func fetchRunningWorkouts(start: Date, end: Date) async throws -> [RunningWorkoutSummary] {
        let samplePredicate = HKQuery.predicateForSamples(
            withStart: start,
            end: end,
            options: [.strictStartDate]
        )
        let runningPredicate = HKQuery.predicateForWorkouts(with: .running)
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            samplePredicate,
            runningPredicate,
        ])
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)

        let workouts: [HKWorkout] = try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: HKWorkoutType.workoutType(),
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sort]
            ) { _, results, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: (results as? [HKWorkout]) ?? [])
                }
            }
            store.execute(query)
        }

        return workouts.compactMap { workout in
            let miles = workout.totalDistance?.doubleValue(for: .mile()) ?? 0
            guard workout.duration > 0, miles > 0 else { return nil }
            return RunningWorkoutSummary(
                id: workout.uuid,
                startedAt: workout.startDate,
                endedAt: workout.endDate,
                miles: miles,
                duration: workout.duration
            )
        }
    }

    func startSleepWakeMonitoring(onWake: @escaping @Sendable (Date) -> Void) {
        guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { return }

        let query = HKObserverQuery(sampleType: sleepType, predicate: nil) { [weak self] _, completion, error in
            guard error == nil, let self else {
                completion()
                return
            }

            // HealthKit declares its completion handler as a plain `() -> Void`,
            // so carrying it into this `Task` is a `sending` violation even
            // though HealthKit's own contract is "call me exactly once, from
            // wherever you finish". The unsafe shadow states that, and the
            // `defer` is what guarantees the once.
            nonisolated(unsafe) let completion = completion
            Task {
                defer { completion() }
                let now = Date()
                let start = Calendar.current.date(byAdding: .hour, value: -24, to: now) ?? now
                guard let sessions = try? await self.fetchSleepSessions(start: start, end: now),
                      let latest = sessions
                        .filter({ $0.asleepDuration >= 3 * 3600 })
                        .max(by: { $0.end < $1.end }),
                      now.timeIntervalSince(latest.end) <= 90 * 60 else {
                    return
                }
                onWake(latest.end)
            }
        }
        // Test and set under one acquisition. Checking the slot in one lock and
        // filling it in another let two concurrent callers both pass the check
        // and both `execute` a query: one observer leaks, and every wake fires
        // its callback twice. Building the query first is free, since an
        // `HKObserverQuery` does nothing until it is executed.
        guard claimObserverSlot(isSleep: true, query: query) else {
            enableBackgroundDelivery(for: sleepType, isSleep: true)
            return
        }
        store.execute(query)
        enableBackgroundDelivery(for: sleepType, isSleep: true)
    }

    /// Claims the single observer slot for this type, returning false if another
    /// caller already holds it.
    private func claimObserverSlot(isSleep: Bool, query: HKObserverQuery) -> Bool {
        withMonitorLock {
            if isSleep {
                guard sleepObserverQuery == nil else { return false }
                sleepObserverQuery = query
            } else {
                guard workoutObserverQuery == nil else { return false }
                workoutObserverQuery = query
            }
            return true
        }
    }

    func startWorkoutMonitoring(onChange: @escaping @Sendable () -> Void) {
        let workoutType = HKWorkoutType.workoutType()
        let query = HKObserverQuery(sampleType: workoutType, predicate: nil) { _, completion, error in
            defer { completion() }
            guard error == nil else { return }
            onChange()
        }
        guard claimObserverSlot(isSleep: false, query: query) else {
            enableBackgroundDelivery(for: workoutType, isSleep: false)
            return
        }
        store.execute(query)
        enableBackgroundDelivery(for: workoutType, isSleep: false)
    }

    func fetchSleepSessions(start: Date, end: Date) async throws -> [SleepSession] {
        guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else {
            throw HealthKitError.unsupportedType
        }

        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [])
        let sortDescriptors = [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]

        let samples: [HKCategorySample] = try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: sleepType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: sortDescriptors
            ) { _, results, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: (results as? [HKCategorySample]) ?? [])
            }
            store.execute(query)
        }

        let intervals = samples.compactMap(SleepInterval.init(sample:))
        return sessionAssembler.sessions(from: intervals)
    }

    func fetchDailyCumulativeStatistics(
        for kind: MovementKind,
        start: Date,
        end: Date
    ) async throws -> [Date: Double] {
        let identifier = quantityIdentifier(for: kind)
        guard let quantityType = HKObjectType.quantityType(forIdentifier: identifier) else {
            throw HealthKitError.unsupportedType
        }

        let calendar = Calendar.current
        let anchorDate = calendar.startOfDay(for: start)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let interval = DateComponents(day: 1)
        let unit = unit(for: kind)

        let healthStore = store
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsCollectionQuery(
                quantityType: quantityType,
                quantitySamplePredicate: predicate,
                options: [.cumulativeSum],
                anchorDate: anchorDate,
                intervalComponents: interval
            )

            query.initialResultsHandler = { query, results, error in
                // A collection query keeps running until it is stopped, unlike a
                // sample query. Three of these leaked on every recap load.
                healthStore.stop(query)

                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                var data: [Date: Double] = [:]
                results?.enumerateStatistics(from: start, to: end) { statistics, _ in
                    let dayStart = calendar.startOfDay(for: statistics.startDate)
                    data[dayStart] = statistics.sumQuantity()?.doubleValue(for: unit) ?? 0
                }
                continuation.resume(returning: data)
            }
            healthStore.execute(query)
        }
    }

    private func quantityIdentifier(for kind: MovementKind) -> HKQuantityTypeIdentifier {
        switch kind {
        case .steps: .stepCount
        case .distance: .distanceWalkingRunning
        case .activeEnergy: .activeEnergyBurned
        }
    }

    private func unit(for kind: MovementKind) -> HKUnit {
        switch kind {
        case .steps: .count()
        case .distance: .meter()
        case .activeEnergy: .kilocalorie()
        }
    }

    private func requestAuthorization(
        toShare shareTypes: Set<HKSampleType>,
        read readTypes: Set<HKObjectType>
    ) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            store.requestAuthorization(toShare: shareTypes, read: readTypes) { success, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if success {
                    continuation.resume(returning: ())
                } else {
                    continuation.resume(throwing: HealthKitError.authorizationDenied)
                }
            }
        }
    }
}

struct SleepInterval: Equatable {
    enum Kind {
        case inBed
        case asleep
    }

    let start: Date
    let end: Date
    let kind: Kind

    var duration: TimeInterval { max(0, end.timeIntervalSince(start)) }
}

private extension SleepInterval {
    init?(sample: HKCategorySample) {
        guard sample.endDate > sample.startDate,
              let value = HKCategoryValueSleepAnalysis(rawValue: sample.value) else {
            return nil
        }

        let kind: Kind
        switch value {
        case .inBed:
            kind = .inBed
        case .asleep, .asleepUnspecified, .asleepCore, .asleepDeep, .asleepREM:
            kind = .asleep
        default:
            return nil
        }

        self.init(start: sample.startDate, end: sample.endDate, kind: kind)
    }
}

struct SleepSessionAssembler {
    let sessionGap: TimeInterval

    init(sessionGap: TimeInterval = 90 * 60) {
        self.sessionGap = sessionGap
    }

    func sessions(from intervals: [SleepInterval]) -> [SleepSession] {
        let sorted = intervals
            .filter { $0.end > $0.start }
            .sorted { lhs, rhs in
                lhs.start == rhs.start ? lhs.end < rhs.end : lhs.start < rhs.start
            }

        var groups: [[SleepInterval]] = []
        for interval in sorted {
            guard var group = groups.popLast() else {
                groups.append([interval])
                continue
            }

            let groupEnd = group.map(\.end).max() ?? interval.start
            if interval.start.timeIntervalSince(groupEnd) > sessionGap {
                groups.append(group)
                groups.append([interval])
            } else {
                group.append(interval)
                groups.append(group)
            }
        }

        return groups.compactMap(makeSession)
    }

    private func makeSession(from intervals: [SleepInterval]) -> SleepSession? {
        guard let start = intervals.map(\.start).min(),
              let end = intervals.map(\.end).max() else {
            return nil
        }

        let asleep = mergedDuration(of: intervals.filter { $0.kind == .asleep })
        let recordedInBed = mergedDuration(of: intervals.filter { $0.kind == .inBed })
        let inBed = max(asleep, recordedInBed > 0 ? recordedInBed : end.timeIntervalSince(start))

        return SleepSession(
            start: start,
            end: end,
            asleepDuration: asleep,
            inBedDuration: inBed
        )
    }

    private func mergedDuration(of intervals: [SleepInterval]) -> TimeInterval {
        let sorted = intervals.sorted { $0.start < $1.start }
        guard var current = sorted.first else { return 0 }
        var total: TimeInterval = 0

        for interval in sorted.dropFirst() {
            if interval.start <= current.end {
                current = SleepInterval(
                    start: current.start,
                    end: max(current.end, interval.end),
                    kind: current.kind
                )
            } else {
                total += current.duration
                current = interval
            }
        }

        return total + current.duration
    }
}
