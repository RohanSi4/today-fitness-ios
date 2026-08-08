import SwiftUI

struct RepRange: Equatable {
    let lower: Int
    let upper: Int

    var label: String { "\(lower)–\(upper) reps" }
}

struct HypertrophyPrescription: Equatable {
    let reps: RepRange
    let targetRIR: ClosedRange<Int>
    let restSeconds: ClosedRange<Int>

    var effortLabel: String {
        "\(targetRIR.lowerBound)–\(targetRIR.upperBound) RIR"
    }

    var restLabel: String {
        let lowerMinutes = Double(restSeconds.lowerBound) / 60
        let upperMinutes = Double(restSeconds.upperBound) / 60
        return "\(Self.minutes(lowerMinutes))–\(Self.minutes(upperMinutes)) min rest"
    }

    private static func minutes(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(value.rounded() == value ? 0 : 1)))
    }
}

struct NextSetTarget: Equatable {
    let weight: Double?
    let reps: Int
    let note: String
    let confidence: ProgressionConfidence
}

enum ProgressionConfidence: String, Equatable {
    case low
    case medium
    case high

    var label: String { "\(rawValue.capitalized) confidence" }
}

struct HypertrophyTemplateExercise: Identifiable, Codable, Hashable {
    var exerciseID: String
    var sets: Int

    var id: String { exerciseID }
}

struct HypertrophyTemplate: Identifiable, Codable, Hashable {
    let id: String
    var title: String
    var focus: String
    var targetMuscles: [WorkoutMuscleArea]
    var exercises: [HypertrophyTemplateExercise]

    var kind: WorkoutKind {
        id.hasPrefix("upper-") ? .upper : .lower
    }
}

enum WorkoutMuscleArea: String, Codable, CaseIterable, Identifiable {
    case chest = "Chest"
    case lats = "Lats"
    case midBack = "Mid back"
    case sideDelts = "Side delts"
    case rearDelts = "Rear delts"
    case biceps = "Biceps"
    case triceps = "Triceps"
    case quads = "Quads"
    case hamstrings = "Hamstrings"
    case glutes = "Glutes"
    case calves = "Calves"
    case core = "Core"

    var id: Self { self }

    func isTargeted(by muscle: MuscleGroup) -> Bool {
        switch self {
        case .chest:
            [.upperChest, .middleChest, .lowerChest].contains(muscle)
        case .lats:
            muscle == .lats
        case .midBack:
            [.rhomboids, .upperTraps, .middleTraps, .lowerTraps, .lowerBack].contains(muscle)
        case .sideDelts:
            muscle == .sideDelts
        case .rearDelts:
            muscle == .rearDelts
        case .biceps:
            [.bicepsLongHead, .bicepsShortHead, .brachialis].contains(muscle)
        case .triceps:
            [.tricepsLongHead, .tricepsLateralHead, .tricepsMedialHead].contains(muscle)
        case .quads:
            [.rectusFemoris, .vastusLateralis, .vastusMedialis].contains(muscle)
        case .hamstrings:
            muscle == .hamstrings
        case .glutes:
            [.gluteMax, .gluteMed, .adductors, .abductors].contains(muscle)
        case .calves:
            [.gastrocnemius, .soleus, .tibialisAnterior].contains(muscle)
        case .core:
            [.rectusAbdominis, .obliques].contains(muscle)
        }
    }
}

enum HypertrophyProgramming {
    static let upperA = HypertrophyTemplate(
        id: "upper-a",
        title: "Upper A",
        focus: "Smith incline, supported T-bar, and your machine pulldown",
        targetMuscles: [.chest, .lats, .midBack, .sideDelts, .biceps, .triceps],
        exercises: [
            .init(exerciseID: "smith-machine-incline-press", sets: 2),
            .init(exerciseID: "chest-supported-t-bar-row", sets: 2),
            .init(exerciseID: "machine-chest-fly", sets: 2),
            .init(exerciseID: "machine-pulldown", sets: 2),
            .init(exerciseID: "single-arm-cable-lateral-raise", sets: 2),
            .init(exerciseID: "overhead-bar-cable-triceps-extension", sets: 1),
            .init(exerciseID: "alternating-standing-dumbbell-curl", sets: 1),
        ]
    )

    static let lowerA = HypertrophyTemplate(
        id: "lower-a",
        title: "Lower A",
        focus: "Quad bias, capped before it compromises running",
        targetMuscles: [.quads, .hamstrings, .glutes, .calves, .core],
        exercises: [
            .init(exerciseID: "leg-press", sets: 2),
            .init(exerciseID: "seated-leg-curl", sets: 2),
            .init(exerciseID: "seated-leg-extension", sets: 2),
            .init(exerciseID: "machine-hip-thrust", sets: 2),
            .init(exerciseID: "standing-calf-raise", sets: 2),
            .init(exerciseID: "kneeling-rope-cable-crunch", sets: 1),
        ]
    )

