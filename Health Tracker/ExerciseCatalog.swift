import Combine
import Foundation

@MainActor
final class ExerciseCatalog: ObservableObject {
    static let shared = ExerciseCatalog()

    /// One row per movement. Brand-qualified variants are *not* in here: they are
    /// derived on demand by ``exercise(id:)`` so that picking a machine brand never
    /// multiplies the list you have to search through.
    @Published private(set) var exercises: [ExerciseDefinition] {
        didSet { rebuildIndex() }
    }
    @Published private(set) var isLoading = false

    private var byID: [String: ExerciseDefinition] = [:]

    private let cacheURL: URL
    private let session: URLSession
    private let sourceURL = URL(
        string: "https://raw.githubusercontent.com/yuhonas/free-exercise-db/main/dist/exercises.json"
    )!
    private let maximumDownloadBytes = 12_000_000
    /// How long a cached remote copy is trusted before another fetch is worth doing.
    private let cacheLifetime: TimeInterval = 30 * 24 * 60 * 60

    init(session: URLSession = .shared, cacheURL: URL? = nil) {
        self.session = session
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        self.cacheURL = cacheURL ?? base.appendingPathComponent("exercise-catalog.json")

        var merged = Self.seedExercises
        if let cached = try? Data(contentsOf: self.cacheURL),
           let remote = try? JSONDecoder().decode([RemoteExercise].self, from: cached) {
            merged = Self.merge(seed: merged, remote: remote)
        }
        exercises = merged.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        rebuildIndex()
    }

