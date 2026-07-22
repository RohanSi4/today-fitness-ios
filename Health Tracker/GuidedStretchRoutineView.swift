import SwiftUI

enum StretchIntervalKind: Equatable {
    case hold
    case transition
}

struct GuidedStretchRoutineView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let transitionSeconds = 5
    private let onFinish: () -> Void

    @State private var session: StretchRoutineSession
    @State private var intervalKind: StretchIntervalKind = .hold
    @State private var pausedSeconds = 0
    @State private var deadline: Date?
    @State private var isTimerRunning = false
    @State private var hasStartedTimer = false
    @State private var feedbackTrigger = 0
    @State private var isStepPickerPresented = false
    @State private var pendingStepIndex = 0

    init(phase: StretchPhase, onFinish: @escaping () -> Void) {
        self.onFinish = onFinish
        _session = State(initialValue: StretchRoutineSession(phase: phase))
    }

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()

            if session.isComplete {
                StretchRoutineCompletion(
                    phase: session.phase,
                    totalSteps: session.totalSteps,
                    onDone: onFinish,
                    onRestart: restart
                )
            } else if let step = session.currentStep {
                StretchRoutineStepView(
                    session: session,
                    step: step,
                    timer: timerState,
                    reduceMotion: reduceMotion,
                    transitionTitle: nextStepTitle,
                    onPrimaryAction: handlePrimaryAction,
                    onResetTimer: resetCurrentTimer,
                    onTimerFinished: finishInterval,
                    onBack: goBack,
                    onSkip: advance,
                    onChooseStep: presentStepPicker
                )
            }
        }
        .navigationTitle(session.phase.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Choose a step", systemImage: "dial.medium", action: presentStepPicker)
                    Button("Restart routine", systemImage: "arrow.counterclockwise", action: restart)
                    Button("Exit routine", systemImage: "xmark") { dismiss() }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("Routine options")
            }
        }
        .sheet(isPresented: $isStepPickerPresented) {
            StretchStepPicker(
                steps: session.steps,
                selection: $pendingStepIndex,
                onCancel: { isStepPickerPresented = false },
                onChoose: choosePendingStep
            )
            .presentationDetents([.medium])
        }
        .sensoryFeedback(.success, trigger: feedbackTrigger)
        .onAppear(perform: resetCurrentTimer)
    }

    private var timerState: StretchTimerState {
        let seconds = intervalKind == .transition
            ? transitionSeconds
            : session.currentStep?.stretch.dose.holdSeconds
        return StretchTimerState(
            totalSeconds: seconds,
            pausedSeconds: pausedSeconds,
            deadline: deadline,
            isRunning: isTimerRunning,
            hasStarted: hasStartedTimer,
            kind: intervalKind
        )
    }

    private var nextStepTitle: String? {
        guard session.stepIndex + 1 < session.totalSteps else { return nil }
        let next = session.steps[session.stepIndex + 1]
        if let position = next.position, position != "Hold" {
            return "\(next.stretch.name), \(position)"
        }
        return next.stretch.name
    }

    private func handlePrimaryAction() {
        guard session.currentStep?.stretch.dose.holdSeconds != nil else {
            advance()
            return
        }
        toggleTimer()
    }

    private func toggleTimer() {
        if isTimerRunning {
            pausedSeconds = timerState.remainingSeconds(at: .now)
            deadline = nil
            isTimerRunning = false
        } else {
            if pausedSeconds <= 0 {
                pausedSeconds = intervalKind == .transition
                    ? transitionSeconds
                    : session.currentStep?.stretch.dose.holdSeconds ?? 0
            }
            hasStartedTimer = true
            deadline = .now.addingTimeInterval(TimeInterval(pausedSeconds))
            isTimerRunning = true
        }
    }

    private func finishInterval() {
        guard isTimerRunning else { return }
        feedbackTrigger += 1

        if intervalKind == .hold {
            guard session.stepIndex + 1 < session.totalSteps else {
                isTimerRunning = false
                deadline = nil
                pausedSeconds = 0
                session.advance()
                return
            }

            intervalKind = .transition
            pausedSeconds = transitionSeconds
            deadline = .now.addingTimeInterval(TimeInterval(transitionSeconds))
            isTimerRunning = true
            hasStartedTimer = true
        } else {
            session.advance()
            guard !session.isComplete else {
                isTimerRunning = false
                deadline = nil
                pausedSeconds = 0
                return
            }

            intervalKind = .hold
            pausedSeconds = session.currentStep?.stretch.dose.holdSeconds ?? 0
            deadline = .now.addingTimeInterval(TimeInterval(pausedSeconds))
            isTimerRunning = true
            hasStartedTimer = true
        }
    }

    private func resetCurrentTimer() {
        intervalKind = .hold
        pausedSeconds = session.currentStep?.stretch.dose.holdSeconds ?? 0
        deadline = nil
        isTimerRunning = false
        hasStartedTimer = false
    }

    private func advance() {
        session.advance()
        resetCurrentTimer()
        if session.isComplete { feedbackTrigger += 1 }
    }

    private func goBack() {
        session.goBack()
        resetCurrentTimer()
    }

    private func restart() {
        session.restart()
        resetCurrentTimer()
    }

    private func presentStepPicker() {
        pendingStepIndex = min(session.stepIndex, max(0, session.totalSteps - 1))
        isStepPickerPresented = true
    }

    private func choosePendingStep() {
        session.go(to: pendingStepIndex)
        resetCurrentTimer()
        isStepPickerPresented = false
    }
}

struct StretchTimerState {
    let totalSeconds: Int?
    let pausedSeconds: Int
    let deadline: Date?
    let isRunning: Bool
    let hasStarted: Bool
    let kind: StretchIntervalKind

    var isTimed: Bool { totalSeconds != nil }
    var isTransition: Bool { kind == .transition }

    func remainingSeconds(at date: Date) -> Int {
        guard let deadline else { return pausedSeconds }
        return max(0, Int(ceil(deadline.timeIntervalSince(date))))
    }
}
