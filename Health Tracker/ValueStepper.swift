import SwiftUI

/// Minus / typeable field / plus, for the weight on a set.
///
/// Extracted from `WorkoutLogView` so the two steppers, the only controls in the
/// app that get touched dozens of times per session, live somewhere you can find
/// them.
struct ValueStepper: View {
    @Binding var value: Double
    let step: Double
    let minimum: Double
    let label: String
    let fractionDigits: ClosedRange<Int>
    let accessibilityName: String

    var body: some View {
        HStack(spacing: 2) {
            StepperButton(
                symbol: "minus",
                accessibilityLabel: "Decrease \(accessibilityName) by \(step.formatted())"
            ) {
                value = max(minimum, value - step)
            }

            VStack(spacing: 0) {
                TextField("0", value: $value, format: .number.precision(.fractionLength(fractionDigits)))
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.center)
                    .font(.headline.monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(minWidth: 42)
                    .accessibilityLabel(accessibilityName)
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
