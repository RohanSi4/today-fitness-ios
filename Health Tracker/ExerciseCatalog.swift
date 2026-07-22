import Combine
import Foundation

@MainActor
final class ExerciseCatalog: ObservableObject {
    static let shared = ExerciseCatalog()

    @Published private(set) var exercises: [ExerciseDefinition]
    @Published private(set) var isLoading = false

    private let cacheURL: URL
    private let session: URLSession
    private let sourceURL = URL(
        string: "https://raw.githubusercontent.com/yuhonas/free-exercise-db/main/dist/exercises.json"
    )!
    private let maximumDownloadBytes = 12_000_000

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
    }

    func refreshIfNeeded() async {
        guard exercises.count < 100, !isLoading else { return }
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
            // The personal seed library always remains available offline.
        }
    }

    func exercise(id: String) -> ExerciseDefinition? {
        exercises.first { $0.id == id }
    }

    func search(_ query: String) -> [ExerciseDefinition] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return Array(exercises.prefix(80)) }
        let tokens = trimmed.split(separator: " ").map(String.init)
        return exercises
            .filter { exercise in tokens.allSatisfy { exercise.searchText.contains($0) } }
            .sorted { lhs, rhs in
                let leftExact = lhs.name.lowercased().hasPrefix(trimmed)
                let rightExact = rhs.name.lowercased().hasPrefix(trimmed)
                if leftExact != rightExact { return leftExact }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
    }

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
        switch exerciseID {
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
        var byName = Dictionary(uniqueKeysWithValues: seed.map { ($0.name.lowercased(), $0) })
        for item in remote where item.category != "cardio" && item.category != "stretching" {
            let key = item.name.lowercased()
            guard byName[key] == nil else { continue }
            let id = "free-exercise-db:\(item.id)"
            byName[key] = ExerciseDefinition(
                id: id,
                name: item.name,
                aliases: [],
                equipment: item.equipment ?? "other",
                loadMode: loadMode(for: item),
                weightIncrement: 5,
                muscles: detailedFallback(primary: item.primaryMuscles, secondary: item.secondaryMuscles)
            )
        }
        return Array(byName.values)
    }

    private static func loadMode(for item: RemoteExercise) -> ExerciseLoadMode {
        if item.equipment == "body only" { return .bodyweight }
        if item.equipment == "dumbbell" { return .perHand }
        return .total
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

private extension ExerciseCatalog {
    static let seedExercises: [ExerciseDefinition] = [
        exercise(
            "machine-chest-fly", "Machine chest fly", ["pec deck", "machine fly"], "machine", .total,
            [.middleChest: 1, .upperChest: 0.55, .lowerChest: 0.45, .frontDelts: 0.3]
        ),
        exercise(
            "lat-pulldown", "Lat pulldown", ["pulldown"], "cable", .total,
            [.lats: 1, .bicepsLongHead: 0.55, .bicepsShortHead: 0.5, .brachialis: 0.45, .lowerTraps: 0.45, .rhomboids: 0.4]
        ),
        exercise(
            "pull-up", "Pull-up", ["pullup", "pull up"], "bodyweight", .addedWeight,
            [.lats: 1, .bicepsLongHead: 0.6, .bicepsShortHead: 0.5, .brachialis: 0.5, .lowerTraps: 0.45, .rhomboids: 0.4]
        ),
        exercise(
            "seated-machine-row", "Seated machine row", ["mid chest row", "machine row", "mid back row"], "machine", .total,
            [.rhomboids: 1, .middleTraps: 0.9, .lats: 0.65, .rearDelts: 0.6, .bicepsLongHead: 0.45, .bicepsShortHead: 0.45]
        ),
        exercise(
            "incline-machine-chest-press", "Incline machine chest press", ["upper chest machine push", "upper chest press"], "machine", .total,
            [.upperChest: 1, .middleChest: 0.55, .frontDelts: 0.7, .tricepsLateralHead: 0.5, .tricepsLongHead: 0.35]
        ),
        exercise(
            "neutral-grip-machine-shoulder-press", "Neutral-grip machine shoulder press", ["shoulder press other grip"], "machine", .total,
            [.frontDelts: 1, .sideDelts: 0.75, .tricepsLateralHead: 0.55, .tricepsLongHead: 0.4, .upperChest: 0.25]
        ),
        exercise(
            "rope-triceps-pushdown", "Rope triceps pushdown", ["rope pushdown"], "cable", .total,
            [.tricepsLateralHead: 1, .tricepsMedialHead: 0.85, .tricepsLongHead: 0.55]
        ),
        exercise(
            "straight-bar-triceps-pushdown", "Straight-bar triceps pushdown", ["flat bar pushdown", "bar pushdown"], "cable", .total,
            [.tricepsLateralHead: 1, .tricepsMedialHead: 0.85, .tricepsLongHead: 0.5]
        ),
        exercise(
            "incline-dumbbell-curl", "Incline dumbbell curl", ["incline bench curl"], "dumbbells", .perHand,
            [.bicepsLongHead: 1, .bicepsShortHead: 0.65, .brachialis: 0.5, .forearms: 0.25]
        ),
        exercise(
            "dumbbell-wrist-curl", "Dumbbell wrist curl", ["wrist curl", "forearm curl"], "dumbbells", .perHand,
            [.forearms: 1]
        ),
        exercise(
            "reverse-dumbbell-wrist-curl", "Reverse dumbbell wrist curl", ["reverse wrist curl"], "dumbbells", .perHand,
            [.forearms: 1]
        ),
        exercise(
            "single-arm-cable-lateral-raise", "Single-arm cable lateral raise", ["shoulder cable single arm raise"], "cable", .total,
            [.sideDelts: 1, .frontDelts: 0.25, .upperTraps: 0.25]
        ),
        exercise(
            "seated-leg-extension", "Seated leg extension", ["leg extension"], "machine", .total,
            [.rectusFemoris: 1, .vastusLateralis: 0.95, .vastusMedialis: 0.95]
        ),
        exercise(
            "seated-leg-curl", "Seated leg curl", ["seated hamstring curl"], "machine", .total,
            [.hamstrings: 1, .gastrocnemius: 0.2]
        ),
        exercise(
            "lying-leg-curl", "Lying leg curl", ["laying leg curl", "prone leg curl"], "machine", .total,
            [.hamstrings: 1, .gastrocnemius: 0.25]
        ),
        exercise(
            "hip-adductor-machine", "Hip adductor machine", ["adductor"], "machine", .total,
            [.adductors: 1]
        ),
        exercise(
            "hip-abductor-machine", "Hip abductor machine", ["abductor"], "machine", .total,
            [.abductors: 1, .gluteMed: 0.85]
        ),
        exercise(
            "calf-raise", "Calf raise", ["calf raises"], "machine", .total,
            [.gastrocnemius: 1, .soleus: 0.75]
        ),
        exercise(
            "plate-loaded-squat", "Plate-loaded squat", ["machine squat", "hack squat"], "plate-loaded machine", .total,
            [.rectusFemoris: 0.85, .vastusLateralis: 1, .vastusMedialis: 0.9, .gluteMax: 0.8, .adductors: 0.35, .hamstrings: 0.3]
        ),
        exercise(
            "kneeling-rope-cable-crunch", "Kneeling rope cable crunch", ["cable kneeling crunch", "rope crunch"], "cable", .total,
            [.rectusAbdominis: 1, .obliques: 0.35]
        ),
        exercise(
            "crunch", "Crunch", ["crunches"], "bodyweight", .bodyweight,
            [.rectusAbdominis: 1, .obliques: 0.25]
        )
    ]

    static func exercise(
        _ id: String,
        _ name: String,
        _ aliases: [String],
        _ equipment: String,
        _ loadMode: ExerciseLoadMode,
        _ muscles: [MuscleGroup: Double]
    ) -> ExerciseDefinition {
        ExerciseDefinition(
            id: id,
            name: name,
            aliases: aliases,
            equipment: equipment,
            loadMode: loadMode,
            weightIncrement: 5,
            muscles: muscles.map(MuscleContribution.init).sorted { $0.muscle.rawValue < $1.muscle.rawValue }
        )
    }
}
