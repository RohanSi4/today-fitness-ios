import Foundation

enum AppTab: String, CaseIterable, Identifiable {
    case today
    case history
    case insights

    var id: Self { self }

    var title: String {
        switch self {
        case .today: "Today"
        case .history: "History"
        case .insights: "Insights"
        }
    }

    var symbol: String {
        switch self {
        case .today: "sun.max.fill"
        case .history: "clock.arrow.circlepath"
        case .insights: "chart.xyaxis.line"
        }
    }
}

enum WorkoutKind: String, Codable, CaseIterable, Identifiable {
    case upper
    case lower
    case push
    case pull
    case legs
    case chest
    case back
    case other

    var id: Self { self }

    var title: String {
        self == .other ? "Blank" : rawValue.capitalized
    }

    var workoutTitle: String {
        self == .other ? "Workout" : "\(title) workout"
    }

    var completionTitle: String {
        self == .other ? "Workout complete" : "\(title) complete"
    }

    var symbol: String {
        switch self {
        case .upper: "figure.strengthtraining.traditional"
        case .lower, .legs: "figure.run"
        case .push: "arrow.up.forward"
        case .pull: "arrow.down.backward"
        case .chest: "figure.arms.open"
        case .back: "figure.strengthtraining.functional"
        case .other: "plus"
        }
    }

    var subtitle: String {
        switch self {
        case .upper: "Your usual upper day"
        case .lower: "Your usual lower day"
        case .push: "Chest, shoulders, and triceps"
        case .pull: "Back and biceps"
        case .legs: "Build a leg day"
        case .chest: "Chest-focused"
        case .back: "Back-focused"
        case .other: "Start empty and add anything"
        }
    }
}

enum ExerciseLoadMode: String, Codable {
    case total
    case perHand
    case bodyweight
    case addedWeight

    var shortLabel: String {
        switch self {
        case .total: "lb"
        case .perHand: "lb each"
        case .bodyweight: "bodyweight"
        case .addedWeight: "lb added"
        }
    }
}

enum MuscleGroup: String, Codable, CaseIterable, Identifiable {
    case upperChest
    case middleChest
    case lowerChest
    case frontDelts
    case sideDelts
    case rearDelts
    case lats
    case rhomboids
    case upperTraps
    case middleTraps
    case lowerTraps
    case bicepsLongHead
    case bicepsShortHead
    case brachialis
    case tricepsLongHead
    case tricepsLateralHead
    case tricepsMedialHead
    case forearms
    case rectusAbdominis
    case obliques
    case rectusFemoris
    case vastusLateralis
    case vastusMedialis
    case hamstrings
    case gluteMax
    case gluteMed
    case adductors
    case abductors
    case gastrocnemius
    case soleus
    case tibialisAnterior
    case lowerBack

    var id: Self { self }

    var title: String {
        switch self {
        case .upperChest: "Upper chest"
        case .middleChest: "Middle chest"
        case .lowerChest: "Lower chest"
        case .frontDelts: "Front delts"
        case .sideDelts: "Side delts"
        case .rearDelts: "Rear delts"
        case .lats: "Lats"
        case .rhomboids: "Rhomboids"
        case .upperTraps: "Upper traps"
        case .middleTraps: "Middle traps"
        case .lowerTraps: "Lower traps"
        case .bicepsLongHead: "Biceps long head"
        case .bicepsShortHead: "Biceps short head"
        case .brachialis: "Brachialis"
        case .tricepsLongHead: "Triceps long head"
        case .tricepsLateralHead: "Triceps lateral head"
        case .tricepsMedialHead: "Triceps medial head"
        case .forearms: "Forearms"
        case .rectusAbdominis: "Abs"
        case .obliques: "Obliques"
        case .rectusFemoris: "Rectus femoris"
        case .vastusLateralis: "Outer quads"
        case .vastusMedialis: "Inner quads"
        case .hamstrings: "Hamstrings"
        case .gluteMax: "Glute max"
        case .gluteMed: "Glute med"
        case .adductors: "Adductors"
        case .abductors: "Abductors"
        case .gastrocnemius: "Gastrocnemius"
        case .soleus: "Soleus"
        case .tibialisAnterior: "Tibialis anterior"
        case .lowerBack: "Lower back"
        }
    }
}

struct MuscleContribution: Codable, Hashable {
    let muscle: MuscleGroup
    let intensity: Double
}

struct ExerciseDefinition: Codable, Hashable, Identifiable {
    let id: String
    let name: String
    let aliases: [String]
    let equipment: String
    let loadMode: ExerciseLoadMode
    let weightIncrement: Double
    let muscles: [MuscleContribution]

    var searchText: String {
        ([name, equipment] + aliases).joined(separator: " ").lowercased()
    }
}

struct LoggedSet: Codable, Hashable, Identifiable {
    var id = UUID()
    var weight: Double?
    var reps: Int
    var isComplete: Bool
}

struct LoggedExercise: Codable, Hashable, Identifiable {
    var id = UUID()
    let exerciseID: String
    var sets: [LoggedSet]

    mutating func removeOneSet() {
        guard sets.count > 1 else { return }
        if let incomplete = sets.lastIndex(where: { !$0.isComplete }) {
            sets.remove(at: incomplete)
        } else {
            sets.removeLast()
        }
    }

    mutating func addSet() {
        let last = sets.last ?? LoggedSet(weight: nil, reps: 8, isComplete: false)
        sets.append(LoggedSet(weight: last.weight, reps: last.reps, isComplete: false))
    }
}

struct WorkoutSession: Codable, Hashable, Identifiable {
    var id = UUID()
    let kind: WorkoutKind
    let startedAt: Date
    var endedAt: Date?
    var exercises: [LoggedExercise]

    var completedSetCount: Int {
        exercises.flatMap(\.sets).filter(\.isComplete).count
    }
}

struct WeightEntry: Codable, Hashable, Identifiable {
    var id = UUID()
    let date: Date
    let pounds: Double
    let healthKitID: UUID?
}

struct StoredTodayData: Codable {
    var weights: [WeightEntry] = []
    var workouts: [WorkoutSession] = []
    var activeWorkout: WorkoutSession?
    var goalWeight: Double = 175
}

struct DashboardEnvelope: Codable {
    let generatedAt: Date?
    let trainingPlan: TrainingPlan?
}

struct TrainingPlan: Codable {
    let weekStart: String
    let weekEnd: String
    let prescribedMiles: Double
    let days: [TrainingPlanDay]
}

struct TrainingPlanDay: Codable, Identifiable, Hashable {
    let date: String
    let dayLabel: String
    let text: String
    let isKeyDay: Bool
    let details: [String]

    var id: String { date }

    var workoutKind: WorkoutKind? {
        if text.localizedCaseInsensitiveContains("upper body lift") { return .upper }
        if text.localizedCaseInsensitiveContains("lower body lift") { return .lower }
        return nil
    }

    var hasRun: Bool {
        text.localizedCaseInsensitiveContains("mile run") ||
        text.localizedCaseInsensitiveContains("mile long run")
    }

    var isRestOnly: Bool {
        text.lowercased() == "rest"
    }
}