    /// The old guard was `exercises.count < 100`, which worked only because the bundled
    /// library was 21 entries: after one successful merge the count stayed above 100 and
    /// the app never refreshed again. The bundled library is now well past 100 on its
    /// own, so that guard would have meant "never fetch". Freshness is now what decides.
    func refreshIfNeeded() async {
        guard !isLoading, isCacheStale else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            var request = URLRequest(url: sourceURL)
            request.timeoutInterval = 15
            request.cachePolicy = .reloadRevalidatingCacheData
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return }
            guard data.count <= maximumDownloadBytes else { return }
            let remote = try JSONDecoder().decode([RemoteExercise].self, from: data)
            guard remote.count <= 5_000 else { return }
            try? data.write(to: cacheURL, options: .atomic)
            exercises = Self.merge(seed: Self.seedExercises, remote: remote)
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        } catch {
            // The bundled library always remains available offline.
        }
    }

    private var isCacheStale: Bool {
        guard let modified = try? FileManager.default
            .attributesOfItem(atPath: cacheURL.path)[.modificationDate] as? Date else {
            return true
        }
        return Date().timeIntervalSince(modified) > cacheLifetime
    }

    /// Resolves both plain ids and brand-qualified ones (`lat-pulldown@cybex`).
    ///
    /// Derivation is deliberately permissive: if an id was ever logged with a brand it
    /// keeps resolving even if that movement later stops offering brands, because the
    /// alternative is orphaning real history.
    func exercise(id: String) -> ExerciseDefinition? {
        if let match = byID[id] { return match }
        let parts = ExerciseDefinition.components(of: id)
        guard let brand = parts.brand, let base = byID[parts.base] else { return nil }
        return Self.branded(base, brand: brand)
    }

    /// The makers worth offering for a movement, or an empty list when the brand would
    /// be decoration. A 50 lb dumbbell is 50 lb whoever cast it, so free-weight and
    /// bodyweight movements deliberately offer nothing.
    func brands(for exerciseID: String) -> [EquipmentBrand] {
        let base = ExerciseDefinition.components(of: exerciseID).base
        guard let definition = byID[base], definition.acceptsBrand else { return [] }
        return EquipmentBrand.allCases
            .filter { $0.manufactures.contains(definition.equipmentClass) }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    /// The id to log a set under once a brand has been chosen. Passing nil returns the
    /// plain id, which is what every set logged before brands existed already uses.
    func qualifiedID(for exerciseID: String, brand: EquipmentBrand?) -> String {
        let base = ExerciseDefinition.components(of: exerciseID).base
        guard let brand, let definition = byID[base], definition.acceptsBrand else { return base }
        return ExerciseDefinition.qualifiedID(base: base, brand: brand)
    }

    private static func branded(_ base: ExerciseDefinition, brand: EquipmentBrand) -> ExerciseDefinition {
        ExerciseDefinition(
            id: ExerciseDefinition.qualifiedID(base: base.id, brand: brand),
            // The brand goes in the name only on this derived instance, so history and
            // the workout log read "Lat pulldown (Cybex)" without the searchable catalog
            // ever growing a row per maker.
            name: "\(base.name) (\(brand.title))",
            aliases: base.aliases,
            equipment: base.equipment,
            loadMode: base.loadMode,
            weightIncrement: base.weightIncrement,
            muscles: base.muscles,
            equipmentClass: base.equipmentClass,
            brand: brand,
            isBrandSignature: base.isBrandSignature
        )
    }

    private func rebuildIndex() {
        byID = Dictionary(exercises.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    func search(_ query: String) -> [ExerciseDefinition] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return Array(exercises.prefix(80)) }
        let tokens = trimmed.split(separator: " ").map(String.init)
        return exercises
            .filter { exercise in tokens.allSatisfy { exercise.searchText.contains($0) } }
            .map { ($0, Self.relevance($0, query: trimmed, tokens: tokens)) }
            .sorted { lhs, rhs in
                if lhs.1 != rhs.1 { return lhs.1 > rhs.1 }
                return lhs.0.name.localizedStandardCompare(rhs.0.name) == .orderedAscending
            }
            .map(\.0)
    }

    /// Ranking exists so that typing a generic movement surfaces the generic movement.
    /// A maker-specific machine is a specialisation, so it sorts below the plain version
    /// of the same lift, and imported rows sort below curated ones.
    private static func relevance(
        _ exercise: ExerciseDefinition,
        query: String,
        tokens: [String]
    ) -> Int {
        let name = exercise.name.lowercased()
        let aliases = exercise.aliases.map { $0.lowercased() }
        var score: Int
        if name == query {
            score = 100
        } else if name.hasPrefix(query) {
            score = 80
        } else if aliases.contains(query) {
            score = 70
        } else if aliases.contains(where: { $0.hasPrefix(query) }) {
            score = 60
        } else if name.contains(query) {
            score = 50
        } else if tokens.allSatisfy({ name.contains($0) }) {
            score = 40
        } else {
            score = 20
        }
        if exercise.isBrandSignature { score -= 25 }
        if isImported(exercise) { score -= 5 }
        return score
    }

    static func isImported(_ exercise: ExerciseDefinition) -> Bool {
        exercise.id.hasPrefix(importedIDPrefix)
    }

    private static let importedIDPrefix = "free-exercise-db:"

    func defaultExerciseIDs(for kind: WorkoutKind) -> [String] {
        switch kind {
        case .upper:
            [
                "machine-chest-fly",
                "lat-pulldown",
                "seated-machine-row",
                "incline-machine-chest-press",
                "neutral-grip-machine-shoulder-press",
                "rope-triceps-pushdown",
                "incline-dumbbell-curl",
                "single-arm-cable-lateral-raise"
            ]
        case .lower:
            [
                "seated-leg-extension",
                "seated-leg-curl",
                "hip-adductor-machine",
                "hip-abductor-machine",
                "calf-raise",
                "kneeling-rope-cable-crunch",
                "crunch"
            ]
        case .push:
            [
                "machine-chest-fly",
                "incline-machine-chest-press",
                "neutral-grip-machine-shoulder-press",
                "rope-triceps-pushdown",
                "single-arm-cable-lateral-raise"
            ]
        case .pull:
            [
                "lat-pulldown",
                "seated-machine-row",
                "incline-dumbbell-curl"
            ]
        case .legs:
            [
                "seated-leg-extension",
                "seated-leg-curl",
                "hip-adductor-machine",
                "hip-abductor-machine",
                "calf-raise",
                "kneeling-rope-cable-crunch",
                "crunch"
            ]
        case .chest:
            [
                "machine-chest-fly",
                "incline-machine-chest-press"
            ]
        case .back:
            [
                "lat-pulldown",
                "seated-machine-row"
            ]
        case .other:
            []
        }
    }

    func defaultSets(for exerciseID: String) -> [LoggedSet] {
        let values: (Double?, Int)
        switch ExerciseDefinition.components(of: exerciseID).base {
        case "machine-chest-fly": values = (235, 5)
        case "pull-up": values = (nil, 6)
        case "crunch": values = (nil, 12)
        default: values = (nil, 8)
        }
        return [
            LoggedSet(weight: values.0, reps: values.1, isComplete: false),
            LoggedSet(weight: values.0, reps: values.1, isComplete: false)
        ]
    }

    private static func merge(seed: [ExerciseDefinition], remote: [RemoteExercise]) -> [ExerciseDefinition] {
        var merged = seed
        // Dedupe on names *and* aliases, ignoring punctuation, so the import does not
        // add "Pullups" next to the curated "Pull-up" and turn search into a list of
        // near-identical rows.
        var taken = Set<String>()
        for exercise in seed {
            taken.insert(normalizedKey(exercise.name))
            for alias in exercise.aliases { taken.insert(normalizedKey(alias)) }
        }
        for item in remote where item.category != "cardio" && item.category != "stretching" {
            let key = normalizedKey(item.name)
            guard !key.isEmpty, taken.insert(key).inserted else { continue }
            merged.append(
                ExerciseDefinition(
                    id: "\(importedIDPrefix)\(item.id)",
                    name: item.name,
                    aliases: [],
                    equipment: item.equipment ?? "other",
                    loadMode: loadMode(for: item),
                    weightIncrement: 5,
                    muscles: detailedFallback(primary: item.primaryMuscles, secondary: item.secondaryMuscles),
                    equipmentClass: equipmentClass(for: item)
                )
            )
        }
        return merged
    }

    /// Punctuation-free and plural-free, so "Pull-up", "Pull Up", and "Pullups" are all
    /// recognised as the one exercise already in the library.
    private static func normalizedKey(_ value: String) -> String {
        let stripped = value.lowercased().filter { $0.isLetter || $0.isNumber }
        return stripped.hasSuffix("s") ? String(stripped.dropLast()) : stripped
    }

    private static func loadMode(for item: RemoteExercise) -> ExerciseLoadMode {
        if item.equipment == "body only" { return .bodyweight }
        if item.equipment == "dumbbell" { return .perHand }
        return .total
    }

    /// Imported rows only say "machine", never whether the machine is pin-loaded or
    /// plate-loaded, so `machine` is read as selectorized. That is the common case in a
    /// commercial gym and it still gives the row a usable brand list; a curated seed is
    /// the fix when a specific plate-loaded machine matters.
    private static func equipmentClass(for item: RemoteExercise) -> EquipmentClass {
        switch item.equipment {
        case "barbell": .barbell
        case "dumbbell": .dumbbell
        case "cable": .cable
        case "machine": .selectorized
        case "body only": .bodyweight
        case "e-z curl bar": .barbell
        default: .other
        }
    }

    static func detailedFallback(primary: [String], secondary: [String]) -> [MuscleContribution] {
        var values: [MuscleGroup: Double] = [:]
        for name in primary {
            for muscle in mappedMuscles(name) { values[muscle, default: 0] = max(values[muscle] ?? 0, 1) }
        }
        let backMuscles: Set<MuscleGroup> = [
            .lats, .rhomboids, .upperTraps, .middleTraps, .lowerTraps, .lowerBack,
        ]
        let isStrappedPull = !backMuscles.isDisjoint(with: values.keys)
        for name in secondary {
            for muscle in mappedMuscles(name) where !(isStrappedPull && muscle == .forearms) {
                values[muscle, default: 0] = max(values[muscle] ?? 0, 0.45)
            }
        }
        return values.map(MuscleContribution.init).sorted { $0.muscle.rawValue < $1.muscle.rawValue }
    }

    private static func mappedMuscles(_ raw: String) -> [MuscleGroup] {
        switch raw.lowercased() {
        case "abdominals": [.rectusAbdominis, .obliques]
        case "abductors": [.abductors, .gluteMed]
        case "adductors": [.adductors]
        case "biceps": [.bicepsLongHead, .bicepsShortHead, .brachialis]
        case "calves": [.gastrocnemius, .soleus]
        case "chest": [.upperChest, .middleChest, .lowerChest]
        case "forearms": [.forearms]
        case "glutes": [.gluteMax, .gluteMed]
        case "hamstrings": [.hamstrings]
        case "lats": [.lats]
        case "lower back": [.lowerBack]
        case "middle back": [.rhomboids, .middleTraps, .lowerTraps]
        case "quadriceps": [.rectusFemoris, .vastusLateralis, .vastusMedialis]
        case "shoulders": [.frontDelts, .sideDelts, .rearDelts]
        case "traps": [.upperTraps, .middleTraps, .lowerTraps]
        case "triceps": [.tricepsLongHead, .tricepsLateralHead, .tricepsMedialHead]
        default: []
        }
    }
}

private struct RemoteExercise: Decodable {
    let id: String
    let name: String
    let equipment: String?
    let primaryMuscles: [String]
    let secondaryMuscles: [String]
    let category: String
}
