import Foundation

/// What happened to a morning weight the user tried to save.
enum WeightSaveOutcome: Equatable {
    /// Nothing was written and nothing existing was touched. The sheet stays
    /// open so he can fix the number.
    case rejected(reason: String)
    /// The reading is on disk. Apple Health may or may not have a copy.
    case saved(health: HealthWriteResult)
}

enum HealthWriteResult: Equatable {
    /// Written to Apple Health and the sample id is attached to the entry.
    case written
    /// This device has no Health data at all, which is not something he can act
    /// on, so it is not worth interrupting him about.
    case unavailable
    /// Health refused the write, almost always because access was denied or
    /// later revoked in Settings. Actionable, so it is surfaced.
    case failed(String)
}

/// Saving a morning weight, in an order that cannot lose it.
///
/// The previous shape was:
///
/// ```swift
/// try await healthStore.requestBodyWeightAuthorization()
/// let sampleID = try await healthStore.saveBodyWeight(pounds: value, date: date)
/// store.recordWeight(value, on: date, healthKitID: sampleID)
/// ```
///
/// Either `try` throwing jumped straight to `catch`, so `recordWeight` never
/// ran: he typed his weight, saw an error, and the number was gone. Nothing
/// reached local storage, nothing reached the coach sync, and because the
/// reminder cancellation also sat below the throwing calls the phone kept
/// nudging him to log a weight he had already entered. Denying Health access
/// once, or revoking it months later in Settings, was enough to trigger it.
///
/// It never showed up in a test run because the whole block sat behind
/// `#if targetEnvironment(simulator)`, and the simulator branch called
/// `recordWeight` unconditionally. The dangerous path was the one path that
/// never compiled under test. That conditional is gone: there is now a single
/// code path whose behaviour depends on the injected `healthStore`, so every
/// branch below is reachable from a test with a stub.
@MainActor
enum WeightSaveService {
    static func save(
        pounds: Double,
        on date: Date,
        store: TodayStore,
        healthStore: BodyWeightHealthStoring,
        reminders: WeightReminderScheduling,
        calendar: Calendar = .current
    ) async -> WeightSaveOutcome {
        let replacedEntry = store.weights.first {
            calendar.isDate($0.date, inSameDayAs: date)
        }
        // The reading lands on disk before anything that can throw. Everything
        // after this point is best effort and cannot cost him the number.
        store.recordWeight(pounds, on: date)

        // `recordWeight` drops implausible values silently, so confirm it landed
        // rather than reporting a success that did not happen. Asking the store
        // what it did, instead of duplicating its validation rules here, means
        // this cannot drift if those rules change.
        guard store.weights.contains(where: {
            calendar.isDate($0.date, inSameDayAs: date) && $0.pounds == pounds
        }) else {
            return .rejected(reason: "That does not look like a body weight. Check the number and try again.")
        }

        let health = await writeToHealth(
            pounds: pounds,
            on: date,
            store: store,
            healthStore: healthStore,
            replacedEntry: replacedEntry
        )

        // Always runs now. He logged his weight, so the nagging stops whether or
        // not Apple Health accepted a copy.
        await refreshReminders(for: date, reminders: reminders)

        return .saved(health: health)
    }

    private static func writeToHealth(
        pounds: Double,
        on date: Date,
        store: TodayStore,
        healthStore: BodyWeightHealthStoring,
        replacedEntry: WeightEntry?
    ) async -> HealthWriteResult {
        guard healthStore.isHealthDataAvailable else { return .unavailable }

        do {
            try await healthStore.requestBodyWeightAuthorization()
            let sampleID = try await healthStore.saveBodyWeight(pounds: pounds, date: date)

            // Re-recording the same day attaches the sample id. `recordWeight`
            // is keyed by day and clears that day before appending, so this
            // replaces the local-only entry rather than adding a second row.
            store.recordWeight(
                pounds,
                on: date,
                healthKitID: sampleID,
                healthKitOwnedByToday: true
            )

            if replacedEntry?.healthKitOwnedByToday == true,
               let previousID = replacedEntry?.healthKitID,
               previousID != sampleID,
               let deletingStore = healthStore as? BodyWeightHealthDeleting {
                try? await deletingStore.deleteBodyWeight(id: previousID)
            }

            let start = Calendar.current.date(byAdding: .year, value: -2, to: Date()) ?? date
            if let history = try? await healthStore.fetchBodyWeights(
                start: start,
                end: Date().addingTimeInterval(60)
            ) {
                store.mergeHealthWeights(history)
            }
            return .written
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    private static func refreshReminders(
        for date: Date,
        reminders: WeightReminderScheduling
    ) async {
        reminders.cancelWeightReminders(for: date)
        guard await reminders.requestAuthorization() else { return }
        // Read once here rather than inside the scheduler so the scheduler stays
        // free of any calendar dependency and keeps working with none granted.
        let firstCommitments = await MainActor.run {
            CalendarService.shared.firstCommitmentsByDayKey()
        }
        await reminders.scheduleWeightReminders(
            from: Date(),
            days: 30,
            firstCommitments: firstCommitments
        )
        // Scheduling the next stretch re-adds today, so clear it again.
        reminders.cancelWeightReminders(for: date)
    }
}
