import Foundation

/// The two halves of Rohan's run-day mobility routine.
enum StretchPhase: String, CaseIterable, Identifiable, Codable {
    case dynamic
    case cooldown

    var id: Self { self }

    /// Long title for the routine screen.
    var title: String {
        switch self {
        case .dynamic: "Dynamic warm-up"
        case .cooldown: "Static cool-down"
        }
    }

    /// Short label for the segmented control.
    var shortTitle: String {
        switch self {
        case .dynamic: "Dynamic"
        case .cooldown: "Static"
        }
    }

    var symbol: String {
        switch self {
        case .dynamic: "figure.run"
        case .cooldown: "figure.cooldown"
        }
    }

    /// One line of context shown above the cards.
    var summary: String {
        switch self {
        case .dynamic:
            "Before your run. Find about 20 yards and work through each one down and back."
        case .cooldown:
            "After your run. Ease into each hold and breathe, both sides where it applies."
        }
    }
}

/// How a given stretch is performed, shown as a small hint chip on each card.
enum StretchStyle: Hashable, CaseIterable {
    case travel
    case pole
    case hold

    var label: String {
        switch self {
        case .travel: "≈20 yd, down and back"
        case .pole: "Hold a pole for balance"
        case .hold: "Hold 20–30 seconds"
        }
    }

    var symbol: String {
        switch self {
        case .travel: "arrow.left.and.right"
        case .pole: "figure.stand"
        case .hold: "timer"
        }
    }
}

struct Stretch: Identifiable, Hashable {
    let id: String
    let name: String
    /// The short how-to cue shown when the card is opened.
    let cue: String
    /// Plain-language area the stretch targets.
    let targets: String
    /// SF Symbol placeholder standing in until real photos are attached.
    let symbol: String
    let phase: StretchPhase
    let style: StretchStyle
}

/// The routine itself. Ordered to match how Rohan actually runs through it.
enum StretchLibrary {
    static let dynamic: [Stretch] = [
        Stretch(
            id: "butt-kickers",
            name: "Butt kickers",
            cue: "Jog forward and flick your heels up toward your glutes with every step.",
            targets: "Quads and knees",
            symbol: "figure.run",
            phase: .dynamic,
            style: .travel
        ),
        Stretch(
            id: "frankensteins",
            name: "Frankensteins",
            cue: "Walk forward kicking one straight leg up to tap the opposite hand, then switch legs.",
            targets: "Hamstrings",
            symbol: "figure.kickboxing",
            phase: .dynamic,
            style: .travel
        ),
        Stretch(
            id: "scoop-toe-touches",
            name: "Scoop toe touches",
            cue: "Step forward and scoop both hands down past your toes, then swing tall as you come up.",
            targets: "Hamstrings and lower back",
            symbol: "figure.flexibility",
            phase: .dynamic,
            style: .travel
        ),
        Stretch(
            id: "open-close-gate",
            name: "Open gate, close gate",
            cue: "One step, lift the knee and rotate it out to open the gate. Next step, rotate it across your body to close it.",
            targets: "Hips and groin",
            symbol: "figure.mixed.cardio",
            phase: .dynamic,
            style: .travel
        ),
        Stretch(
            id: "carioca",
            name: "Carioca (karaoke)",
            cue: "Travel sideways crossing one foot over the other and rotating the hips. Do it facing both directions.",
            targets: "Hips and obliques",
            symbol: "figure.dance",
            phase: .dynamic,
            style: .travel
        ),
        Stretch(
            id: "walking-lunge-twist",
            name: "Walking lunge with a twist",
            cue: "Step into a forward lunge and rotate your torso over the front leg, then walk into the next lunge.",
            targets: "Hip flexors and mid-back",
            symbol: "figure.strengthtraining.functional",
            phase: .dynamic,
            style: .travel
        ),
        Stretch(
            id: "lateral-leg-swings",
            name: "Lateral leg swings",
            cue: "Hold a pole and swing one leg left to right across your body, keeping your torso steady. Switch legs.",
            targets: "Adductors and abductors",
            symbol: "figure.mixed.cardio",
            phase: .dynamic,
            style: .pole
        ),
        Stretch(
            id: "front-back-leg-swings",
            name: "Front-to-back leg swings",
            cue: "Hold the pole and swing one leg straight forward and back in a clean line. Switch legs.",
            targets: "Hamstrings and hip flexors",
            symbol: "figure.walk",
            phase: .dynamic,
            style: .pole
        ),
    ]

