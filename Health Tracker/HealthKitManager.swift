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

protocol HealthDataProviding {
    var isHealthDataAvailable: Bool { get }
    func requestAuthorization() async throws
    func fetchSleepSessions(start: Date, end: Date) async throws -> [SleepSession]
    func fetchDailyCumulativeStatistics(
        for kind: MovementKind,
        start: Date,
        end: Date
    ) async throws -> [Date: Double]
}

final class HealthKitManager: HealthDataProviding {
    static let shared = HealthKitManager()

    var isHealthDataAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    private let store: HKHealthStore
    private let sessionAssembler = SleepSessionAssembler()

    private init(store: HKHealthStore = HKHealthStore()) {
        self.store = store
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

        let readTypes: Set<HKObjectType> = [sleepType, stepsType, distanceType, energyType]

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            store.requestAuthorization(toShare: [], read: readTypes) { success, error in
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

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsCollectionQuery(
                quantityType: quantityType,
                quantitySamplePredicate: predicate,
                options: [.cumulativeSum],
                anchorDate: anchorDate,
                intervalComponents: interval
            )

            query.initialResultsHandler = { _, results, error in
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
            store.execute(query)
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