    static let upperB = HypertrophyTemplate(
        id: "upper-b",
        title: "Upper B",
        focus: "Back first, pec deck chest work, and cable-biased arms",
        targetMuscles: [.chest, .lats, .midBack, .sideDelts, .rearDelts, .biceps, .triceps],
        exercises: [
            .init(exerciseID: "lat-pulldown", sets: 2),
            .init(exerciseID: "machine-chest-fly", sets: 2),
            .init(exerciseID: "seated-cable-row", sets: 2),
            .init(exerciseID: "single-arm-cable-lateral-raise", sets: 2),
            .init(exerciseID: "straight-bar-triceps-pushdown", sets: 1),
            .init(exerciseID: "bayesian-cable-curl", sets: 1),
            .init(exerciseID: "reverse-pec-deck", sets: 2),
        ]
    )

    static let lowerB = HypertrophyTemplate(
        id: "lower-b",
        title: "Lower B",
        focus: "Posterior-chain bias with failure kept off hinges",
        targetMuscles: [.quads, .hamstrings, .glutes, .calves, .core],
        exercises: [
            .init(exerciseID: "plate-loaded-squat", sets: 2),
            .init(exerciseID: "romanian-deadlift", sets: 2),
            .init(exerciseID: "seated-leg-extension", sets: 2),
            .init(exerciseID: "seated-leg-curl", sets: 2),
            .init(exerciseID: "hip-adductor-machine", sets: 1),
            .init(exerciseID: "standing-calf-raise", sets: 2),
            .init(exerciseID: "crunch", sets: 1),
        ]
    )

    static let templates = [upperA, lowerA, upperB, lowerB]

    static func template(id: String) -> HypertrophyTemplate? {
        templates.first { $0.id == id }
    }

    static func nextTemplate(for kind: WorkoutKind, workouts: [WorkoutSession]) -> HypertrophyTemplate? {
        switch kind {
        case .upper:
            return workouts.first(where: { $0.routineID == upperA.id || $0.routineID == upperB.id })?.routineID == upperA.id
                ? upperB : upperA
        case .lower:
            return workouts.first(where: { $0.routineID == lowerA.id || $0.routineID == lowerB.id })?.routineID == lowerA.id
                ? lowerB : lowerA
        default: return nil
        }
    }

    static func prescription(for exerciseID: String) -> HypertrophyPrescription {
        let id = ExerciseDefinition.components(of: exerciseID).base

        if longLeverAndSmallMuscleExercises.contains(id) {
            return .init(reps: .init(lower: 10, upper: 20), targetRIR: 0...2, restSeconds: 90...180)
        }
        if isolationExercises.contains(id) {
            return .init(reps: .init(lower: 8, upper: 15), targetRIR: 0...2, restSeconds: 90...180)
        }
        if stableMachineCompounds.contains(id) {
            return .init(reps: .init(lower: 6, upper: 10), targetRIR: 1...2, restSeconds: 120...240)
        }
        if heavyCompoundExercises.contains(id) {
            return .init(reps: .init(lower: 5, upper: 10), targetRIR: 2...3, restSeconds: 180...300)
        }
        return .init(reps: .init(lower: 6, upper: 12), targetRIR: 1...3, restSeconds: 120...240)
    }

    static func progressionSuggestion(
        history: LoggedExercise?,
        prescription: HypertrophyPrescription,
        weightIncrement: Double
    ) -> String {
        guard let history else {
            return "First tracked exposure. Choose a controlled load inside the target range."
        }
        let sets = history.sets.filter(\.isProgressionSet)
        guard !sets.isEmpty else { return "Log completed sets to unlock load guidance." }

        let allAtTop = sets.allSatisfy { $0.reps >= prescription.reps.upper }
        if allAtTop {
            let increment = weightIncrement.formatted(.number.precision(.fractionLength(0...1)))
            return "Top of the range across working sets. Try +\(increment) lb next time."
        }

        if sets.contains(where: { $0.reps < prescription.reps.lower }) {
            return "Below the rep range. Rest longer, then hold or slightly reduce the load."
        }
        return "Keep the load and add reps before adding weight."
    }

    static func nextSetTarget(
        current: LoggedExercise,
        history: LoggedExercise?,
        exercise: ExerciseDefinition
    ) -> NextSetTarget? {
        nextSetTarget(current: current, history: history.map { [$0] } ?? [], exercise: exercise)
    }

