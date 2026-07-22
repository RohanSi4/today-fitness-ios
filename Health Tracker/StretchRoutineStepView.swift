import SwiftUI

struct StretchRoutineStepView: View {
    let session: StretchRoutineSession
    let step: StretchRoutineStep
    let timer: StretchTimerState
    let reduceMotion: Bool
    let transitionTitle: String?
    let onPrimaryAction: () -> Void
    let onResetTimer: () -> Void
    let onTimerFinished: () -> Void
    let onBack: () -> Void
    let onSkip: () -> Void
    let onChooseStep: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                StretchProgressHeader(session: session, onChooseStep: onChooseStep)
                StretchArtwork(stretch: step.stretch, height: 270)
                StretchInstructionCard(step: step)

                if timer.isTimed {
                    StretchHoldTimerCard(
                        timer: timer,
                        reduceMotion: reduceMotion,
                        transitionTitle: transitionTitle,
                        onPrimaryAction: onPrimaryAction,
                        onReset: onResetTimer,
                        onTimerFinished: onTimerFinished
                    )
                } else {
                    StretchManualCompletionButton(
                        label: nextButtonLabel,
                        action: onPrimaryAction
                    )
                }

                StretchSecondaryControls(
                    canGoBack: session.canGoBack,
                    onBack: onBack,
                    onSkip: onSkip
                )

                Text(session.phase.safetyNote)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            .padding(16)
            .padding(.bottom, 20)
        }
        .accessibilityIdentifier("stretch-session-scroll")
    }

    private var nextButtonLabel: String {
        guard session.stepIndex + 1 < session.totalSteps else { return "Finish routine" }
        let next = session.steps[session.stepIndex + 1]
        return next.stretch.id == step.stretch.id ? "Next position" : "Next stretch"
    }
}

private struct StretchProgressHeader: View {
    let session: StretchRoutineSession
    let onChooseStep: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: onChooseStep) {
                HStack {
                    Text(session.progressLabel)
                        .font(.subheadline.weight(.bold))
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2.weight(.bold))
                    Spacer()
                    Text("\(session.completedSteps) done")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Choose routine step, currently \(session.progressLabel)")
            .accessibilityIdentifier("stretch-step-picker-button")

            ProgressView(
                value: Double(session.completedSteps),
                total: Double(max(1, session.totalSteps))
            )
            .tint(TodayPalette.accent)
            .accessibilityLabel("Routine progress")
            .accessibilityValue(session.progressLabel)
        }
    }
}

private struct StretchInstructionCard: View {
    let step: StretchRoutineStep

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let position = step.position, position != "Hold" {
                Text(position)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(TodayPalette.accent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(TodayPalette.accent.opacity(0.12), in: Capsule())
            }

            Text(step.stretch.name)
                .font(.title2.weight(.bold))

            Label(step.stretch.dose.label, systemImage: step.stretch.dose.symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(step.stretch.cue)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)

            Label(step.stretch.targets, systemImage: "target")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if let support = step.stretch.support {
                Label(support, systemImage: "info.circle")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .todayCard()
    }
}

private struct StretchHoldTimerCard: View {
    let timer: StretchTimerState
    let reduceMotion: Bool
    let transitionTitle: String?
    let onPrimaryAction: () -> Void
    let onReset: () -> Void
    let onTimerFinished: () -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let seconds = timer.remainingSeconds(at: context.date)

            VStack(spacing: 14) {
                if timer.isTransition {
                    VStack(spacing: 3) {
                        Label("Switch position", systemImage: "arrow.triangle.2.circlepath")
                            .font(.headline)
                        if let transitionTitle {
                            Text("Next: \(transitionTitle)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                    }
                }

                StretchHoldTimerDial(
                    remainingSeconds: seconds,
                    totalSeconds: timer.totalSeconds ?? 1,
                    isTransition: timer.isTransition,
                    reduceMotion: reduceMotion
                )

                HStack(spacing: 10) {
                    Button(action: onPrimaryAction) {
                        Label(primaryLabel, systemImage: primarySymbol)
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(timer.isTransition ? TodayPalette.warm : TodayPalette.accent)
                    .controlSize(.large)
                    .accessibilityIdentifier("stretch-timer-button")

                    Button(action: onReset) {
                        Image(systemName: "arrow.counterclockwise")
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("Reset current hold")
                    .accessibilityIdentifier("stretch-timer-reset")
                }
            }
            .padding(18)
            .todayCard()
            .onChange(of: seconds) { _, newValue in
                if newValue == 0, timer.isRunning {
                    onTimerFinished()
                }
            }
        }
    }

    private var primaryLabel: String {
        if timer.isRunning { return "Pause" }
        return timer.hasStarted ? "Resume" : "Start 30-second hold"
    }

    private var primarySymbol: String {
        timer.isRunning ? "pause.fill" : "play.fill"
    }
}

private struct StretchManualCompletionButton: View {
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(label, systemImage: "checkmark")
                .font(.headline)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(TodayPalette.accent)
        .controlSize(.large)
        .accessibilityIdentifier("complete-stretch-step")
    }
}

private struct StretchSecondaryControls: View {
    let canGoBack: Bool
    let onBack: () -> Void
    let onSkip: () -> Void

    var body: some View {
        HStack {
            Button(action: onBack) {
                Label("Back", systemImage: "chevron.left")
            }
            .disabled(!canGoBack)

            Spacer()

            Button("Skip", action: onSkip)
                .foregroundStyle(.secondary)
                .accessibilityHint("Moves to the next step without completing this one")
        }
        .font(.subheadline.weight(.semibold))
        .padding(.horizontal, 4)
    }
}

struct StretchStepPicker: View {
    let steps: [StretchRoutineStep]
    @Binding var selection: Int
    let onCancel: () -> Void
    let onChoose: () -> Void

    var body: some View {
        NavigationStack {
            Picker("Routine step", selection: $selection) {
                ForEach(steps.indices, id: \.self) { index in
                    Text(stepLabel(steps[index], number: index + 1))
                        .tag(index)
                }
            }
            .pickerStyle(.wheel)
            .labelsHidden()
            .accessibilityIdentifier("stretch-step-picker")
            .navigationTitle("Choose a step")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Go", action: onChoose)
                }
            }
        }
    }

    private func stepLabel(_ step: StretchRoutineStep, number: Int) -> String {
        if let position = step.position, position != "Hold" {
            return "\(number). \(step.stretch.name), \(position)"
        }
        return "\(number). \(step.stretch.name)"
    }
}
