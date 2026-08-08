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

/// The kind of hardware a movement is performed on.
///
/// This is the axis that decides whether the *brand* of the equipment changes the
/// number you write down. Cam profiles, lever-arm lengths, pulley ratios, and stack
/// increments are brand-specific, so 150 on a Life Fitness pulldown is simply not the
/// same load as 150 on a Hammer Strength pulldown. A 45 lb barbell weighs 45 lb
/// everywhere and a 50 lb dumbbell weighs 50 lb everywhere, so for those the brand is
/// decoration and recording it would only fragment history for no benefit.
enum EquipmentClass: String, Codable, CaseIterable, Sendable {
    case selectorized
    case plateLoaded
    case cable
    case smith
    case barbell
    case dumbbell
    case bodyweight
    case other

    /// Whether the same nominal weight means a different load depending on the maker.
    var brandChangesTheLoad: Bool {
        switch self {
        case .selectorized, .plateLoaded, .cable, .smith: true
        case .barbell, .dumbbell, .bodyweight, .other: false
        }
    }
}

/// A manufacturer of gym equipment.
///
/// The raw value is the slug used inside a brand-qualified exercise id, so it has to
/// stay stable forever: it is part of the key that logged history is stored under.
enum EquipmentBrand: String, Codable, CaseIterable, Identifiable, Sendable {
    case lifeFitness = "life-fitness"
    case hammerStrength = "hammer-strength"
    case cybex = "cybex"
    case technogym = "technogym"
    case precor = "precor"
    case nautilus = "nautilus"
    case matrix = "matrix"
    case bodySolid = "body-solid"
    case rogue = "rogue"
    case eleiko = "eleiko"
    case atlantis = "atlantis"
    case arsenal = "arsenal"
    case prime = "prime"
    case panatta = "panatta"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .lifeFitness: "Life Fitness"
        case .hammerStrength: "Hammer Strength"
        case .cybex: "Cybex"
        case .technogym: "Technogym"
        case .precor: "Precor"
        case .nautilus: "Nautilus"
        case .matrix: "Matrix"
        case .bodySolid: "Body-Solid"
        case .rogue: "Rogue"
        case .eleiko: "Eleiko"
        case .atlantis: "Atlantis"
        case .arsenal: "Arsenal Strength"
        case .prime: "PRIME"
        case .panatta: "Panatta"
        }
    }

    /// Which hardware categories this maker actually builds.
    ///
    /// Deliberately coarse. Claiming "Cybex makes exactly these 41 machines" would rot
    /// the moment a line is refreshed, and inventing model names is worse than being
    /// vague. What is durable is the category: Rogue and Eleiko build bars, racks,
    /// plate-loaded levers, and cable towers but no pin-loaded stack line, while
    /// Life Fitness sells its plate-loaded product under the Hammer Strength name.
    var manufactures: Set<EquipmentClass> {
        switch self {
        case .lifeFitness: [.selectorized, .cable]
        case .hammerStrength: [.plateLoaded, .selectorized, .cable, .smith]
        case .cybex: [.selectorized, .plateLoaded, .cable]
        case .technogym: [.selectorized, .plateLoaded, .cable]
        case .precor: [.selectorized, .plateLoaded, .cable]
        case .nautilus: [.selectorized, .plateLoaded, .cable]
        case .matrix: [.selectorized, .plateLoaded, .cable, .smith]
        case .bodySolid: [.selectorized, .plateLoaded, .cable, .smith]
        case .rogue: [.plateLoaded, .cable]
        case .eleiko: [.plateLoaded, .cable]
        case .atlantis: [.selectorized, .plateLoaded, .cable]
        case .arsenal: [.plateLoaded, .selectorized, .cable, .smith]
        case .prime: [.selectorized, .plateLoaded]
        case .panatta: [.selectorized, .plateLoaded, .cable, .smith]
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
    /// Either a plain catalog id (`lat-pulldown`) or a brand-qualified one
    /// (`lat-pulldown@hammer-strength`). See ``qualifiedID(base:brand:)``.
    let id: String
    let name: String
    let aliases: [String]
    let equipment: String
    let loadMode: ExerciseLoadMode
    let weightIncrement: Double
    let muscles: [MuscleContribution]
    /// What the movement is performed on. Decides whether brand is a meaningful axis.
    let equipmentClass: EquipmentClass
    /// Nil on the generic catalog row. Set on a brand-qualified instance, and on the
    /// handful of movements where the maker *is* the movement (a Hammer Strength
    /// Iso-Lateral Row is not a generic seated row with a sticker on it).
    let brand: EquipmentBrand?
    /// True when brand is baked into the movement itself and cannot be re-selected.
    let isBrandSignature: Bool

    init(
        id: String,
        name: String,
        aliases: [String],
        equipment: String,
        loadMode: ExerciseLoadMode,
        weightIncrement: Double,
        muscles: [MuscleContribution],
        equipmentClass: EquipmentClass = .other,
        brand: EquipmentBrand? = nil,
        isBrandSignature: Bool = false
    ) {
        self.id = id
        self.name = name
        self.aliases = aliases
        self.equipment = equipment
        self.loadMode = loadMode
        self.weightIncrement = weightIncrement
        self.muscles = muscles
        self.equipmentClass = equipmentClass
        self.brand = brand
        self.isBrandSignature = isBrandSignature
    }

    /// Tolerant of payloads written before equipment class and brand existed.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        aliases = try container.decodeIfPresent([String].self, forKey: .aliases) ?? []
        equipment = try container.decodeIfPresent(String.self, forKey: .equipment) ?? "other"
        loadMode = try container.decodeIfPresent(ExerciseLoadMode.self, forKey: .loadMode) ?? .total
        weightIncrement = try container.decodeIfPresent(Double.self, forKey: .weightIncrement) ?? 5
        muscles = try container.decodeIfPresent([MuscleContribution].self, forKey: .muscles) ?? []
        equipmentClass = try container.decodeIfPresent(EquipmentClass.self, forKey: .equipmentClass) ?? .other
        brand = try container.decodeIfPresent(EquipmentBrand.self, forKey: .brand)
        isBrandSignature = try container.decodeIfPresent(Bool.self, forKey: .isBrandSignature) ?? false
    }

    var searchText: String {
        ([name, equipment] + aliases + [brand?.title].compactMap { $0 })
            .joined(separator: " ")
            .lowercased()
    }

    /// The generic movement behind a brand-qualified instance.
    var baseID: String { Self.components(of: id).base }

    /// Whether a brand can be attached to this movement when logging it.
    var acceptsBrand: Bool { !isBrandSignature && equipmentClass.brandChangesTheLoad }
}