    static let cooldown: [Stretch] = [
        Stretch(
            id: "wall-calf",
            name: "Wall calf stretch",
            cue: "Right off the pole, lean your hands on the wall, step one foot back with the leg straight and heel pressed down, and sink in for a quick calf stretch. Switch sides.",
            targets: "Calves",
            symbol: "figure.strengthtraining.functional",
            phase: .cooldown,
            style: .hold
        ),
        Stretch(
            id: "crossed-toe-touch",
            name: "Crossed-leg toe touch",
            cue: "Cross one foot in front of the other, fold forward, and reach for your toes. Swap the cross and repeat.",
            targets: "Hamstrings and IT band",
            symbol: "figure.flexibility",
            phase: .cooldown,
            style: .hold
        ),
        Stretch(
            id: "wide-toe-touch",
            name: "Wide-stance toe touches",
            cue: "Feet wide, reach down toward each foot in turn, then center, to open the inner hamstrings.",
            targets: "Inner hamstrings and adductors",
            symbol: "figure.flexibility",
            phase: .cooldown,
            style: .hold
        ),
        Stretch(
            id: "crossed-side-bend",
            name: "Crossed-leg side bend",
            cue: "Cross one leg over the other and reach up and over to that side. Switch and repeat.",
            targets: "Hip flexors and outer thigh",
            symbol: "figure.cooldown",
            phase: .cooldown,
            style: .hold
        ),
        Stretch(
            id: "standing-quad",
            name: "Standing quad stretch",
            cue: "Stand tall, bend one knee and grab that foot behind you, easing the heel toward your glutes like a held butt kicker. Switch sides.",
            targets: "Quads and hip flexors",
            symbol: "figure.yoga",
            phase: .cooldown,
            style: .hold
        ),
        Stretch(
            id: "seated-hamstring",
            name: "Seated hamstring stretch",
            cue: "Sit with one leg straight and the other tucked in, then reach toward the extended foot. Switch sides.",
            targets: "Hamstrings and calves",
            symbol: "figure.flexibility",
            phase: .cooldown,
            style: .hold
        ),
        Stretch(
            id: "butterfly",
            name: "Butterfly",
            cue: "Sit with the soles of your feet together and let your knees settle toward the floor.",
            targets: "Groin and adductors",
            symbol: "figure.flexibility",
            phase: .cooldown,
            style: .hold
        ),
        Stretch(
            id: "seated-twist",
            name: "Seated spinal twist",
            cue: "Sit tall, cross one leg over, and twist toward the top knee, arching to open the outer thigh and hip.",
            targets: "Glutes, outer thigh, hips",
            symbol: "figure.flexibility",
            phase: .cooldown,
            style: .hold
        ),
        Stretch(
            id: "pigeon",
            name: "Pigeon stretch",
            cue: "Lie face down, bring one knee up and forward under your hips, and let your bodyweight settle over that leg while the other stays long behind you. Switch sides.",
            targets: "Hips, glutes, and quad",
            symbol: "figure.core.training",
            phase: .cooldown,
            style: .hold
        ),
        Stretch(
            id: "downward-calf",
            name: "Down-dog calf stretch",
            cue: "From a downward-dog or push-up position, rest one foot behind the other ankle and press the bottom heel toward the floor. Switch sides.",
            targets: "Calves, gastroc and soleus",
            symbol: "figure.core.training",
            phase: .cooldown,
            style: .hold
        ),
    ]

    static var all: [Stretch] { dynamic + cooldown }

    static func stretches(for phase: StretchPhase) -> [Stretch] {
        switch phase {
        case .dynamic: dynamic
        case .cooldown: cooldown
        }
    }
}
