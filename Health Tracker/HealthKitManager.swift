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
            return "Health data is not available on this device."
        case .authorizationDenied:
            return "HealthKit authorization was not granted."
        case .unsupportedType:
            return "A required HealthKit data type is unavailable."
        case .noSleepData:
            return "No recent sleep data was found."
        }
    }
}

final class HealthKitManager {
    static let shared = HealthKitManager()

    private let store = HKHealthStore()
    private let sessionGap: TimeInterval = 90 * 60

    private init() {}

    func requestAuthorization() async throws {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw HealthKitError.healthDataNotAvailable
        }

        guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis),
              let stepsType = HKObjectType.quantityType(forIdentifier: .stepCount),
              let distanceType = HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning),
              let energyType = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned) else {
            throw HealthKitError.unsupportedType
        }

        let readTypes: Set<HKObjectType> = [sleepType, stepsType, distanceType, energyType]

        try await withCheckedThrowingContinuation { continuation in
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

        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let sortDescriptors = [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]

        let samples = try await withCheckedThrowingContinuation { continuation in
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

                let categorySamples = (results as? [HKCategorySample]) ?? []
                continuation.resume(returning: categorySamples)
            }

            store.execute(query)
        }

        return buildSleepSessions(from: samples)
    }

    func fetchDailyCumulativeStatistics(
        for typeIdentifier: HKQuantityTypeIdentifier,
        start: Date,
        end: Date
    ) async throws -> [Date: Double] {
        guard let quantityType = HKObjectType.quantityType(forIdentifier: typeIdentifier) else {
            throw HealthKitError.unsupportedType
        }

        let calendar = Calendar.current
        let anchorDate = calendar.startOfDay(for: start)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let interval = DateComponents(day: 1)
        let unit = unit(for: typeIdentifier)

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
                if let results {
                    results.enumerateStatistics(from: start, to: end) { statistics, _ in
                        let sum = statistics.sumQuantity()?.doubleValue(for: unit) ?? 0
                        let dayStart = calendar.startOfDay(for: statistics.startDate)
                        data[dayStart] = sum
                    }
                }
                continuation.resume(returning: data)
            }

            store.execute(query)
        }
    }

    private func unit(for identifier: HKQuantityTypeIdentifier) -> HKUnit {
        switch identifier {
        case .stepCount:
            return HKUnit.count()
        case .distanceWalkingRunning:
            return HKUnit.meter()
        case .activeEnergyBurned:
            return HKUnit.kilocalorie()
        default:
            return HKUnit.count()
        }
    }

    private func buildSleepSessions(from samples: [HKCategorySample]) -> [SleepSession] {
        let sleepSamples = samples.compactMap { sample -> SleepSample? in
            guard let value = HKCategoryValueSleepAnalysis(rawValue: sample.value) else { return nil }

            switch value {
            case .inBed:
                return SleepSample(start: sample.startDate, end: sample.endDate, isAsleep: false)
            case .asleep, .asleepUnspecified, .asleepCore, .asleepDeep, .asleepREM:
                return SleepSample(start: sample.startDate, end: sample.endDate, isAsleep: true)
            default:
                return nil
            }
        }

        let sorted = sleepSamples.sorted { $0.start < $1.start }
        var sessions: [SleepSession] = []
        var builder: SleepSessionBuilder?

        for sample in sorted {
            if builder == nil {
                builder = SleepSessionBuilder(
                    start: sample.start,
                    end: sample.end,
                    asleepDuration: sample.isAsleep ? sample.duration : 0
                )
                continue
            }

            let gap = sample.start.timeIntervalSince(builder?.end ?? sample.start)
            if gap > sessionGap {
                if let builder {
                    sessions.append(builder.build())
                }
                builder = SleepSessionBuilder(
                    start: sample.start,
                    end: sample.end,
                    asleepDuration: sample.isAsleep ? sample.duration : 0
                )
            } else {
                builder?.end = max(builder?.end ?? sample.end, sample.end)
                if sample.isAsleep {
                    builder?.asleepDuration += sample.duration
                }
            }
        }

        if let builder {
            sessions.append(builder.build())
        }

        return sessions
    }
}

private struct SleepSample {
    let start: Date
    let end: Date
    let isAsleep: Bool

    var duration: TimeInterval {
        max(0, end.timeIntervalSince(start))
    }
}

private struct SleepSessionBuilder {
    var start: Date
    var end: Date
    var asleepDuration: TimeInterval

    func build() -> SleepSession {
        SleepSession(
            start: start,
            end: end,
            asleepDuration: asleepDuration,
            inBedDuration: max(0, end.timeIntervalSince(start))
        )
    }
}
