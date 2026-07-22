import Foundation
import Testing
import UIKit
@testable import Health_Tracker

struct StretchLibraryTests {
    @Test func routineHasTheExpectedShape() {
        #expect(StretchLibrary.dynamic.count == 7)
        #expect(StretchLibrary.cooldown.count == 5)
        #expect(StretchLibrary.all.count == 12)
    }

    @Test func everyStretchIsWellFormed() {
        for stretch in StretchLibrary.all {
            #expect(!stretch.name.isEmpty)
            #expect(!stretch.cue.isEmpty)
            #expect(!stretch.targets.isEmpty)
            #expect(!stretch.dose.label.isEmpty)
        }
    }

    @Test func stretchIDsAndGeneratedStepIDsAreUnique() {
        let stretchIDs = StretchLibrary.all.map(\.id)
        #expect(Set(stretchIDs).count == stretchIDs.count)

        for phase in StretchPhase.allCases {
            let stepIDs = StretchLibrary.steps(for: phase).map(\.id)
            #expect(Set(stepIDs).count == stepIDs.count)
        }
    }

    @Test func eachStretchSitsInItsOwnBucket() {
        #expect(StretchLibrary.dynamic.allSatisfy { $0.phase == .dynamic })
        #expect(StretchLibrary.cooldown.allSatisfy { $0.phase == .cooldown })
        #expect(StretchLibrary.stretches(for: .dynamic) == StretchLibrary.dynamic)
        #expect(StretchLibrary.stretches(for: .cooldown) == StretchLibrary.cooldown)
    }

    @Test func cooldownStretchesAreTimedAndDynamicMovesAreNot() {
        #expect(StretchLibrary.cooldown.allSatisfy { $0.dose.holdSeconds != nil })
        #expect(StretchLibrary.dynamic.allSatisfy { $0.dose.holdSeconds == nil })
    }

    @Test func everyDoseUsesAUsefulAmount() {
        for stretch in StretchLibrary.all {
            switch stretch.dose {
            case .distance(let yards, _):
                #expect(yards >= 10)
            case .repetitions(let count, _):
                #expect(count >= 5)
            case .hold(let seconds, let positions):
                #expect((20...45).contains(seconds))
                #expect(!positions.isEmpty)
                #expect(positions.allSatisfy { !$0.isEmpty })
            }
        }
    }

    @Test func guidedRoutineExpandsEveryHoldPosition() {
        #expect(StretchLibrary.steps(for: .dynamic).count == 7)
        #expect(StretchLibrary.steps(for: .cooldown).count == 11)

        let wallCalfSteps = StretchLibrary.steps(for: .cooldown)
            .filter { $0.stretch.id == "wall-calf" }
        #expect(
            wallCalfSteps.map(\.position) == [
                "Right, knee straight",
                "Right, knee bent",
                "Left, knee straight",
                "Left, knee bent",
            ]
        )
    }

    @Test func routineSessionAdvancesBacktracksAndRestartsSafely() {
        var session = StretchRoutineSession(phase: .dynamic)
        #expect(session.currentStep?.stretch.id == "butt-kickers")
        #expect(session.progressLabel == "1 of 7")
        #expect(!session.canGoBack)

        session.advance()
        #expect(session.currentStep?.stretch.id == "frankensteins")
        #expect(session.canGoBack)

        session.goBack()
        #expect(session.currentStep?.stretch.id == "butt-kickers")

        session.go(to: 4)
        #expect(session.stepIndex == 4)
        session.go(to: 500)
        #expect(session.stepIndex == session.totalSteps - 1)
        session.restart()

        for _ in 0...(session.totalSteps + 2) { session.advance() }
        #expect(session.isComplete)
        #expect(session.currentStep == nil)
        #expect(session.completedSteps == session.totalSteps)

        session.restart()
        #expect(!session.isComplete)
        #expect(session.stepIndex == 0)
    }

    @Test func warmupStartsWithEasyMovementAndEveryPhaseHasSafetyGuidance() {
        #expect(StretchPhase.dynamic.summary.contains("jog easy for 5 minutes"))
        #expect(StretchPhase.dynamic.estimatedMinutes >= 8)
        for phase in StretchPhase.allCases {
            #expect(!phase.safetyNote.isEmpty)
            #expect(phase.estimatedMinutes > 0)
            #expect(!phase.actionTitle.isEmpty)
        }
    }

    @Test func marathonRoutineKeepsTheFocusedCore() {
        #expect(
            StretchLibrary.dynamic.map(\.id) == [
                "butt-kickers",
                "frankensteins",
                "scoop-toe-touches",
                "open-close-gate",
                "walking-lunge-twist",
                "lateral-leg-swings",
                "front-back-leg-swings",
            ]
        )
        #expect(
            StretchLibrary.cooldown.map(\.id) == [
                "wall-calf",
                "standing-quad",
                "seated-hamstring",
                "butterfly",
                "pigeon",
            ]
        )
    }

    @Test func publicCopyAvoidsMisleadingOrUnsafeClaims() {
        let copy = StretchLibrary.all
            .flatMap { [$0.cue, $0.targets, $0.support ?? ""] }
            .joined(separator: " ")
            .lowercased()

        #expect(!copy.contains("it band"))
        #expect(!StretchLibrary.all.contains { $0.targets.lowercased() == "knees" })
        #expect(StretchPhase.cooldown.safetyNote.lowercased().contains("not pain"))
        #expect(StretchPhase.cooldown.safetyNote.lowercased().contains("never bounce"))
    }

    @Test func holdAndSwitchTimersClampAtZero() {
        let start = Date(timeIntervalSince1970: 1_000)
        let hold = StretchTimerState(
            totalSeconds: 30,
            pausedSeconds: 30,
            deadline: start.addingTimeInterval(30),
            isRunning: true,
            hasStarted: true,
            kind: .hold
        )
        #expect(hold.isTimed)
        #expect(!hold.isTransition)
        #expect(hold.remainingSeconds(at: start.addingTimeInterval(7)) == 23)
        #expect(hold.remainingSeconds(at: start.addingTimeInterval(40)) == 0)

        let transition = StretchTimerState(
            totalSeconds: 5,
            pausedSeconds: 5,
            deadline: nil,
            isRunning: false,
            hasStarted: true,
            kind: .transition
        )
        #expect(transition.isTransition)
        #expect(transition.remainingSeconds(at: start) == 5)
    }

    @MainActor
    @Test func everyStretchArtworkResolves() {
        for stretch in StretchLibrary.all {
            #expect(UIImage(named: stretch.assetName) != nil, "Missing artwork: \(stretch.assetName)")
        }
    }

    @MainActor
    @Test func everySymbolResolvesToASystemImage() {
        for stretch in StretchLibrary.all {
            #expect(UIImage(systemName: stretch.symbol) != nil, "Missing SF Symbol: \(stretch.symbol)")
            #expect(
                UIImage(systemName: stretch.dose.symbol) != nil,
                "Missing dose symbol: \(stretch.dose.symbol)"
            )
        }
        for phase in StretchPhase.allCases {
            #expect(UIImage(systemName: phase.symbol) != nil, "Missing phase symbol: \(phase.symbol)")
        }
    }
}