extension ExerciseDefinition {
    /// Brand is stored as a suffix on the logged exercise id rather than as a separate
    /// field, and rather than as separate catalog rows per brand.
    ///
    /// Three options were on the table:
    ///
    /// 1. Bake the brand into the name and ship a row per brand. That is 250 movements
    ///    times 14 makers, so searching "lat pulldown" buries the thing you wanted under
    ///    a dozen near-identical rows. Rejected.
    /// 2. Add a `brand` field to `LoggedExercise`. Correct in the abstract, but every
    ///    history lookup in the app keys on the exercise id string, so each of those
    ///    call sites would have to learn about brands or it would silently average a
    ///    Hammer Strength row in with a Cybex row.
    /// 3. Qualify the id: `seated-machine-row@hammer-strength`. The catalog stays one
    ///    row per movement so search is unaffected, and because history is keyed by id,
    ///    two brands of the same machine keep separate weight histories for free. That
    ///    is exactly the property that matters, since 150 lb on two makers' stacks is
    ///    not the same load.
    ///
    /// Option 3 is what is implemented. An id with no suffix means "unbranded", which is
    /// what every already-logged set is, so nothing in existing history moves.
    static let brandSeparator: Character = "@"

    static func qualifiedID(base: String, brand: EquipmentBrand?) -> String {
        guard let brand else { return base }
        return "\(base)\(brandSeparator)\(brand.rawValue)"
    }

