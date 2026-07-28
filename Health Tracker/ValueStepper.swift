import SwiftUI

/// Minus / typeable field / plus, for the weight on a set.
///
/// Extracted from `WorkoutLogView` so the two steppers, the only controls in the
/// app that get touched dozens of times per session, live somewhere you can find
/// them.
/// Turning the weight field's `Double` into text and back.
///
/// Split out of the view because the interesting part is the typing, which a
/// screenshot cannot check and a SwiftUI body cannot be unit-tested through.
enum StepperText {
    /// An unset weight renders as an EMPTY field so the `TextField`'s own "0"
    /// placeholder shows in placeholder grey. Binding straight to the `Double`
    /// printed a literal `0`, so a first-exposure set read "0 lb" as though he
    /// had loaded an empty machine.
    static func display(_ value: Double, fractionDigits: ClosedRange<Int>) -> String {
        value == 0 ? "" : value.formatted(.number.precision(.fractionLength(fractionDigits)))
    }

    /// `nil` means "not a number yet, leave the value alone". Clearing the field
    /// is a real zero, not a refusal.
    static func parse(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return 0 }
        return Double(trimmed.replacingOccurrences(of: ",", with: "."))
    }
}

struct ValueStepper: View {
    @Binding var value: Double
    let step: Double
    let minimum: Double
    let label: String
    let fractionDigits: ClosedRange<Int>
    let accessibilityName: String

    /// A local buffer, not a computed `Binding<String>`. Computing the text from
    /// `value` on every keystroke round-trips "12." through `Double` back to
    /// "12" and eats the decimal point as he types it — on the one control in
    /// the app that gets touched dozens of times a session.
    @State private var text = ""

    var body: some View {
        HStack(spacing: 2) {
            StepperButton(
                symbol: "minus",
                accessibilityLabel: "Decrease \(accessibilityName) by \(step.formatted())"
            ) {
                value = max(minimum, value - step)
            }

            VStack(spacing: 0) {
                TextField("0", text: $text)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.center)
                    .font(.headline.monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(minWidth: 42)
                    .accessibilityLabel(accessibilityName)
                    .onAppear { text = StepperText.display(value, fractionDigits: fractionDigits) }
                    .onChange(of: text) { _, typed in
                        guard let parsed = StepperText.parse(typed) else { return }
                        let clamped = max(minimum, parsed)
                        if clamped != value { value = clamped }
                    }
                    .onChange(of: value) { _, updated in
                        // Only when the change came from OUTSIDE the field — the
                        // +/- buttons, or a brand switch rebuilding the row.
                        // Rewriting on every keystroke is what deletes "12.".
                        if StepperText.parse(text) != updated {
                            text = StepperText.display(updated, fractionDigits: fractionDigits)
                        }
                    }
                Text(label)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }

            StepperButton(
                symbol: "plus",
                accessibilityLabel: "Increase \(accessibilityName) by \(step.formatted())"
            ) {
                value += step
            }
        }
        .frame(maxWidth: .infinity)
    }
}

/// The same control for whole reps.
struct IntValueStepper: View {
    @Binding var value: Int
    let label: String
    let accessibilityName: String

    var body: some View {
        HStack(spacing: 2) {
            StepperButton(symbol: "minus", accessibilityLabel: "Decrease \(accessibilityName)") {
                value = max(0, value - 1)
            }

            VStack(spacing: 0) {
                TextField("0", value: $value, format: .number)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.center)
                    .font(.headline.monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(minWidth: 28)
                    .accessibilityLabel(accessibilityName)
                Text(label)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }

            StepperButton(symbol: "plus", accessibilityLabel: "Increase \(accessibilityName)") {
                value += 1
            }
        }
        .frame(width: 120)
    }
}

/// A 44 pt tap target no matter how small the glyph is, which is what these
/// buttons were already open-coding four times.
private struct StepperButton: View {
    let symbol: String
    let accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}
