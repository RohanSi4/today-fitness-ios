import SwiftUI
import UIKit

struct WeightLogView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: TodayStore

    @State private var value: Double
    @State private var date = Date()
    @State private var showBackdate = false
    @State private var isSaving = false
    @State private var errorMessage: String?
    /// Set only when the weight is safely stored but Apple Health refused it.
    @State private var healthWriteFailure: String?
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
            Group {
                if let healthWriteFailure {
                    savedWithoutHealth(reason: healthWriteFailure)
                } else {
                    editor
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Morning weight")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(healthWriteFailure == nil ? "Close" : "Done") { dismiss() }
                }
                // The decimal pad has no return key, so without this the only
                // way out of the field was to tap something else on the sheet.
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { isWeightFieldFocused = false }
                        .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    /// Shown after the weight is stored but Apple Health rejected the copy.
    private func savedWithoutHealth(reason: String) -> some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 44))
                .foregroundStyle(.green)
                .accessibilityHidden(true)
            Text("\(value.formatted(.number.precision(.fractionLength(1)))) lb saved")
                .font(.title3.weight(.bold))
            Text("It is stored in Today and will reach the coach sync. Apple Health did not accept a copy, so this reading will not appear there.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Text(reason)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .buttonStyle(.bordered)
            .padding(.top, 4)
            Spacer()
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity)
    }

    private var editor: some View {
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

            // Saving replaces whatever is already on that day. Silently
            // overwriting a reading you had forgotten about is exactly how a
            // backdated correction turns into lost history.
            if let existing = existingEntry {
                Label(
                    "Replaces \(existing.pounds.formatted(.number.precision(.fractionLength(1)))) lb "
                        + "already logged for \(existing.date.formatted(.dateTime.weekday(.abbreviated).month().day()))",
                    systemImage: "arrow.triangle.2.circlepath"
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            }

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
    }

    /// The reading this save would replace, if any.
    private var existingEntry: WeightEntry? {
        store.weights.first { Calendar.current.isDate($0.date, inSameDayAs: date) }
    }

    private func adjustmentButton(_ label: String, amount: Double) -> some View {
        Button(label) {
            // A half-typed number in the field has not reached `value` yet, so
            // nudging would silently discard it.
            isWeightFieldFocused = false
            withAnimation(.snappy) {
                value = ((value + amount) * 10).rounded() / 10
            }
        }
        .buttonStyle(.bordered)
        .font(.subheadline.monospacedDigit().weight(.semibold))
        .accessibilityLabel("Adjust weight by \(label) pounds")
    }

    private func save() async {
        // A formatted TextField only writes its parsed value back to the binding
        // when editing ends. Tapping Save straight from the keyboard could
        // therefore store yesterday's number instead of the one on screen.
        isWeightFieldFocused = false
        dismissKeyboard()
        await Task.yield()

        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        let outcome = await WeightSaveService.save(
            pounds: value,
            on: date,
            store: store,
            healthStore: healthStore,
            reminders: reminders
        )

        switch outcome {
        case .rejected(let reason):
            errorMessage = reason
        case .saved(.written), .saved(.unavailable):
            // Opportunistic and unrelated to storing the weight, so it happens
            // out here rather than anywhere it could affect the save.
            try? await HealthKitManager.shared.requestAuthorization()
            dismiss()
        case .saved(.failed(let reason)):
            // The reading is already safe on disk. Staying open costs one tap in
            // a state he can actually fix, and it is the only way he would ever
            // learn that Apple Health has stopped receiving his weights.
            healthWriteFailure = reason
        }
    }
}