    static func components(of id: String) -> (base: String, brand: EquipmentBrand?) {
        guard let index = id.lastIndex(of: brandSeparator) else { return (id, nil) }
        let base = String(id[id.startIndex..<index])
        let slug = String(id[id.index(after: index)...])
        guard !base.isEmpty, let brand = EquipmentBrand(rawValue: slug) else { return (id, nil) }
        return (base, brand)
    }
}

enum WorkoutSetType: String, Codable, CaseIterable, Identifiable {
    case working
    case warmup
    case backoff

    var id: Self { self }

    var title: String {
        switch self {
        case .working: "Working"
        case .warmup: "Warm-up"
        case .backoff: "Backoff"
        }
    }

    var shortTitle: String {
        switch self {
        case .working: "Work"
        case .warmup: "Warm-up"
        case .backoff: "Backoff"
        }
    }

    /// Warm-ups prepare the movement but should not inflate hypertrophy dose,
    /// progression targets, or fatigue estimates. Backoff sets still count.
    var countsAsWorking: Bool { self != .warmup }
}

struct LoggedSet: Codable, Hashable, Identifiable {
    var id = UUID()
    var weight: Double?
    var reps: Int
    var isComplete: Bool
    /// Repetitions still possible with the same technique and range of motion.
    /// New sets default to zero because the current logging preference is failure.
    /// Nil remains unknown for older archives and must not be inferred as failure.
    var rir: Int? = 0
    /// The instant the set was checked off. This drives an elapsed rest clock,
    /// not a countdown, and remains nil for legacy completed sets.
    var completedAt: Date? = nil
    var setType: WorkoutSetType = .working

    var isPerformed: Bool {
        isComplete && reps > 0
    }

    var isWorkingSet: Bool {
        isPerformed && setType.countsAsWorking
    }

    /// Only the primary working load drives rep-then-load progression. Backoff
    /// work still contributes to hypertrophy dose and muscle coverage.
    var isProgressionSet: Bool {
        isPerformed && setType == .working
    }

    private enum CodingKeys: String, CodingKey {
        case id, weight, reps, isComplete, rir, completedAt, setType
    }

    init(
        id: UUID = UUID(),
        weight: Double?,
        reps: Int,
        isComplete: Bool,
        rir: Int? = 0,
        completedAt: Date? = nil,
        setType: WorkoutSetType = .working
    ) {
        self.id = id
        self.weight = weight
        self.reps = reps
        self.isComplete = isComplete
        self.rir = rir
        self.completedAt = completedAt
        self.setType = setType
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        weight = try container.decodeIfPresent(Double.self, forKey: .weight)
        reps = try container.decode(Int.self, forKey: .reps)
        isComplete = try container.decode(Bool.self, forKey: .isComplete)
        rir = try container.decodeIfPresent(Int.self, forKey: .rir)
        completedAt = try container.decodeIfPresent(Date.self, forKey: .completedAt)
        setType = try container.decodeIfPresent(WorkoutSetType.self, forKey: .setType) ?? .working
    }
}

struct LoggedExercise: Codable, Hashable, Identifiable {
    var id = UUID()
    let exerciseID: String
    var sets: [LoggedSet]

    /// The movement, ignoring which maker's version of it was used.
    var baseExerciseID: String { ExerciseDefinition.components(of: exerciseID).base }

    /// The maker of the machine this was logged on, if one was recorded.
    var brand: EquipmentBrand? { ExerciseDefinition.components(of: exerciseID).brand }

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
    /// Identifies the exact routine selected without changing the long-lived
    /// `WorkoutKind` values that are shared with history and coach sync.
    var routineID: String? = nil
    /// Freezes the routine as it existed when the workout began. Editing Upper A
    /// next month must not rename or reinterpret the workout done today.
    var routineSnapshot: HypertrophyTemplate? = nil
    let startedAt: Date
    var endedAt: Date?
    var exercises: [LoggedExercise]

