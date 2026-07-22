import Foundation

/// The two halves of Rohan's run-day mobility routine.
enum StretchPhase: String, CaseIterable, Identifiable, Codable, Hashable {
    case dynamic
    case cooldown

    var id: Self { self }

    var title: String {
        switch self {
        case .dynamic: "Pre-run warm-up"
        case .cooldown: "Post-run mobility"
        }
    }

    var shortTitle: String {
        switch self {
        case .dynamic: "Pre-run"
        case .cooldown: "Post-run"
        }
    }

    var actionTitle: String {
        switch self {
        case .dynamic: "warm-up"
        case .cooldown: "cooldown"
        }
    }

    var symbol: String {
        switch self {
        case .dynamic: "figure.run"
        case .cooldown: "figure.cooldown"
        }
    }

    var summary: String {
        switch self {
        case .dynamic:
            "For easy runs, the first few easy minutes can be enough. Before workouts or races, jog easy for 5 minutes, then use these drills."
        case .cooldown:
            "Walk until your breathing settles. These holds are optional when they help you feel loose or keep your mobility."
        }
    }

    var safetyNote: String {
        switch self {
        case .dynamic:
            "Stay controlled and use a comfortable range. Skip anything that pinches or hurts."
        case .cooldown:
            "Look for gentle tension, not pain. Breathe normally and never bounce or force a position."
        }
    }

    var estimatedMinutes: Int {
        let movementSeconds = StretchLibrary.stretches(for: self)
            .reduce(0) { $0 + $1.dose.estimatedSeconds }
        let seconds = movementSeconds + (self == .dynamic ? 300 : 0)
        return max(1, Int(ceil(Double(seconds) / 60)))
    }
}

/// A concrete amount of work for a movement.
enum StretchDose: Hashable {
    case distance(yards: Int, roundTrip: Bool)
    case repetitions(count: Int, perSide: Bool)
    case hold(seconds: Int, positions: [String])

    var label: String {
        switch self {
        case .distance(let yards, let roundTrip):
            return roundTrip ? "About \(yards) yd, down and back" : "About \(yards) yd"
        case .repetitions(let count, let perSide):
            return perSide ? "\(count) reps each side" : "\(count) reps"
        case .hold(let seconds, let positions):
            if positions.count == 2 {
                return "\(seconds) sec each side"
            }
            if positions.count > 2 {
                return "\(seconds) sec each position"
            }
            return "\(seconds) sec hold"
        }
    }

    var symbol: String {
        switch self {
        case .distance: "arrow.left.and.right"
        case .repetitions: "repeat"
        case .hold: "timer"
        }
    }

    var estimatedSeconds: Int {
        switch self {
        case .distance:
            35
        case .repetitions(let count, let perSide):
            max(20, count * (perSide ? 2 : 1) * 2)
        case .hold(let seconds, let positions):
            seconds * max(1, positions.count)
        }
    }

    var holdSeconds: Int? {
        guard case .hold(let seconds, _) = self else { return nil }
        return seconds
    }

    var timerSeconds: Int? { holdSeconds }

    var stepPositions: [String?] {
        switch self {
        case .distance, .repetitions:
            [nil]
        case .hold(_, let positions):
            positions.isEmpty ? [nil] : positions.map(Optional.some)
        }
    }
}

struct Stretch: Identifiable, Hashable {
    let id: String
    let name: String
    let cue: String
    let targets: String
    let symbol: String
    let phase: StretchPhase
    let dose: StretchDose
    let support: String?

    var assetName: String { "stretch-\(id)" }
}

struct StretchRoutineStep: Identifiable, Hashable {
    let stretch: Stretch
    let position: String?
    let positionIndex: Int

    var id: String { "\(stretch.id)-\(positionIndex)" }
}

/// Small, deterministic state machine that keeps the guided routine testable.
struct StretchRoutineSession: Equatable {
    let phase: StretchPhase
    private(set) var stepIndex = 0

    var steps: [StretchRoutineStep] { StretchLibrary.steps(for: phase) }
    var totalSteps: Int { steps.count }
    var completedSteps: Int { min(stepIndex, totalSteps) }
    var isComplete: Bool { stepIndex >= totalSteps }
    var canGoBack: Bool { stepIndex > 0 }
    var currentStep: StretchRoutineStep? {
        guard steps.indices.contains(stepIndex) else { return nil }
        return steps[stepIndex]
    }

    var progressLabel: String {
        isComplete ? "Complete" : "\(stepIndex + 1) of \(totalSteps)"
    }

    mutating func advance() {
        stepIndex = min(stepIndex + 1, totalSteps)
    }

    mutating func goBack() {
        stepIndex = max(0, stepIndex - 1)
    }

    mutating func go(to index: Int) {
        guard totalSteps > 0 else {
            stepIndex = 0
            return
        }
        stepIndex = min(max(0, index), totalSteps - 1)
    }

    mutating func restart() {
        stepIndex = 0
    }
}

/// The routine itself, ordered to match how Rohan runs through it.
enum StretchLibrary {
    private static let bothSides = ["Right side", "Left side"]

