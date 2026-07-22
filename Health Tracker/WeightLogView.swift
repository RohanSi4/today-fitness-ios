import SwiftUI

struct WeightLogView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: TodayStore

    @State private var value: Double
    @State private var date = Date()
    @State private var showBackdate = false
    @State private var isSaving = false
    @State private var errorMessage: String?
    @FocusState private var isWeightFieldFocused: Bool

    private let healthStore: BodyWeightHealthStoring
    private let reminders: WeightReminderScheduling

    init(
        store: TodayStore,
        healthStore: BodyWeightHealthStoring = HealthKitManager.shared,
        reminders: WeightReminderScheduling = NotificationManager.shared
    ) {
        self.store = store
        self.healthStore = healthStore
        self.reminders = reminders
        _value = State(initialValue: store.latestWeight?.pounds ?? 184.4)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                Spacer(minLength: 12)

                VStack(spacing: 4) {
                    TextField(
                        "Weight",
                        value: $value,
                        format: .number.precision(.fractionLength(1))
                    )
                        .font(.system(size: 64, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.center)
                        .focused($isWeightFieldFocused)
                        .frame(maxWidth: 240)
                        .accessibilityLabel("Weight in pounds")
                    Text("pounds")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 10) {
                    adjustmentButton("−0.5", amount: -0.5)
                    adjustmentButton("−0.1", amount: -0.1)
                    adjustmentButton("+0.1", amount: 0.1)
                    adjustmentButton("+0.5", amount: 0.5)
                }

                DisclosureGroup("Log a different day", isExpanded: $showBackdate) {
                    DatePicker("Date", selection: $date, in: ...Date(), displayedComponents: [.date])
                        .datePickerStyle(.compact)
                        .padding(.top, 8)
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }

                Button {
                    Task { await save() }
                } label: {
                    if isSaving {
                        ProgressView().frame(maxWidth: .infinity)
                    } else {
                        Text("Save weight").frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(isSaving || value <= 0)

                Text("The exact number stays private unless you choose to share a small progress summary in Coach sync.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Morning weight")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func adjustmentButton(_ label: String, amount: Double) -> some View {
        Button(label) {
            withAnimation(.snappy) {
                value = ((value + amount) * 10).rounded() / 10
            }
        }
        .buttonStyle(.bordered)
        .font(.subheadline.monospacedDigit().weight(.semibold))
        .accessibilityLabel("Adjust weight by \(label) pounds")
    }

    private func save() async {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        do {
#if targetEnvironment(simulator)
            store.recordWeight(value, on: date)
#else
            try await healthStore.requestBodyWeightAuthorization()
            let sampleID = try await healthStore.saveBodyWeight(pounds: value, date: date)
            store.recordWeight(value, on: date, healthKitID: sampleID)
            try? await HealthKitManager.shared.requestAuthorization()
            let start = Calendar.current.date(byAdding: .year, value: -2, to: Date()) ?? date
            if let history = try? await healthStore.fetchBodyWeights(start: start, end: Date().addingTimeInterval(60)) {
                store.mergeHealthWeights(history)
            }
#endif
            reminders.cancelWeightReminders(for: date)
            if await reminders.requestAuthorization() {
                await reminders.scheduleWeightReminders(from: Date(), days: 30)
                reminders.cancelWeightReminders(for: date)
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
