import SwiftUI

struct StretchRoutineCompletion: View {
    let phase: StretchPhase
    let totalSteps: Int
    let onDone: () -> Void
    let onRestart: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("Routine complete", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        } description: {
            Text("\(phase.title) done. You worked through all \(totalSteps) steps.")
        } actions: {
            Button("Done", action: onDone)
                .buttonStyle(.borderedProminent)
                .tint(TodayPalette.accent)

            Button("Run it again", action: onRestart)
                .buttonStyle(.bordered)
        }
        .accessibilityIdentifier("stretch-routine-complete")
    }
}

struct StretchHoldTimerDial: View {
    let remainingSeconds: Int
    let totalSeconds: Int
    let isTransition: Bool
    let reduceMotion: Bool

    private var fraction: Double {
        guard totalSeconds > 0 else { return 0 }
        return min(1, max(0, Double(remainingSeconds) / Double(totalSeconds)))
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color(.tertiarySystemFill), lineWidth: 10)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(
                    isTransition ? TodayPalette.warm : TodayPalette.accent,
                    style: StrokeStyle(lineWidth: 10, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(reduceMotion ? nil : .linear(duration: 0.2), value: fraction)

            VStack(spacing: 2) {
                Text("\(remainingSeconds)")
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text(isTransition ? "switch" : "seconds")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 150, height: 150)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            isTransition
                ? "\(remainingSeconds) seconds to switch position"
                : "\(remainingSeconds) seconds remaining"
        )
    }
}