    static func nextSetTarget(
        current: LoggedExercise,
        history: [LoggedExercise],
        exercise: ExerciseDefinition
    ) -> NextSetTarget? {
        guard let nextIndex = current.sets.firstIndex(where: { !$0.isPerformed }) else { return nil }
        let prescription = prescription(for: current.baseExerciseID)
        let currentSet = current.sets[nextIndex]
        if currentSet.setType == .backoff {
            let priorBackoffs = history.compactMap { exposure in
                exposure.sets.first { $0.isPerformed && $0.setType == .backoff }
            }
            let prior = priorBackoffs.first
            return NextSetTarget(
                weight: currentSet.weight ?? prior?.weight,
                reps: currentSet.reps > 0 ? currentSet.reps : (prior?.reps ?? prescription.reps.lower),
                note: prior == nil
                    ? "Backoff set. Use a controlled lower load and establish a baseline."
                    : "Backoff set. Match the prior backoff before adding reps or load.",
                confidence: priorBackoffs.count >= 2 ? .medium : .low
            )
        }
        let exposures = history.prefix(3).map { $0.sets.filter(\.isProgressionSet) }.filter { !$0.isEmpty }
        let priorSets = exposures.first ?? []
        let confidence: ProgressionConfidence = exposures.count >= 3 ? .high : (exposures.count == 2 ? .medium : .low)

        if currentSet.setType == .warmup {
            return NextSetTarget(
                weight: currentSet.weight,
                reps: currentSet.reps > 0 ? currentSet.reps : prescription.reps.lower,
                note: "Warm-up set. Prepare the movement without turning it into fatigue.",
                confidence: .high
            )
        }

        guard !priorSets.isEmpty else {
            let reps = currentSet.reps > 0 ? currentSet.reps : prescription.reps.lower
            return NextSetTarget(
                weight: currentSet.weight,
                reps: reps,
                note: "First tracked exposure. Establish a clean baseline.",
                confidence: .low
            )
        }

        let workingIndex = current.sets.prefix(nextIndex).filter { $0.setType.countsAsWorking }.count
        let prior = priorSets[min(workingIndex, priorSets.count - 1)]
        let comparable = comparableExposures(exposures)
        let allAtTopTwice = comparable.count >= 2 && comparable.prefix(2).allSatisfy { exposure in
            exposure.allSatisfy { $0.reps >= prescription.reps.upper }
        }
        if allAtTopTwice,
           exercise.loadMode != .bodyweight,
           let priorWeight = prior.weight {
            return NextSetTarget(
                weight: priorWeight + exercise.weightIncrement,
                reps: prescription.reps.lower,
                note: "You topped the range in two comparable sessions. Add the smallest load jump.",
                confidence: confidence
            )
        }

        let completedNow = current.sets.filter(\.isProgressionSet)
        if let first = completedNow.first,
           let last = completedNow.last,
           completedNow.count >= 2,
           first.reps > 0,
           Double(last.reps) / Double(first.reps) < 0.75 {
            return NextSetTarget(
                weight: last.weight ?? prior.weight,
                reps: max(prescription.reps.lower, last.reps),
                note: "Reps dropped sharply this workout. Keep the load and take the rest you need.",
                confidence: .high
            )
        }

        let targetReps = min(prescription.reps.upper, max(1, prior.reps + 1))
        let note: String
        if prior.reps < prescription.reps.lower {
            note = "Hold the load and work back into the target range."
        } else if targetReps > prior.reps {
            let totals = comparable.prefix(3).map { $0.reduce(0) { $0 + $1.reps } }
            let context = totals.count >= 2 ? " across \(totals.count) comparable sessions" : ""
            note = "Beat this set by one rep\(context)."
        } else {
            note = "Match the top of the range with cleaner execution."
        }
        return NextSetTarget(weight: prior.weight, reps: targetReps, note: note, confidence: confidence)
    }

    /// Exact exercise IDs already separate machine brands. This second gate keeps
    /// mixed-load exposures from pretending to be the same progression attempt.
    private static func comparableExposures(_ exposures: [[LoggedSet]]) -> [[LoggedSet]] {
        guard let baseline = exposures.first,
              let baselineLoad = representativeLoad(for: baseline) else { return exposures }
        return exposures.filter { exposure in
            guard let load = representativeLoad(for: exposure) else { return false }
            return abs(load - baselineLoad) < 0.01
        }
    }

    private static func representativeLoad(for sets: [LoggedSet]) -> Double? {
        let loads = sets.compactMap(\.weight)
        guard !loads.isEmpty else { return 0 }
        let counts = Dictionary(grouping: loads, by: { $0 }).mapValues(\.count)
        return counts.max { lhs, rhs in
            lhs.value == rhs.value ? lhs.key < rhs.key : lhs.value < rhs.value
        }?.key
    }