    var completedSetCount: Int {
        exercises.flatMap(\.sets).filter(\.isWorkingSet).count
    }

    var performedSetCount: Int {
        exercises.flatMap(\.sets).filter(\.isPerformed).count
    }

    var lastCompletedSetAt: Date? {
        exercises.flatMap(\.sets).compactMap(\.completedAt).max()
    }
}

struct WeightEntry: Codable, Hashable, Identifiable {
    var id = UUID()
    let date: Date
    let pounds: Double
    let healthKitID: UUID?
    /// True only for a sample written by Today. Imported scale/manual samples
    /// must never be deleted when a local correction replaces the day.
    var healthKitOwnedByToday: Bool? = nil
    /// User-entered corrections win over later HealthKit refreshes for the same
    /// calendar day. External samples cannot be deleted by this app.
    var isUserEntered: Bool? = nil
}

struct StoredTodayData: Codable {
    static let defaultGoalWeight: Double = 175

    var weights: [WeightEntry] = []
    var workouts: [WorkoutSession] = []
    var activeWorkout: WorkoutSession?
    var goalWeight: Double = StoredTodayData.defaultGoalWeight
    var routines: [HypertrophyTemplate] = HypertrophyProgramming.templates
    /// IDs intentionally removed by the user. The remote archive needs these to
    /// distinguish a deletion from a workout omitted by a rolling export window.
    var deletedWorkoutIDs: [UUID] = []

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
        case routines
        case deletedWorkoutIDs
    }

    init(
        weights: [WeightEntry] = [],
        workouts: [WorkoutSession] = [],
        activeWorkout: WorkoutSession? = nil,
        goalWeight: Double = StoredTodayData.defaultGoalWeight,
        routines: [HypertrophyTemplate] = HypertrophyProgramming.templates,
        deletedWorkoutIDs: [UUID] = []
    ) {
        self.weights = weights
        self.workouts = workouts
        self.activeWorkout = activeWorkout
        self.goalWeight = goalWeight
        self.routines = routines
        self.deletedWorkoutIDs = deletedWorkoutIDs
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
        routines = (try? container.decode([HypertrophyTemplate].self, forKey: .routines))
            .map(Self.validatedRoutines) ?? HypertrophyProgramming.templates
        deletedWorkoutIDs = (try? container.decode([UUID].self, forKey: .deletedWorkoutIDs)) ?? []
        unreadableEntryCount = dropped
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(weights, forKey: .weights)
        try container.encode(workouts, forKey: .workouts)
        try container.encodeIfPresent(activeWorkout, forKey: .activeWorkout)
        try container.encode(goalWeight, forKey: .goalWeight)
        try container.encode(routines, forKey: .routines)
        try container.encode(deletedWorkoutIDs, forKey: .deletedWorkoutIDs)
    }

    private static func validatedRoutines(_ decoded: [HypertrophyTemplate]) -> [HypertrophyTemplate] {
        let supported = Set(HypertrophyProgramming.templates.map(\.id))
        let unique = Dictionary(decoded.filter { supported.contains($0.id) }.map { ($0.id, $0) }) { first, _ in first }
        return HypertrophyProgramming.templates.map { unique[$0.id] ?? $0 }
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
        // The lookbehind is load-bearing. With a plain `\b` the engine could
        // backtrack into the middle of a longer number and match a fragment of
        // it: "100.1 miles" matched the trailing "1" and returned 1.0, and
        // "120.5 miles" returned 5.0. That is worse than not parsing, because
        // the value looks reasonable and goes straight to the Watch as a
        // distance goal. Refusing to match makes it fail loudly instead.
        let pattern = #"(?i)(?<![\d.])(\d{1,2}(?:\.\d{1,2})?)\s*(?:mile|miles|mi)\b"#
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
