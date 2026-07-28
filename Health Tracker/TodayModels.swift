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

    var isPerformed: Bool {
        isComplete && reps > 0
    }
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
        exercises.flatMap(\.sets).filter(\.isPerformed).count
    }
}

struct WeightEntry: Codable, Hashable, Identifiable {
    var id = UUID()
    let date: Date
    let pounds: Double
    let healthKitID: UUID?
}

struct StoredTodayData: Codable {
    static let defaultGoalWeight: Double = 175

    var weights: [WeightEntry] = []
    var workouts: [WorkoutSession] = []
    var activeWorkout: WorkoutSession?
    var goalWeight: Double = StoredTodayData.defaultGoalWeight

    /// Entries that were in the file but could not be decoded, so this value is a
    /// partial view of what is on disk. Never encoded. `TodayStore` uses it to keep
    /// a copy of the original bytes instead of quietly writing the shorter list
    /// back over a year of training history.
    private(set) var unreadableEntryCount = 0

    private enum CodingKeys: String, CodingKey {
        case weights
        case workouts
        case activeWorkout
        case goalWeight
    }

    init(
        weights: [WeightEntry] = [],
        workouts: [WorkoutSession] = [],
        activeWorkout: WorkoutSession? = nil,
        goalWeight: Double = StoredTodayData.defaultGoalWeight
    ) {
        self.weights = weights
        self.workouts = workouts
        self.activeWorkout = activeWorkout
        self.goalWeight = goalWeight
    }

    // Decoding is deliberately element-by-element. The synthesised array decode is
    // all-or-nothing: one workout written by a newer build, or one entry with a
    // field this build cannot parse, used to fail the whole file, which downgraded
    // to "corrupt" and put the entire archive at risk. Losing one session beats
    // losing every session. Anything skipped is counted so the caller can preserve
    // the original file.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        var dropped = 0
        weights = try Self.decodeLossyArray(WeightEntry.self, from: container, forKey: .weights, dropped: &dropped)
        workouts = try Self.decodeLossyArray(WorkoutSession.self, from: container, forKey: .workouts, dropped: &dropped)

        if Self.hasValue(container, .activeWorkout) {
            activeWorkout = try? container.decode(WorkoutSession.self, forKey: .activeWorkout)
            if activeWorkout == nil { dropped += 1 }
        }

        if Self.hasValue(container, .goalWeight) {
            let decoded = try? container.decode(Double.self, forKey: .goalWeight)
            if decoded == nil { dropped += 1 }
            goalWeight = decoded ?? Self.defaultGoalWeight
        }
        unreadableEntryCount = dropped
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(weights, forKey: .weights)
        try container.encode(workouts, forKey: .workouts)
        try container.encodeIfPresent(activeWorkout, forKey: .activeWorkout)
        try container.encode(goalWeight, forKey: .goalWeight)
    }

    private static func hasValue(
        _ container: KeyedDecodingContainer<CodingKeys>,
        _ key: CodingKeys
    ) -> Bool {
        container.contains(key) && (try? container.decodeNil(forKey: key)) != true
    }

    /// Throws only when the key holds something that is not an array at all, which
    /// really is a corrupt file rather than one stale entry.
    private static func decodeLossyArray<T: Decodable>(
        _ type: T.Type,
        from container: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys,
        dropped: inout Int
    ) throws -> [T] {
        guard hasValue(container, key) else { return [] }
        let raw = try container.decode([LossyDecoded<T>].self, forKey: key)
        dropped += raw.lazy.filter { $0.value == nil }.count
        return raw.compactMap(\.value)
    }
}

/// Decodes an element, or records that it could not be decoded, without failing
/// the array around it.
private struct LossyDecoded<T: Decodable>: Decodable {
    let value: T?

    init(from decoder: Decoder) throws {
        value = try? T(from: decoder)
    }
}

struct DashboardEnvelope: Codable {
    let generatedAt: Date?
    let trainingPlan: TrainingPlan?
}

struct TrainingPlan: Codable, Equatable {
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
        plannedRunMiles != nil
    }

    var plannedRunMiles: Double? {
        let pattern = #"(?i)\b(\d{1,2}(?:\.\d{1,2})?)\s*(?:mile|miles|mi)\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(
                in: text,
                range: NSRange(text.startIndex..., in: text)
              ),
              let range = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return Double(text[range])
    }

    var isRestOnly: Bool {
        text.lowercased() == "rest"
    }
}