    private static let longLeverAndSmallMuscleExercises: Set<String> = [
        "single-arm-cable-lateral-raise", "reverse-pec-deck", "cable-rear-delt-fly",
        "dumbbell-reverse-fly", "hip-adductor-machine", "hip-abductor-machine",
        "kneeling-rope-cable-crunch", "crunch",
    ]

    private static let isolationExercises: Set<String> = [
        "machine-chest-fly", "seated-leg-extension", "single-leg-extension",
        "seated-leg-curl", "lying-leg-curl", "standing-leg-curl", "calf-raise",
        "standing-calf-raise", "seated-calf-raise", "leg-press-calf-raise",
        "rope-triceps-pushdown", "straight-bar-triceps-pushdown",
        "overhead-rope-triceps-extension", "machine-preacher-curl", "preacher-curl",
        "overhead-bar-cable-triceps-extension", "alternating-standing-dumbbell-curl",
        "incline-dumbbell-curl", "cable-curl", "bayesian-cable-curl",
    ]

    private static let heavyCompoundExercises: Set<String> = [
        "plate-loaded-squat", "leg-press", "horizontal-leg-press", "vertical-leg-press",
        "romanian-deadlift", "dumbbell-romanian-deadlift", "barbell-hip-thrust",
        "machine-hip-thrust", "smith-machine-hip-thrust", "barbell-bench-press",
        "incline-barbell-bench-press", "pull-up",
    ]

    private static let stableMachineCompounds: Set<String> = [
        "incline-machine-chest-press", "machine-chest-press", "plate-loaded-chest-press",
        "neutral-grip-machine-shoulder-press", "lat-pulldown", "seated-machine-row",
        "chest-supported-machine-row", "smith-machine-incline-press",
        "chest-supported-t-bar-row", "machine-pulldown",
    ]
}

struct HypertrophyPlanView: View {
    @ObservedObject var store: TodayStore
    @ObservedObject var catalog: ExerciseCatalog

    var body: some View {
        List {
            Section("Up next") {
                nextTemplateRow(for: .upper)
                nextTemplateRow(for: .lower)
            }

            Section {
                Text("Four lifting days give most major muscle groups two weekly exposures while leaving room for key runs. The two-set base is a recoverable starting dose, not a universal optimum. Run Upper A, Lower A, Upper B, Lower B in order and move lower days away from priority runs when practical.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Evidence-informed starting program")
            }

            Section("What the evidence changes") {
                Label("Use broad practical ranges: 6–10 on stable compounds, 8–15 on isolations, and 10–20 where heavy loading is awkward", systemImage: "arrow.left.and.right")
                Label("Your completed working sets default to failure; on squats and hinges, technical failure means stop before form breaks", systemImage: "shield.lefthalf.filled")
                Label("Treat frequency as a way to distribute quality weekly work—not a hypertrophy multiplier", systemImage: "calendar.badge.clock")
                Label("Adjust weekly sets gradually from multi-week performance and recovery trends", systemImage: "chart.line.uptrend.xyaxis")
            }

            ForEach(store.routines) { template in
                Section {
                    ForEach(template.exercises) { item in
                        templateRow(item)
                    }
                } header: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(template.title)
                        Text(template.focus).textCase(nil)
                    }
                }
            }

            Section("How Today adapts it") {
                Label("Add reps, then load, across comparable sets", systemImage: "arrow.up.right")
                Label("Judge trends over several exposures, not one workout", systemImage: "chart.line.uptrend.xyaxis")
                Label("Consider a small volume increase after several recovered exposures without progress", systemImage: "plus.rectangle.on.rectangle")
                Label("Reduce lower-body fatigue around key running sessions", systemImage: "figure.run")
            }

            Section("Evidence and limitations") {
                NavigationLink {
                    ResearchLibraryView()
                } label: {
                    Label("Open the evidence guide", systemImage: "books.vertical.fill")
                }
                Text("Today’s exact exercise order and starting set counts are personalized coaching choices. The evidence supports the principles, not one uniquely optimal routine.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Hypertrophy plan")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func templateRow(_ item: HypertrophyTemplateExercise) -> some View {
        let prescription = HypertrophyProgramming.prescription(for: item.exerciseID)
        return HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text(catalog.exercise(id: item.exerciseID)?.name ?? item.exerciseID)
                    .font(.subheadline.weight(.semibold))
                Text(prescription.reps.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            Text("\(item.sets) sets")
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(TodayPalette.accent)
        }
        .accessibilityElement(children: .combine)
    }

    private func nextTemplateRow(for kind: WorkoutKind) -> some View {
        let template = store.nextRoutine(for: kind)
        return HStack {
            Label(kind.title, systemImage: kind.symbol)
            Spacer()
            Text(template?.title ?? "Custom")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(TodayPalette.accent)
        }
    }
}