    static let dynamic: [Stretch] = [
        Stretch(
            id: "butt-kickers",
            name: "Butt kickers",
            cue: "Jog forward with quick, relaxed steps and bring each heel toward your glutes.",
            targets: "Quads and running rhythm",
            symbol: "figure.run",
            phase: .dynamic,
            dose: .distance(yards: 20, roundTrip: true),
            support: nil
        ),
        Stretch(
            id: "frankensteins",
            name: "Frankensteins",
            cue: "Walk tall and lift one straight leg toward the opposite hand. Keep it smooth, stop before your back rounds, and switch legs each step.",
            targets: "Hamstrings",
            symbol: "figure.kickboxing",
            phase: .dynamic,
            dose: .distance(yards: 20, roundTrip: true),
            support: nil
        ),
        Stretch(
            id: "scoop-toe-touches",
            name: "Hamstring scoops",
            cue: "Set one heel forward with the toe up, send your hips back, and scoop both hands past the foot with a long spine. Stand tall and switch legs.",
            targets: "Hamstrings and calves",
            symbol: "figure.flexibility",
            phase: .dynamic,
            dose: .distance(yards: 20, roundTrip: true),
            support: nil
        ),
        Stretch(
            id: "open-close-gate",
            name: "Open gate, close gate",
            cue: "Lift one knee and rotate from the hip. Alternate opening the knee out and bringing it back across your body as you walk.",
            targets: "Hips and groin",
            symbol: "figure.mixed.cardio",
            phase: .dynamic,
            dose: .distance(yards: 20, roundTrip: true),
            support: nil
        ),
        Stretch(
            id: "walking-lunge-twist",
            name: "Walking lunge with a twist",
            cue: "Step into a comfortable lunge, keep the front knee tracking over your foot, and rotate your torso toward the front leg.",
            targets: "Hip flexors, glutes, and mid-back",
            symbol: "figure.strengthtraining.functional",
            phase: .dynamic,
            dose: .distance(yards: 20, roundTrip: true),
            support: nil
        ),
        Stretch(
            id: "lateral-leg-swings",
            name: "Lateral leg swings",
            cue: "Swing one leg across your body and out to the side without twisting your torso. Start small and let the range grow naturally.",
            targets: "Inner and outer hips",
            symbol: "figure.mixed.cardio",
            phase: .dynamic,
            dose: .repetitions(count: 10, perSide: true),
            support: "Use a wall, pole, or rack for balance."
        ),
        Stretch(
            id: "front-back-leg-swings",
            name: "Front-to-back leg swings",
            cue: "Swing one leg forward and back in a clean line while keeping your torso tall. Start small and stay controlled.",
            targets: "Hamstrings and hip flexors",
            symbol: "figure.walk",
            phase: .dynamic,
            dose: .repetitions(count: 10, perSide: true),
            support: "Use a wall, pole, or rack for balance."
        ),
    ]

    static let cooldown: [Stretch] = [
        Stretch(
            id: "wall-calf",
            name: "Wall calf stretches",
            cue: "Keep the back heel down and toes forward. Use a straight back knee for the upper calf, then bend that knee slightly for the lower calf.",
            targets: "Upper and lower calves",
            symbol: "figure.strengthtraining.functional",
            phase: .cooldown,
            dose: .hold(
                seconds: 30,
                positions: [
                    "Right, knee straight",
                    "Right, knee bent",
                    "Left, knee straight",
                    "Left, knee bent",
                ]
            ),
            support: "Use a wall or sturdy rack."
        ),
        Stretch(
            id: "standing-quad",
            name: "Standing quad stretch",
            cue: "Stand tall, keep your knees close, and bring one heel toward your glutes without pulling hard or arching your back.",
            targets: "Quads and hip flexors",
            symbol: "figure.yoga",
            phase: .cooldown,
            dose: .hold(seconds: 30, positions: bothSides),
            support: "Use a wall for balance if you need it."
        ),
        Stretch(
            id: "seated-hamstring",
            name: "Seated hamstring stretch",
            cue: "Extend one leg, tuck the other foot in, and hinge forward with a long back. Reach only as far as you can stay relaxed.",
            targets: "Hamstrings and calves",
            symbol: "figure.flexibility",
            phase: .cooldown,
            dose: .hold(seconds: 30, positions: bothSides),
            support: nil
        ),
        Stretch(
            id: "butterfly",
            name: "Butterfly",
            cue: "Sit tall with the soles of your feet together. Let your knees relax outward without pressing them down.",
            targets: "Inner thighs and groin",
            symbol: "figure.flexibility",
            phase: .cooldown,
            dose: .hold(seconds: 30, positions: ["Hold"]),
            support: nil
        ),
        Stretch(
            id: "pigeon",
            name: "Pigeon stretch",
            cue: "Start on hands and knees, bring one leg forward with the shin at a comfortable angle, and extend the other leg behind you. Keep your hips level and fold only if it feels comfortable.",
            targets: "Glutes and deep hip rotators",
            symbol: "figure.core.training",
            phase: .cooldown,
            dose: .hold(seconds: 30, positions: bothSides),
            support: "Use a seated figure four instead if you feel pinching in your hip or knee."
        ),
    ]

    static var all: [Stretch] { dynamic + cooldown }

    static func stretches(for phase: StretchPhase) -> [Stretch] {
        switch phase {
        case .dynamic: dynamic
        case .cooldown: cooldown
        }
    }

    static func steps(for phase: StretchPhase) -> [StretchRoutineStep] {
        stretches(for: phase).flatMap { stretch in
            stretch.dose.stepPositions.enumerated().map { index, position in
                StretchRoutineStep(
                    stretch: stretch,
                    position: position,
                    positionIndex: index
                )
            }
        }
    }
}
