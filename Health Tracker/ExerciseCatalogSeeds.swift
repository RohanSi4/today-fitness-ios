import Foundation

// The bundled exercise library.
//
// Everything here ships in the binary, so the catalog is complete with no network. The
// remote free-exercise-db merge only ever *adds* rows that are not already covered here
// (see `ExerciseCatalog.merge`), and its generic `arms` / `back` muscle labels never
// overwrite the per-head mapping below.
//
// Two rules govern this file:
//
// 1. An id is permanent. Logged history is keyed by it. Rename freely, delete never.
// 2. Anything a person loads heavy gets a real per-head muscle map. `triceps` is not a
//    muscle as far as the anatomy view is concerned; the long, lateral, and medial heads
//    are. Intensity is relative to the hardest-worked muscle in that movement, which is
//    always 1.0, and secondary work is a fraction of it.
//
// Grip convention: pulling movements do not list `forearms`. He straps in for heavy back
// work, so crediting forearms on every row would light up the anatomy view for work that
// is not actually happening. Forearms appear on direct forearm work, on curls, and on
// carries.

extension ExerciseCatalog {
    /// Every exercise available with no network connection.
    static let seedExercises: [ExerciseDefinition] =
        originalCuratedSeeds
        + chestSeeds
        + backSeeds
        + shoulderSeeds
        + armSeeds
        + legSeeds
        + coreSeeds
        + brandSignatureSeeds

    static func seed(
        _ id: String,
        _ name: String,
        _ aliases: [String],
        _ equipment: String,
        _ equipmentClass: EquipmentClass,
        _ loadMode: ExerciseLoadMode,
        _ muscles: [MuscleGroup: Double],
        brand: EquipmentBrand? = nil,
        signature: Bool = false
    ) -> ExerciseDefinition {
        ExerciseDefinition(
            id: id,
            name: name,
            aliases: aliases,
            equipment: equipment,
            loadMode: loadMode,
            weightIncrement: 5,
            muscles: muscles.map(MuscleContribution.init).sorted { $0.muscle.rawValue < $1.muscle.rawValue },
            equipmentClass: equipmentClass,
            brand: brand,
            isBrandSignature: signature
        )
    }
}

// MARK: - The original hand-tuned library

extension ExerciseCatalog {
    /// The first 21 exercises, kept verbatim. These ids appear throughout real logged
    /// history and in `defaultExerciseIDs`, and their muscle maps were tuned by hand.
    /// Only the equipment class is new.
    static let originalCuratedSeeds: [ExerciseDefinition] = [
        seed(
            "machine-chest-fly", "Machine chest fly", ["pec deck", "machine fly"], "machine", .selectorized, .total,
            [.middleChest: 1, .upperChest: 0.55, .lowerChest: 0.45, .frontDelts: 0.3]
        ),
        seed(
            "lat-pulldown", "Lat pulldown", ["pulldown"], "cable", .cable, .total,
            [.lats: 1, .bicepsLongHead: 0.55, .bicepsShortHead: 0.5, .brachialis: 0.45, .lowerTraps: 0.45, .rhomboids: 0.4]
        ),
        seed(
            "pull-up", "Pull-up", ["pullup", "pull up"], "bodyweight", .bodyweight, .addedWeight,
            [.lats: 1, .bicepsLongHead: 0.6, .bicepsShortHead: 0.5, .brachialis: 0.5, .lowerTraps: 0.45, .rhomboids: 0.4]
        ),
        seed(
            "seated-machine-row", "Seated machine row", ["mid chest row", "machine row", "mid back row"], "machine", .selectorized, .total,
            [.rhomboids: 1, .middleTraps: 0.9, .lats: 0.65, .rearDelts: 0.6, .bicepsLongHead: 0.45, .bicepsShortHead: 0.45]
        ),
        seed(
            "incline-machine-chest-press", "Incline machine chest press", ["upper chest machine push", "upper chest press"], "machine", .selectorized, .total,
            [.upperChest: 1, .middleChest: 0.55, .frontDelts: 0.7, .tricepsLateralHead: 0.5, .tricepsLongHead: 0.35]
        ),
        seed(
            "neutral-grip-machine-shoulder-press", "Neutral-grip machine shoulder press", ["shoulder press other grip"], "machine", .selectorized, .total,
            [.frontDelts: 1, .sideDelts: 0.75, .tricepsLateralHead: 0.55, .tricepsLongHead: 0.4, .upperChest: 0.25]
        ),
        seed(
            "rope-triceps-pushdown", "Rope triceps pushdown", ["rope pushdown"], "cable", .cable, .total,
            [.tricepsLateralHead: 1, .tricepsMedialHead: 0.85, .tricepsLongHead: 0.55]
        ),
        seed(
            "straight-bar-triceps-pushdown", "Straight-bar triceps pushdown", ["flat bar pushdown", "bar pushdown"], "cable", .cable, .total,
            [.tricepsLateralHead: 1, .tricepsMedialHead: 0.85, .tricepsLongHead: 0.5]
        ),
        seed(
            "incline-dumbbell-curl", "Incline dumbbell curl", ["incline bench curl"], "dumbbells", .dumbbell, .perHand,
            [.bicepsLongHead: 1, .bicepsShortHead: 0.65, .brachialis: 0.5, .forearms: 0.25]
        ),
        seed(
            "dumbbell-wrist-curl", "Dumbbell wrist curl", ["wrist curl", "forearm curl"], "dumbbells", .dumbbell, .perHand,
            [.forearms: 1]
        ),
        seed(
            "reverse-dumbbell-wrist-curl", "Reverse dumbbell wrist curl", ["reverse wrist curl"], "dumbbells", .dumbbell, .perHand,
            [.forearms: 1]
        ),
        seed(
            "single-arm-cable-lateral-raise", "Single-arm cable lateral raise", ["shoulder cable single arm raise"], "cable", .cable, .total,
            [.sideDelts: 1, .frontDelts: 0.25, .upperTraps: 0.25]
        ),
        seed(
            "seated-leg-extension", "Seated leg extension", ["leg extension"], "machine", .selectorized, .total,
            [.rectusFemoris: 1, .vastusLateralis: 0.95, .vastusMedialis: 0.95]
        ),
        seed(
            "seated-leg-curl", "Seated leg curl", ["seated hamstring curl"], "machine", .selectorized, .total,
            [.hamstrings: 1, .gastrocnemius: 0.2]
        ),
        seed(
            "lying-leg-curl", "Lying leg curl", ["laying leg curl", "prone leg curl"], "machine", .selectorized, .total,
            [.hamstrings: 1, .gastrocnemius: 0.25]
        ),
        seed(
            "hip-adductor-machine", "Hip adductor machine", ["adductor"], "machine", .selectorized, .total,
            [.adductors: 1]
        ),
        seed(
            "hip-abductor-machine", "Hip abductor machine", ["abductor"], "machine", .selectorized, .total,
            [.abductors: 1, .gluteMed: 0.85]
        ),
        seed(
            "calf-raise", "Calf raise", ["calf raises"], "machine", .selectorized, .total,
            [.gastrocnemius: 1, .soleus: 0.75]
        ),
        seed(
            "plate-loaded-squat", "Plate-loaded squat", ["machine squat", "hack squat"], "plate-loaded machine", .plateLoaded, .total,
            [.rectusFemoris: 0.85, .vastusLateralis: 1, .vastusMedialis: 0.9, .gluteMax: 0.8, .adductors: 0.35, .hamstrings: 0.3]
        ),
        seed(
            "kneeling-rope-cable-crunch", "Kneeling rope cable crunch", ["cable kneeling crunch", "rope crunch"], "cable", .cable, .total,
            [.rectusAbdominis: 1, .obliques: 0.35]
        ),
        seed(
            "crunch", "Crunch", ["crunches"], "bodyweight", .bodyweight, .bodyweight,
            [.rectusAbdominis: 1, .obliques: 0.25]
        ),
    ]
}

// MARK: - Chest

extension ExerciseCatalog {
    static let chestSeeds: [ExerciseDefinition] = [
        seed(
            "machine-chest-press", "Machine chest press", ["seated chest press", "converging chest press"], "machine", .selectorized, .total,
            [.middleChest: 1, .lowerChest: 0.5, .upperChest: 0.4, .frontDelts: 0.55, .tricepsLateralHead: 0.5, .tricepsLongHead: 0.35]
        ),
        seed(
            "decline-machine-chest-press", "Decline machine chest press", ["decline chest press machine"], "machine", .selectorized, .total,
            [.lowerChest: 1, .middleChest: 0.7, .tricepsLateralHead: 0.5, .tricepsLongHead: 0.35, .frontDelts: 0.25]
        ),
        seed(
            "plate-loaded-chest-press", "Plate-loaded chest press", ["lever chest press"], "plate-loaded machine", .plateLoaded, .total,
            [.middleChest: 1, .lowerChest: 0.5, .upperChest: 0.4, .frontDelts: 0.55, .tricepsLateralHead: 0.5, .tricepsLongHead: 0.35]
        ),
        seed(
            "plate-loaded-incline-press", "Plate-loaded incline press", ["lever incline press"], "plate-loaded machine", .plateLoaded, .total,
            [.upperChest: 1, .middleChest: 0.55, .frontDelts: 0.7, .tricepsLateralHead: 0.5, .tricepsLongHead: 0.35]
        ),
        seed(
            "cable-chest-press", "Cable chest press", ["standing cable press"], "cable", .cable, .total,
            [.middleChest: 1, .upperChest: 0.4, .frontDelts: 0.5, .tricepsLateralHead: 0.45, .rectusAbdominis: 0.25]
        ),
        seed(
            "barbell-bench-press", "Barbell bench press", ["flat bench", "bench press"], "barbell", .barbell, .total,
            [.middleChest: 1, .lowerChest: 0.6, .upperChest: 0.45, .frontDelts: 0.6, .tricepsLateralHead: 0.6, .tricepsLongHead: 0.4, .tricepsMedialHead: 0.4]
        ),
        seed(
            "incline-barbell-bench-press", "Incline barbell bench press", ["incline bench press"], "barbell", .barbell, .total,
            [.upperChest: 1, .middleChest: 0.55, .frontDelts: 0.75, .tricepsLateralHead: 0.55, .tricepsLongHead: 0.4]
        ),
        seed(
            "decline-barbell-bench-press", "Decline barbell bench press", ["decline bench press"], "barbell", .barbell, .total,
            [.lowerChest: 1, .middleChest: 0.7, .tricepsLateralHead: 0.55, .tricepsLongHead: 0.4, .frontDelts: 0.3]
        ),
        seed(
            "close-grip-bench-press", "Close-grip bench press", ["narrow grip bench"], "barbell", .barbell, .total,
            [.tricepsLateralHead: 1, .tricepsMedialHead: 0.85, .tricepsLongHead: 0.75, .middleChest: 0.6, .frontDelts: 0.4]
        ),
        seed(
            "barbell-floor-press", "Barbell floor press", ["floor press"], "barbell", .barbell, .total,
            [.middleChest: 0.9, .tricepsLateralHead: 1, .tricepsMedialHead: 0.7, .tricepsLongHead: 0.6, .frontDelts: 0.45]
        ),
        seed(
            "smith-machine-bench-press", "Smith machine bench press", ["smith bench"], "smith machine", .smith, .total,
            [.middleChest: 1, .lowerChest: 0.55, .upperChest: 0.4, .frontDelts: 0.55, .tricepsLateralHead: 0.55, .tricepsLongHead: 0.35]
        ),
        seed(
            "smith-machine-incline-press", "Smith machine incline press", ["smith incline bench"], "smith machine", .smith, .total,
            [.upperChest: 1, .middleChest: 0.55, .frontDelts: 0.7, .tricepsLateralHead: 0.5, .tricepsLongHead: 0.35]
        ),
        seed(
            "dumbbell-bench-press", "Dumbbell bench press", ["flat dumbbell press", "db bench"], "dumbbells", .dumbbell, .perHand,
            [.middleChest: 1, .lowerChest: 0.55, .upperChest: 0.45, .frontDelts: 0.55, .tricepsLateralHead: 0.5, .tricepsLongHead: 0.35]
        ),
        seed(
            "incline-dumbbell-bench-press", "Incline dumbbell bench press", ["incline dumbbell press"], "dumbbells", .dumbbell, .perHand,
            [.upperChest: 1, .middleChest: 0.55, .frontDelts: 0.7, .tricepsLateralHead: 0.45, .tricepsLongHead: 0.3]
        ),
        seed(
            "decline-dumbbell-bench-press", "Decline dumbbell bench press", ["decline dumbbell press"], "dumbbells", .dumbbell, .perHand,
            [.lowerChest: 1, .middleChest: 0.7, .tricepsLateralHead: 0.5, .tricepsLongHead: 0.3]
        ),
        seed(
            "dumbbell-fly", "Dumbbell fly", ["flat dumbbell fly", "chest fly"], "dumbbells", .dumbbell, .perHand,
            [.middleChest: 1, .lowerChest: 0.45, .upperChest: 0.4, .frontDelts: 0.35]
        ),
        seed(
            "incline-dumbbell-fly", "Incline dumbbell fly", ["incline fly"], "dumbbells", .dumbbell, .perHand,
            [.upperChest: 1, .middleChest: 0.5, .frontDelts: 0.4]
        ),
        seed(
            "high-to-low-cable-fly", "High-to-low cable fly", ["high cable crossover", "downward cable fly"], "cable", .cable, .total,
            [.lowerChest: 1, .middleChest: 0.75, .frontDelts: 0.2]
        ),
        seed(
            "mid-cable-fly", "Mid cable fly", ["cable crossover", "cable fly"], "cable", .cable, .total,
            [.middleChest: 1, .lowerChest: 0.5, .upperChest: 0.45, .frontDelts: 0.3]
        ),
        seed(
            "low-to-high-cable-fly", "Low-to-high cable fly", ["upward cable fly", "low cable crossover"], "cable", .cable, .total,
            [.upperChest: 1, .middleChest: 0.6, .frontDelts: 0.4]
        ),
        seed(
            "single-arm-cable-fly", "Single-arm cable fly", ["one arm cable crossover"], "cable", .cable, .total,
            [.middleChest: 1, .upperChest: 0.45, .lowerChest: 0.45, .frontDelts: 0.3, .obliques: 0.2]
        ),
        seed(
            "chest-dip", "Chest dip", ["dip", "dips", "parallel bar dip"], "bodyweight", .bodyweight, .addedWeight,
            [.lowerChest: 1, .middleChest: 0.7, .tricepsLateralHead: 0.8, .tricepsLongHead: 0.6, .tricepsMedialHead: 0.6, .frontDelts: 0.5]
        ),
        seed(
            "assisted-dip-machine", "Assisted dip machine", ["assisted dips"], "machine", .selectorized, .total,
            [.lowerChest: 1, .middleChest: 0.7, .tricepsLateralHead: 0.8, .tricepsLongHead: 0.55, .frontDelts: 0.45]
        ),
        seed(
            "machine-dip", "Machine dip", ["seated dip machine", "seated dip"], "machine", .selectorized, .total,
            [.tricepsLateralHead: 1, .tricepsMedialHead: 0.8, .tricepsLongHead: 0.7, .lowerChest: 0.6, .frontDelts: 0.3]
        ),
        seed(
            "push-up", "Push-up", ["pushup", "press up"], "bodyweight", .bodyweight, .addedWeight,
            [.middleChest: 1, .lowerChest: 0.5, .upperChest: 0.4, .frontDelts: 0.5, .tricepsLateralHead: 0.6, .tricepsLongHead: 0.35, .rectusAbdominis: 0.3]
        ),
        seed(
            "incline-push-up", "Incline push-up", ["hands elevated push up"], "bodyweight", .bodyweight, .addedWeight,
            [.lowerChest: 0.8, .middleChest: 1, .frontDelts: 0.35, .tricepsLateralHead: 0.5, .rectusAbdominis: 0.25]
        ),
        seed(
            "decline-push-up", "Decline push-up", ["feet elevated push up"], "bodyweight", .bodyweight, .addedWeight,
            [.upperChest: 1, .middleChest: 0.7, .frontDelts: 0.6, .tricepsLateralHead: 0.5, .rectusAbdominis: 0.35]
        ),
        seed(
            "landmine-press", "Landmine press", ["landmine chest press"], "barbell", .barbell, .total,
            [.upperChest: 1, .frontDelts: 0.9, .middleChest: 0.5, .tricepsLateralHead: 0.45, .rectusAbdominis: 0.3, .obliques: 0.3]
        ),
        seed(
            "machine-pec-fly-rear-delt", "Pec fly / rear delt machine", ["fly rear delt", "dual pec deck"], "machine", .selectorized, .total,
            [.middleChest: 1, .upperChest: 0.5, .lowerChest: 0.4, .frontDelts: 0.3]
        ),
    ]
}

// MARK: - Back

extension ExerciseCatalog {
    static let backSeeds: [ExerciseDefinition] = [
        seed(
            "wide-grip-lat-pulldown", "Wide-grip lat pulldown", ["wide pulldown"], "cable", .cable, .total,
            [.lats: 1, .lowerTraps: 0.5, .rhomboids: 0.45, .rearDelts: 0.4, .bicepsLongHead: 0.4, .bicepsShortHead: 0.35, .brachialis: 0.35]
        ),
        seed(
            "close-grip-lat-pulldown", "Close-grip lat pulldown", ["v handle pulldown", "narrow pulldown"], "cable", .cable, .total,
            [.lats: 1, .bicepsLongHead: 0.6, .bicepsShortHead: 0.55, .brachialis: 0.5, .rhomboids: 0.45, .lowerTraps: 0.4]
        ),
        seed(
            "neutral-grip-lat-pulldown", "Neutral-grip lat pulldown", ["parallel grip pulldown"], "cable", .cable, .total,
            [.lats: 1, .brachialis: 0.6, .bicepsLongHead: 0.55, .bicepsShortHead: 0.45, .lowerTraps: 0.45, .rhomboids: 0.4]
        ),
        seed(
            "reverse-grip-lat-pulldown", "Reverse-grip lat pulldown", ["underhand pulldown", "supinated pulldown"], "cable", .cable, .total,
            [.lats: 1, .bicepsLongHead: 0.7, .bicepsShortHead: 0.65, .brachialis: 0.45, .lowerTraps: 0.4, .rhomboids: 0.35]
        ),
        seed(
            "single-arm-lat-pulldown", "Single-arm lat pulldown", ["one arm pulldown"], "cable", .cable, .total,
            [.lats: 1, .bicepsLongHead: 0.5, .bicepsShortHead: 0.45, .brachialis: 0.45, .lowerTraps: 0.4, .obliques: 0.25]
        ),
        seed(
            "machine-pulldown", "Machine pulldown", ["selectorized pulldown", "lever pulldown"], "machine", .selectorized, .total,
            [.lats: 1, .lowerTraps: 0.5, .rhomboids: 0.45, .bicepsLongHead: 0.5, .bicepsShortHead: 0.45, .brachialis: 0.4]
        ),
        seed(
            "plate-loaded-pulldown", "Plate-loaded pulldown", ["lever pulldown machine"], "plate-loaded machine", .plateLoaded, .total,
            [.lats: 1, .lowerTraps: 0.5, .rhomboids: 0.45, .bicepsLongHead: 0.5, .bicepsShortHead: 0.45, .brachialis: 0.4]
        ),
        seed(
            "straight-arm-cable-pulldown", "Straight-arm cable pulldown", ["straight arm pushdown", "lat pushdown"], "cable", .cable, .total,
            [.lats: 1, .lowerTraps: 0.4, .tricepsLongHead: 0.35, .rectusAbdominis: 0.25]
        ),
        seed(
            "cable-rope-pullover", "Cable rope pullover", ["rope pullover", "cable pullover"], "cable", .cable, .total,
            [.lats: 1, .tricepsLongHead: 0.4, .lowerTraps: 0.35, .rectusAbdominis: 0.25]
        ),
        seed(
            "machine-pullover", "Machine pullover", ["pullover machine"], "machine", .selectorized, .total,
            [.lats: 1, .tricepsLongHead: 0.4, .lowerTraps: 0.35, .rectusAbdominis: 0.2]
        ),
        seed(
            "seated-cable-row", "Seated cable row", ["cable row", "low row"], "cable", .cable, .total,
            [.rhomboids: 1, .middleTraps: 0.9, .lats: 0.75, .rearDelts: 0.55, .bicepsLongHead: 0.5, .bicepsShortHead: 0.45, .lowerBack: 0.3]
        ),
        seed(
            "wide-grip-seated-cable-row", "Wide-grip seated cable row", ["wide cable row"], "cable", .cable, .total,
            [.rhomboids: 1, .middleTraps: 0.95, .rearDelts: 0.8, .lats: 0.6, .bicepsLongHead: 0.4, .bicepsShortHead: 0.35]
        ),
        seed(
            "single-arm-cable-row", "Single-arm cable row", ["one arm cable row"], "cable", .cable, .total,
            [.lats: 1, .rhomboids: 0.8, .middleTraps: 0.7, .rearDelts: 0.5, .bicepsLongHead: 0.45, .obliques: 0.3]
        ),
        seed(
            "chest-supported-machine-row", "Chest-supported machine row", ["chest supported row"], "machine", .selectorized, .total,
            [.rhomboids: 1, .middleTraps: 0.9, .lats: 0.7, .rearDelts: 0.6, .bicepsLongHead: 0.45, .bicepsShortHead: 0.4]
        ),
        seed(
            "chest-supported-dumbbell-row", "Chest-supported dumbbell row", ["incline bench row", "prone dumbbell row"], "dumbbells", .dumbbell, .perHand,
            [.rhomboids: 1, .middleTraps: 0.9, .lats: 0.75, .rearDelts: 0.6, .bicepsLongHead: 0.45]
        ),
        seed(
            "machine-high-row", "Machine high row", ["high row"], "machine", .selectorized, .total,
            [.lats: 1, .rhomboids: 0.75, .middleTraps: 0.7, .lowerTraps: 0.55, .rearDelts: 0.5, .bicepsLongHead: 0.4]
        ),
        seed(
            "machine-low-row", "Machine low row", ["low row machine"], "machine", .selectorized, .total,
            [.lats: 1, .rhomboids: 0.85, .middleTraps: 0.7, .rearDelts: 0.45, .bicepsLongHead: 0.45, .lowerBack: 0.25]
        ),
        seed(
            "t-bar-row", "T-bar row", ["landmine t bar row"], "barbell", .barbell, .total,
            [.rhomboids: 1, .middleTraps: 0.9, .lats: 0.85, .rearDelts: 0.5, .lowerBack: 0.5, .bicepsLongHead: 0.45]
        ),
        seed(
            "landmine-row", "Landmine row", ["meadows row"], "barbell", .barbell, .total,
            [.lats: 1, .rhomboids: 0.8, .middleTraps: 0.7, .rearDelts: 0.5, .lowerBack: 0.4, .bicepsLongHead: 0.4]
        ),
        seed(
            "barbell-row", "Barbell row", ["bent over row", "bent-over barbell row"], "barbell", .barbell, .total,
            [.lats: 1, .rhomboids: 0.9, .middleTraps: 0.8, .rearDelts: 0.5, .lowerBack: 0.6, .bicepsLongHead: 0.45, .hamstrings: 0.3]
        ),
        seed(
            "pendlay-row", "Pendlay row", ["dead stop barbell row"], "barbell", .barbell, .total,
            [.rhomboids: 1, .middleTraps: 0.9, .lats: 0.85, .rearDelts: 0.55, .lowerBack: 0.55, .bicepsLongHead: 0.4]
        ),
        seed(
            "reverse-grip-barbell-row", "Reverse-grip barbell row", ["yates row", "underhand barbell row"], "barbell", .barbell, .total,
            [.lats: 1, .rhomboids: 0.75, .middleTraps: 0.65, .bicepsLongHead: 0.6, .bicepsShortHead: 0.55, .lowerBack: 0.5]
        ),
        seed(
            "single-arm-dumbbell-row", "Single-arm dumbbell row", ["one arm dumbbell row", "db row"], "dumbbells", .dumbbell, .perHand,
            [.lats: 1, .rhomboids: 0.8, .middleTraps: 0.7, .rearDelts: 0.5, .bicepsLongHead: 0.45, .obliques: 0.3]
        ),
        seed(
            "seal-row", "Seal row", ["bench supported barbell row"], "barbell", .barbell, .total,
            [.rhomboids: 1, .middleTraps: 0.95, .lats: 0.8, .rearDelts: 0.6, .bicepsLongHead: 0.45]
        ),
        seed(
            "smith-machine-row", "Smith machine row", ["smith bent over row"], "smith machine", .smith, .total,
            [.lats: 1, .rhomboids: 0.85, .middleTraps: 0.75, .rearDelts: 0.45, .lowerBack: 0.5, .bicepsLongHead: 0.4]
        ),
        seed(
            "inverted-row", "Inverted row", ["body row", "australian pull up"], "bodyweight", .bodyweight, .addedWeight,
            [.rhomboids: 1, .middleTraps: 0.9, .lats: 0.75, .rearDelts: 0.55, .bicepsLongHead: 0.45, .rectusAbdominis: 0.3]
        ),
        seed(
            "chin-up", "Chin-up", ["chinup", "underhand pull up"], "bodyweight", .bodyweight, .addedWeight,
            [.lats: 1, .bicepsLongHead: 0.8, .bicepsShortHead: 0.75, .brachialis: 0.55, .lowerTraps: 0.45, .rhomboids: 0.4]
        ),
        seed(
            "neutral-grip-pull-up", "Neutral-grip pull-up", ["hammer grip pull up"], "bodyweight", .bodyweight, .addedWeight,
            [.lats: 1, .brachialis: 0.7, .bicepsLongHead: 0.6, .bicepsShortHead: 0.5, .lowerTraps: 0.45, .rhomboids: 0.4]
        ),
        seed(
            "assisted-pull-up-machine", "Assisted pull-up machine", ["assisted chin", "dip chin assist"], "machine", .selectorized, .total,
            [.lats: 1, .bicepsLongHead: 0.6, .bicepsShortHead: 0.5, .brachialis: 0.5, .lowerTraps: 0.45, .rhomboids: 0.4]
        ),
        seed(
            "conventional-deadlift", "Conventional deadlift", ["deadlift"], "barbell", .barbell, .total,
            [.lowerBack: 1, .gluteMax: 0.95, .hamstrings: 0.9, .upperTraps: 0.6, .middleTraps: 0.5, .lats: 0.5, .vastusLateralis: 0.4, .rectusFemoris: 0.35, .adductors: 0.35]
        ),
        seed(
            "sumo-deadlift", "Sumo deadlift", ["sumo pull"], "barbell", .barbell, .total,
            [.gluteMax: 1, .adductors: 0.8, .lowerBack: 0.8, .hamstrings: 0.7, .vastusLateralis: 0.6, .vastusMedialis: 0.55, .upperTraps: 0.5, .lats: 0.4]
        ),
        seed(
            "trap-bar-deadlift", "Trap bar deadlift", ["hex bar deadlift"], "specialty bar", .barbell, .total,
            [.gluteMax: 1, .vastusLateralis: 0.75, .rectusFemoris: 0.65, .hamstrings: 0.7, .lowerBack: 0.8, .upperTraps: 0.55]
        ),
        seed(
            "rack-pull", "Rack pull", ["block pull"], "barbell", .barbell, .total,
            [.lowerBack: 1, .upperTraps: 0.7, .gluteMax: 0.7, .hamstrings: 0.5, .middleTraps: 0.5, .lats: 0.45]
        ),
        seed(
            "romanian-deadlift", "Romanian deadlift", ["rdl", "barbell rdl"], "barbell", .barbell, .total,
            [.hamstrings: 1, .gluteMax: 0.85, .lowerBack: 0.7, .middleTraps: 0.3, .lats: 0.3]
        ),
        seed(
            "dumbbell-romanian-deadlift", "Dumbbell Romanian deadlift", ["dumbbell rdl"], "dumbbells", .dumbbell, .perHand,
            [.hamstrings: 1, .gluteMax: 0.8, .lowerBack: 0.6]
        ),
        seed(
            "stiff-leg-deadlift", "Stiff-leg deadlift", ["straight leg deadlift"], "barbell", .barbell, .total,
            [.hamstrings: 1, .gluteMax: 0.75, .lowerBack: 0.8]
        ),
        seed(
            "single-leg-romanian-deadlift", "Single-leg Romanian deadlift", ["single leg rdl"], "dumbbells", .dumbbell, .perHand,
            [.hamstrings: 1, .gluteMax: 0.9, .gluteMed: 0.6, .lowerBack: 0.5]
        ),
        seed(
            "good-morning", "Good morning", ["barbell good morning"], "barbell", .barbell, .total,
            [.hamstrings: 1, .lowerBack: 0.95, .gluteMax: 0.75]
        ),
        seed(
            "barbell-shrug", "Barbell shrug", ["shrug"], "barbell", .barbell, .total,
            [.upperTraps: 1, .middleTraps: 0.45, .lowerTraps: 0.2]
        ),
        seed(
            "dumbbell-shrug", "Dumbbell shrug", ["db shrug"], "dumbbells", .dumbbell, .perHand,
            [.upperTraps: 1, .middleTraps: 0.45, .lowerTraps: 0.2]
        ),
        seed(
            "machine-shrug", "Machine shrug", ["shrug machine"], "machine", .selectorized, .total,
            [.upperTraps: 1, .middleTraps: 0.45, .lowerTraps: 0.2]
        ),
        seed(
            "smith-machine-shrug", "Smith machine shrug", ["smith shrug"], "smith machine", .smith, .total,
            [.upperTraps: 1, .middleTraps: 0.45, .lowerTraps: 0.2]
        ),
        seed(
            "cable-shrug", "Cable shrug", ["low cable shrug"], "cable", .cable, .total,
            [.upperTraps: 1, .middleTraps: 0.4, .lowerTraps: 0.2]
        ),
        seed(
            "back-extension", "Back extension", ["hyperextension", "45 degree back extension"], "bodyweight", .bodyweight, .addedWeight,
            [.lowerBack: 1, .gluteMax: 0.7, .hamstrings: 0.65]
        ),
        seed(
            "machine-back-extension", "Machine back extension", ["seated back extension"], "machine", .selectorized, .total,
            [.lowerBack: 1, .gluteMax: 0.5, .hamstrings: 0.4]
        ),
        seed(
            "reverse-hyperextension", "Reverse hyperextension", ["reverse hyper"], "plate-loaded machine", .plateLoaded, .total,
            [.gluteMax: 1, .hamstrings: 0.8, .lowerBack: 0.7]
        ),
        seed(
            "glute-ham-raise", "Glute-ham raise", ["ghd raise", "ghr"], "bodyweight", .bodyweight, .addedWeight,
            [.hamstrings: 1, .gluteMax: 0.6, .lowerBack: 0.5, .gastrocnemius: 0.3]
        ),
    ]
}

// MARK: - Shoulders

extension ExerciseCatalog {
    static let shoulderSeeds: [ExerciseDefinition] = [
        seed(
            "machine-shoulder-press", "Machine shoulder press", ["overhead press machine", "seated shoulder press machine"], "machine", .selectorized, .total,
            [.frontDelts: 1, .sideDelts: 0.7, .tricepsLateralHead: 0.55, .tricepsLongHead: 0.4, .upperChest: 0.25]
        ),
        seed(
            "plate-loaded-shoulder-press", "Plate-loaded shoulder press", ["lever shoulder press"], "plate-loaded machine", .plateLoaded, .total,
            [.frontDelts: 1, .sideDelts: 0.7, .tricepsLateralHead: 0.55, .tricepsLongHead: 0.4, .upperChest: 0.25]
        ),
        seed(
            "standing-overhead-press", "Standing overhead press", ["military press", "barbell overhead press", "ohp"], "barbell", .barbell, .total,
            [.frontDelts: 1, .sideDelts: 0.65, .tricepsLateralHead: 0.6, .tricepsLongHead: 0.45, .upperChest: 0.3, .rectusAbdominis: 0.35, .upperTraps: 0.35]
        ),
        seed(
            "seated-barbell-overhead-press", "Seated barbell overhead press", ["seated military press"], "barbell", .barbell, .total,
            [.frontDelts: 1, .sideDelts: 0.7, .tricepsLateralHead: 0.6, .tricepsLongHead: 0.45, .upperChest: 0.3, .upperTraps: 0.3]
        ),
        seed(
            "dumbbell-shoulder-press", "Dumbbell shoulder press", ["seated dumbbell press", "db shoulder press"], "dumbbells", .dumbbell, .perHand,
            [.frontDelts: 1, .sideDelts: 0.75, .tricepsLateralHead: 0.5, .tricepsLongHead: 0.35, .upperChest: 0.25, .upperTraps: 0.3]
        ),
        seed(
            "arnold-press", "Arnold press", ["arnold dumbbell press"], "dumbbells", .dumbbell, .perHand,
            [.frontDelts: 1, .sideDelts: 0.8, .tricepsLateralHead: 0.45, .upperChest: 0.25, .upperTraps: 0.3]
        ),
        seed(
            "smith-machine-shoulder-press", "Smith machine shoulder press", ["smith overhead press"], "smith machine", .smith, .total,
            [.frontDelts: 1, .sideDelts: 0.7, .tricepsLateralHead: 0.55, .tricepsLongHead: 0.4, .upperChest: 0.25]
        ),
        seed(
            "push-press", "Push press", ["barbell push press"], "barbell", .barbell, .total,
            [.frontDelts: 1, .sideDelts: 0.6, .tricepsLateralHead: 0.6, .gluteMax: 0.4, .rectusFemoris: 0.4, .rectusAbdominis: 0.35]
        ),
        seed(
            "landmine-shoulder-press", "Landmine shoulder press", ["half kneeling landmine press"], "barbell", .barbell, .total,
            [.frontDelts: 1, .upperChest: 0.55, .sideDelts: 0.4, .tricepsLateralHead: 0.45, .obliques: 0.35]
        ),
        seed(
            "dumbbell-lateral-raise", "Dumbbell lateral raise", ["side raise", "lateral raise"], "dumbbells", .dumbbell, .perHand,
            [.sideDelts: 1, .frontDelts: 0.3, .upperTraps: 0.3, .rearDelts: 0.2]
        ),
        seed(
            "leaning-dumbbell-lateral-raise", "Leaning dumbbell lateral raise", ["lean away lateral raise"], "dumbbells", .dumbbell, .perHand,
            [.sideDelts: 1, .upperTraps: 0.25, .frontDelts: 0.2]
        ),
        seed(
            "machine-lateral-raise", "Machine lateral raise", ["lateral raise machine"], "machine", .selectorized, .total,
            [.sideDelts: 1, .upperTraps: 0.3, .frontDelts: 0.25]
        ),
        seed(
            "cable-lateral-raise", "Cable lateral raise", ["cable side raise"], "cable", .cable, .total,
            [.sideDelts: 1, .frontDelts: 0.25, .upperTraps: 0.25]
        ),
        seed(
            "dumbbell-front-raise", "Dumbbell front raise", ["front raise"], "dumbbells", .dumbbell, .perHand,
            [.frontDelts: 1, .sideDelts: 0.3, .upperChest: 0.25]
        ),
        seed(
            "cable-front-raise", "Cable front raise", ["cable anterior raise"], "cable", .cable, .total,
            [.frontDelts: 1, .sideDelts: 0.3, .upperChest: 0.2]
        ),
        seed(
            "reverse-pec-deck", "Reverse pec deck", ["rear delt machine", "reverse fly machine", "rear delt fly machine"], "machine", .selectorized, .total,
            [.rearDelts: 1, .rhomboids: 0.6, .middleTraps: 0.55, .lowerTraps: 0.3]
        ),
        seed(
            "cable-rear-delt-fly", "Cable rear delt fly", ["reverse cable fly", "cable reverse fly"], "cable", .cable, .total,
            [.rearDelts: 1, .rhomboids: 0.55, .middleTraps: 0.5]
        ),
        seed(
            "dumbbell-reverse-fly", "Dumbbell reverse fly", ["bent over reverse fly", "rear delt fly"], "dumbbells", .dumbbell, .perHand,
            [.rearDelts: 1, .rhomboids: 0.6, .middleTraps: 0.55, .lowerTraps: 0.25]
        ),
        seed(
            "rope-face-pull", "Rope face pull", ["face pull"], "cable", .cable, .total,
            [.rearDelts: 1, .middleTraps: 0.7, .rhomboids: 0.65, .lowerTraps: 0.5]
        ),
        seed(
            "cable-rear-delt-row", "Cable rear delt row", ["rope high row", "rear delt row"], "cable", .cable, .total,
            [.rearDelts: 1, .rhomboids: 0.7, .middleTraps: 0.65, .lats: 0.3]
        ),
        seed(
            "barbell-upright-row", "Barbell upright row", ["upright row"], "barbell", .barbell, .total,
            [.sideDelts: 1, .upperTraps: 0.8, .frontDelts: 0.45, .brachialis: 0.3]
        ),
        seed(
            "cable-upright-row", "Cable upright row", ["rope upright row"], "cable", .cable, .total,
            [.sideDelts: 1, .upperTraps: 0.75, .frontDelts: 0.4, .brachialis: 0.3]
        ),
        seed(
            "machine-rear-delt-row", "Machine rear delt row", ["rear delt machine row"], "machine", .selectorized, .total,
            [.rearDelts: 1, .rhomboids: 0.7, .middleTraps: 0.65, .lats: 0.3]
        ),
    ]
}

// MARK: - Arms

extension ExerciseCatalog {
    static let armSeeds: [ExerciseDefinition] = [
        seed(
            "barbell-curl", "Barbell curl", ["straight bar curl"], "barbell", .barbell, .total,
            [.bicepsShortHead: 1, .bicepsLongHead: 0.85, .brachialis: 0.5, .forearms: 0.3]
        ),
        seed(
            "ez-bar-curl", "EZ-bar curl", ["ez curl"], "specialty bar", .barbell, .total,
            [.bicepsShortHead: 1, .bicepsLongHead: 0.8, .brachialis: 0.55, .forearms: 0.3]
        ),
        seed(
            "dumbbell-curl", "Dumbbell curl", ["standing dumbbell curl", "db curl"], "dumbbells", .dumbbell, .perHand,
            [.bicepsShortHead: 1, .bicepsLongHead: 0.85, .brachialis: 0.5, .forearms: 0.3]
        ),
        seed(
            "hammer-curl", "Hammer curl", ["neutral grip curl"], "dumbbells", .dumbbell, .perHand,
            [.brachialis: 1, .forearms: 0.7, .bicepsLongHead: 0.65, .bicepsShortHead: 0.45]
        ),
        seed(
            "cross-body-hammer-curl", "Cross-body hammer curl", ["pinwheel curl"], "dumbbells", .dumbbell, .perHand,
            [.brachialis: 1, .forearms: 0.7, .bicepsLongHead: 0.6, .bicepsShortHead: 0.4]
        ),
        seed(
            "preacher-curl", "Preacher curl", ["ez bar preacher curl"], "specialty bar", .barbell, .total,
            [.bicepsShortHead: 1, .brachialis: 0.65, .bicepsLongHead: 0.55, .forearms: 0.25]
        ),
        seed(
            "machine-preacher-curl", "Machine preacher curl", ["biceps curl machine", "arm curl machine"], "machine", .selectorized, .total,
            [.bicepsShortHead: 1, .brachialis: 0.65, .bicepsLongHead: 0.55, .forearms: 0.2]
        ),
        seed(
            "dumbbell-preacher-curl", "Dumbbell preacher curl", ["single arm preacher curl"], "dumbbells", .dumbbell, .perHand,
            [.bicepsShortHead: 1, .brachialis: 0.6, .bicepsLongHead: 0.5, .forearms: 0.25]
        ),
        seed(
            "concentration-curl", "Concentration curl", ["seated concentration curl"], "dumbbells", .dumbbell, .perHand,
            [.bicepsShortHead: 1, .bicepsLongHead: 0.6, .brachialis: 0.5, .forearms: 0.25]
        ),
        seed(
            "spider-curl", "Spider curl", ["prone incline curl"], "dumbbells", .dumbbell, .perHand,
            [.bicepsShortHead: 1, .bicepsLongHead: 0.55, .brachialis: 0.5, .forearms: 0.2]
        ),
        seed(
            "cable-curl", "Cable curl", ["straight bar cable curl"], "cable", .cable, .total,
            [.bicepsShortHead: 1, .bicepsLongHead: 0.85, .brachialis: 0.5, .forearms: 0.25]
        ),
        seed(
            "rope-hammer-cable-curl", "Rope hammer cable curl", ["rope curl"], "cable", .cable, .total,
            [.brachialis: 1, .forearms: 0.65, .bicepsLongHead: 0.6, .bicepsShortHead: 0.45]
        ),
        seed(
            "bayesian-cable-curl", "Bayesian cable curl", ["behind body cable curl", "single arm cable curl"], "cable", .cable, .total,
            [.bicepsLongHead: 1, .bicepsShortHead: 0.6, .brachialis: 0.45, .forearms: 0.25]
        ),
        seed(
            "reverse-curl", "Reverse curl", ["pronated curl", "reverse grip curl"], "specialty bar", .barbell, .total,
            [.forearms: 1, .brachialis: 0.9, .bicepsShortHead: 0.4, .bicepsLongHead: 0.35]
        ),
        seed(
            "drag-curl", "Drag curl", ["barbell drag curl"], "barbell", .barbell, .total,
            [.bicepsLongHead: 1, .bicepsShortHead: 0.6, .brachialis: 0.5, .forearms: 0.25]
        ),
        seed(
            "v-bar-triceps-pushdown", "V-bar triceps pushdown", ["v handle pushdown", "angled bar pushdown"], "cable", .cable, .total,
            [.tricepsLateralHead: 1, .tricepsMedialHead: 0.85, .tricepsLongHead: 0.5]
        ),
        seed(
            "single-arm-cable-pushdown", "Single-arm cable pushdown", ["one arm triceps pushdown", "reverse grip pushdown"], "cable", .cable, .total,
            [.tricepsLateralHead: 1, .tricepsMedialHead: 0.8, .tricepsLongHead: 0.45]
        ),
        seed(
            "overhead-rope-triceps-extension", "Overhead rope triceps extension", ["cable overhead extension"], "cable", .cable, .total,
            [.tricepsLongHead: 1, .tricepsMedialHead: 0.6, .tricepsLateralHead: 0.55]
        ),
        seed(
            "overhead-ez-bar-triceps-extension", "Overhead EZ-bar triceps extension", ["french press", "seated overhead extension"], "specialty bar", .barbell, .total,
            [.tricepsLongHead: 1, .tricepsMedialHead: 0.6, .tricepsLateralHead: 0.55]
        ),
        seed(
            "single-arm-overhead-dumbbell-extension", "Single-arm overhead dumbbell extension", ["one arm triceps extension"], "dumbbells", .dumbbell, .perHand,
            [.tricepsLongHead: 1, .tricepsMedialHead: 0.6, .tricepsLateralHead: 0.5]
        ),
        seed(
            "lying-triceps-extension", "Lying triceps extension", ["skullcrusher", "skull crusher"], "specialty bar", .barbell, .total,
            [.tricepsLongHead: 1, .tricepsLateralHead: 0.75, .tricepsMedialHead: 0.7]
        ),
        seed(
            "jm-press", "JM press", ["jm bench press"], "barbell", .barbell, .total,
            [.tricepsLateralHead: 1, .tricepsMedialHead: 0.85, .tricepsLongHead: 0.8, .middleChest: 0.35, .frontDelts: 0.3]
        ),
        seed(
            "bench-dip", "Bench dip", ["tricep bench dip"], "bodyweight", .bodyweight, .addedWeight,
            [.tricepsLateralHead: 1, .tricepsMedialHead: 0.8, .tricepsLongHead: 0.7, .frontDelts: 0.4, .lowerChest: 0.35]
        ),
        seed(
            "machine-triceps-extension", "Machine triceps extension", ["triceps extension machine", "arm extension machine"], "machine", .selectorized, .total,
            [.tricepsLateralHead: 1, .tricepsMedialHead: 0.85, .tricepsLongHead: 0.6]
        ),
        seed(
            "machine-triceps-press", "Machine triceps press", ["triceps press machine"], "machine", .selectorized, .total,
            [.tricepsLateralHead: 1, .tricepsMedialHead: 0.85, .tricepsLongHead: 0.55, .lowerChest: 0.25]
        ),
        seed(
            "cable-triceps-kickback", "Cable triceps kickback", ["cable kickback"], "cable", .cable, .total,
            [.tricepsLongHead: 1, .tricepsLateralHead: 0.7, .tricepsMedialHead: 0.6]
        ),
        seed(
            "dumbbell-triceps-kickback", "Dumbbell triceps kickback", ["kickback"], "dumbbells", .dumbbell, .perHand,
            [.tricepsLongHead: 1, .tricepsLateralHead: 0.7, .tricepsMedialHead: 0.6]
        ),
        seed(
            "barbell-wrist-curl", "Barbell wrist curl", ["seated wrist curl"], "barbell", .barbell, .total,
            [.forearms: 1]
        ),
        seed(
            "reverse-barbell-wrist-curl", "Reverse barbell wrist curl", ["reverse forearm curl"], "barbell", .barbell, .total,
            [.forearms: 1]
        ),
        seed(
            "cable-wrist-curl", "Cable wrist curl", ["cable forearm curl"], "cable", .cable, .total,
            [.forearms: 1]
        ),
        seed(
            "wrist-roller", "Wrist roller", ["forearm roller"], "other", .other, .total,
            [.forearms: 1]
        ),
        seed(
            "farmers-carry", "Farmer's carry", ["farmers walk", "loaded carry"], "dumbbells", .dumbbell, .perHand,
            [.forearms: 1, .upperTraps: 0.8, .obliques: 0.6, .rectusAbdominis: 0.5, .gluteMed: 0.4, .lowerBack: 0.4]
        ),
        seed(
            "plate-pinch-hold", "Plate pinch hold", ["pinch grip hold"], "other", .other, .total,
            [.forearms: 1]
        ),
    ]
}

// MARK: - Legs

extension ExerciseCatalog {
    static let legSeeds: [ExerciseDefinition] = [
        seed(
            "back-squat", "Back squat", ["barbell squat", "squat"], "barbell", .barbell, .total,
            [.vastusLateralis: 1, .rectusFemoris: 0.9, .vastusMedialis: 0.9, .gluteMax: 0.85, .adductors: 0.5, .lowerBack: 0.5, .hamstrings: 0.4]
        ),
        seed(
            "front-squat", "Front squat", ["barbell front squat"], "barbell", .barbell, .total,
            [.rectusFemoris: 1, .vastusLateralis: 0.95, .vastusMedialis: 0.95, .gluteMax: 0.65, .rectusAbdominis: 0.45, .lowerBack: 0.45, .adductors: 0.4]
        ),
        seed(
            "smith-machine-squat", "Smith machine squat", ["smith squat"], "smith machine", .smith, .total,
            [.vastusLateralis: 1, .rectusFemoris: 0.9, .vastusMedialis: 0.9, .gluteMax: 0.75, .adductors: 0.4, .hamstrings: 0.35]
        ),
        seed(
            "goblet-squat", "Goblet squat", ["dumbbell goblet squat"], "dumbbells", .dumbbell, .total,
            [.vastusLateralis: 1, .rectusFemoris: 0.9, .vastusMedialis: 0.9, .gluteMax: 0.7, .rectusAbdominis: 0.35, .adductors: 0.4]
        ),
        seed(
            "hack-squat-machine", "Hack squat machine", ["sled hack squat", "45 degree hack squat"], "plate-loaded machine", .plateLoaded, .total,
            [.vastusLateralis: 1, .vastusMedialis: 0.95, .rectusFemoris: 0.9, .gluteMax: 0.6, .adductors: 0.4]
        ),
        seed(
            "pendulum-squat", "Pendulum squat", ["arc squat"], "plate-loaded machine", .plateLoaded, .total,
            [.vastusLateralis: 1, .vastusMedialis: 0.95, .rectusFemoris: 0.95, .gluteMax: 0.7, .adductors: 0.4]
        ),
        seed(
            "belt-squat", "Belt squat", ["hip belt squat"], "plate-loaded machine", .plateLoaded, .total,
            [.vastusLateralis: 1, .rectusFemoris: 0.85, .vastusMedialis: 0.9, .gluteMax: 0.8, .adductors: 0.45]
        ),
        seed(
            "v-squat-machine", "V-squat machine", ["v squat"], "plate-loaded machine", .plateLoaded, .total,
            [.vastusLateralis: 1, .vastusMedialis: 0.9, .rectusFemoris: 0.85, .gluteMax: 0.75, .adductors: 0.4]
        ),
        seed(
            "sissy-squat", "Sissy squat", ["sissy squat bench"], "bodyweight", .bodyweight, .addedWeight,
            [.rectusFemoris: 1, .vastusMedialis: 0.85, .vastusLateralis: 0.8]
        ),
        seed(
            "bulgarian-split-squat", "Bulgarian split squat", ["rear foot elevated split squat", "rfess"], "dumbbells", .dumbbell, .perHand,
            [.gluteMax: 1, .vastusLateralis: 0.85, .rectusFemoris: 0.8, .vastusMedialis: 0.8, .gluteMed: 0.6, .adductors: 0.5, .hamstrings: 0.4]
        ),
        seed(
            "split-squat", "Split squat", ["static lunge"], "dumbbells", .dumbbell, .perHand,
            [.vastusLateralis: 1, .gluteMax: 0.85, .rectusFemoris: 0.8, .vastusMedialis: 0.8, .gluteMed: 0.5, .adductors: 0.4]
        ),
        seed(
            "walking-lunge", "Walking lunge", ["dumbbell walking lunge"], "dumbbells", .dumbbell, .perHand,
            [.gluteMax: 1, .vastusLateralis: 0.85, .rectusFemoris: 0.8, .vastusMedialis: 0.75, .gluteMed: 0.55, .hamstrings: 0.45, .adductors: 0.4]
        ),
        seed(
            "reverse-lunge", "Reverse lunge", ["backward lunge"], "dumbbells", .dumbbell, .perHand,
            [.gluteMax: 1, .vastusLateralis: 0.75, .rectusFemoris: 0.7, .hamstrings: 0.5, .gluteMed: 0.5, .adductors: 0.4]
        ),
        seed(
            "step-up", "Step-up", ["dumbbell step up", "box step up"], "dumbbells", .dumbbell, .perHand,
            [.gluteMax: 1, .vastusLateralis: 0.8, .rectusFemoris: 0.75, .gluteMed: 0.6, .hamstrings: 0.4]
        ),
        seed(
            "leg-press", "Leg press", ["45 degree leg press", "sled leg press"], "plate-loaded machine", .plateLoaded, .total,
            [.vastusLateralis: 1, .vastusMedialis: 0.9, .rectusFemoris: 0.85, .gluteMax: 0.75, .adductors: 0.45, .hamstrings: 0.3]
        ),
        seed(
            "horizontal-leg-press", "Horizontal leg press", ["seated leg press", "selectorized leg press"], "machine", .selectorized, .total,
            [.vastusLateralis: 1, .vastusMedialis: 0.9, .rectusFemoris: 0.85, .gluteMax: 0.7, .adductors: 0.4]
        ),
        seed(
            "vertical-leg-press", "Vertical leg press", ["upright leg press"], "plate-loaded machine", .plateLoaded, .total,
            [.gluteMax: 1, .vastusLateralis: 0.9, .vastusMedialis: 0.85, .rectusFemoris: 0.8, .hamstrings: 0.4, .adductors: 0.4]
        ),
        seed(
            "single-leg-press", "Single-leg press", ["one leg press"], "plate-loaded machine", .plateLoaded, .total,
            [.vastusLateralis: 1, .vastusMedialis: 0.9, .rectusFemoris: 0.85, .gluteMax: 0.8, .gluteMed: 0.45, .adductors: 0.4]
        ),
        seed(
            "single-leg-extension", "Single-leg extension", ["one leg extension"], "machine", .selectorized, .total,
            [.rectusFemoris: 1, .vastusLateralis: 0.95, .vastusMedialis: 0.95]
        ),
        seed(
            "standing-leg-curl", "Standing leg curl", ["single leg standing curl"], "machine", .selectorized, .total,
            [.hamstrings: 1, .gastrocnemius: 0.25, .gluteMax: 0.2]
        ),
        seed(
            "nordic-curl", "Nordic curl", ["nordic hamstring curl"], "bodyweight", .bodyweight, .addedWeight,
            [.hamstrings: 1, .gastrocnemius: 0.3, .gluteMax: 0.3]
        ),
        seed(
            "barbell-hip-thrust", "Barbell hip thrust", ["hip thrust"], "barbell", .barbell, .total,
            [.gluteMax: 1, .hamstrings: 0.55, .vastusLateralis: 0.35, .adductors: 0.3]
        ),
        seed(
            "machine-hip-thrust", "Machine hip thrust", ["hip thrust machine", "glute drive"], "machine", .selectorized, .total,
            [.gluteMax: 1, .hamstrings: 0.5, .vastusLateralis: 0.3]
        ),
        seed(
            "smith-machine-hip-thrust", "Smith machine hip thrust", ["smith hip thrust"], "smith machine", .smith, .total,
            [.gluteMax: 1, .hamstrings: 0.5, .vastusLateralis: 0.3]
        ),
        seed(
            "glute-bridge", "Glute bridge", ["barbell glute bridge"], "barbell", .barbell, .total,
            [.gluteMax: 1, .hamstrings: 0.55]
        ),
        seed(
            "cable-glute-kickback", "Cable glute kickback", ["cable kickback glute", "glute kickback"], "cable", .cable, .total,
            [.gluteMax: 1, .hamstrings: 0.45, .gluteMed: 0.35]
        ),
        seed(
            "machine-glute-kickback", "Machine glute kickback", ["glute machine", "kickback machine"], "machine", .selectorized, .total,
            [.gluteMax: 1, .hamstrings: 0.45, .gluteMed: 0.35]
        ),
        seed(
            "standing-calf-raise", "Standing calf raise", ["standing calf machine"], "machine", .selectorized, .total,
            [.gastrocnemius: 1, .soleus: 0.6]
        ),
        seed(
            "seated-calf-raise", "Seated calf raise", ["seated calf machine"], "plate-loaded machine", .plateLoaded, .total,
            [.soleus: 1, .gastrocnemius: 0.5]
        ),
        seed(
            "leg-press-calf-raise", "Leg press calf raise", ["calf press on leg press"], "plate-loaded machine", .plateLoaded, .total,
            [.gastrocnemius: 1, .soleus: 0.65]
        ),
        seed(
            "smith-machine-calf-raise", "Smith machine calf raise", ["smith calf raise"], "smith machine", .smith, .total,
            [.gastrocnemius: 1, .soleus: 0.6]
        ),
        seed(
            "donkey-calf-raise", "Donkey calf raise", ["bent over calf raise"], "machine", .selectorized, .total,
            [.gastrocnemius: 1, .soleus: 0.55]
        ),
        seed(
            "single-leg-calf-raise", "Single-leg calf raise", ["one leg calf raise"], "dumbbells", .dumbbell, .perHand,
            [.gastrocnemius: 1, .soleus: 0.6]
        ),
        seed(
            "tibialis-raise", "Tibialis raise", ["tib raise", "dorsiflexion raise"], "other", .other, .total,
            [.tibialisAnterior: 1]
        ),
        seed(
            "adductor-machine-standing", "Standing cable adduction", ["cable adduction"], "cable", .cable, .total,
            [.adductors: 1, .gluteMed: 0.2]
        ),
        seed(
            "abductor-machine-standing", "Standing cable abduction", ["cable abduction"], "cable", .cable, .total,
            [.abductors: 1, .gluteMed: 0.85, .gluteMax: 0.3]
        ),
        seed(
            "hip-flexor-machine", "Hip flexor machine", ["multi hip machine"], "machine", .selectorized, .total,
            [.rectusFemoris: 1, .rectusAbdominis: 0.4, .adductors: 0.3]
        ),
    ]
}

// MARK: - Core

extension ExerciseCatalog {
    static let coreSeeds: [ExerciseDefinition] = [
        seed(
            "machine-crunch", "Machine crunch", ["abdominal machine", "ab crunch machine"], "machine", .selectorized, .total,
            [.rectusAbdominis: 1, .obliques: 0.35]
        ),
        seed(
            "machine-oblique-crunch", "Machine oblique crunch", ["oblique machine", "rotary torso crunch"], "machine", .selectorized, .total,
            [.obliques: 1, .rectusAbdominis: 0.6]
        ),
        seed(
            "machine-torso-rotation", "Machine torso rotation", ["torso rotation", "rotary torso"], "machine", .selectorized, .total,
            [.obliques: 1, .rectusAbdominis: 0.45]
        ),
        seed(
            "decline-sit-up", "Decline sit-up", ["decline crunch"], "bodyweight", .bodyweight, .addedWeight,
            [.rectusAbdominis: 1, .obliques: 0.4, .rectusFemoris: 0.35]
        ),
        seed(
            "hanging-leg-raise", "Hanging leg raise", ["hanging knee raise"], "bodyweight", .bodyweight, .addedWeight,
            [.rectusAbdominis: 1, .obliques: 0.5, .rectusFemoris: 0.45]
        ),
        seed(
            "captains-chair-knee-raise", "Captain's chair knee raise", ["vertical knee raise"], "bodyweight", .bodyweight, .addedWeight,
            [.rectusAbdominis: 1, .obliques: 0.45, .rectusFemoris: 0.45]
        ),
        seed(
            "lying-leg-raise", "Lying leg raise", ["floor leg raise"], "bodyweight", .bodyweight, .addedWeight,
            [.rectusAbdominis: 1, .obliques: 0.35, .rectusFemoris: 0.4]
        ),
        seed(
            "ab-wheel-rollout", "Ab wheel rollout", ["ab rollout"], "other", .other, .addedWeight,
            [.rectusAbdominis: 1, .obliques: 0.5, .lats: 0.4, .lowerBack: 0.3]
        ),
        seed(
            "plank", "Plank", ["front plank"], "bodyweight", .bodyweight, .addedWeight,
            [.rectusAbdominis: 1, .obliques: 0.6, .lowerBack: 0.3]
        ),
        seed(
            "side-plank", "Side plank", ["lateral plank"], "bodyweight", .bodyweight, .addedWeight,
            [.obliques: 1, .rectusAbdominis: 0.5, .gluteMed: 0.4]
        ),
        seed(
            "cable-woodchop", "Cable woodchop", ["woodchopper", "high to low chop"], "cable", .cable, .total,
            [.obliques: 1, .rectusAbdominis: 0.6, .lowerBack: 0.25]
        ),
        seed(
            "pallof-press", "Pallof press", ["anti rotation press"], "cable", .cable, .total,
            [.obliques: 1, .rectusAbdominis: 0.6]
        ),
        seed(
            "russian-twist", "Russian twist", ["seated twist"], "other", .other, .addedWeight,
            [.obliques: 1, .rectusAbdominis: 0.6]
        ),
        seed(
            "standing-cable-crunch", "Standing cable crunch", ["standing rope crunch"], "cable", .cable, .total,
            [.rectusAbdominis: 1, .obliques: 0.35]
        ),
        seed(
            "dumbbell-side-bend", "Dumbbell side bend", ["side bend"], "dumbbells", .dumbbell, .perHand,
            [.obliques: 1, .lowerBack: 0.35]
        ),
    ]
}

// MARK: - Brand-signature machines

extension ExerciseCatalog {
    /// Movements where the maker *is* the movement.
    ///
    /// A Hammer Strength Iso-Lateral Row runs an independent, converging arc that no
    /// generic seated row reproduces, so it is its own row in the catalog with its own
    /// id and its own history. Everything else machine-based is a generic movement that
    /// simply happens to be built by several companies, and for those the brand is
    /// selected when logging (`ExerciseDefinition.qualifiedID`) instead of duplicating
    /// the row fourteen times.
    ///
    /// Every entry below is a product that the manufacturer actually sells. Product
    /// lines were read off the makers' own catalogs; nothing here is invented, and
    /// brands whose lineup is a set of generic movements (Matrix, Technogym, Precor,
    /// Nautilus, Body-Solid, Eleiko) deliberately get no signature rows at all.
    static let brandSignatureSeeds: [ExerciseDefinition] = [
        // Hammer Strength plate-loaded, from the Life Fitness plate-loaded catalog.
        seed(
            "hammer-strength-iso-lateral-row", "Hammer Strength Iso-Lateral row", ["iso lateral row", "iso row"], "plate-loaded machine", .plateLoaded, .perHand,
            [.lats: 1, .rhomboids: 0.85, .middleTraps: 0.7, .rearDelts: 0.5, .bicepsLongHead: 0.45, .bicepsShortHead: 0.4],
            brand: .hammerStrength, signature: true
        ),
        seed(
            "hammer-strength-iso-lateral-high-row", "Hammer Strength Iso-Lateral high row", ["iso lateral high row"], "plate-loaded machine", .plateLoaded, .perHand,
            [.lats: 1, .lowerTraps: 0.6, .rhomboids: 0.7, .middleTraps: 0.65, .rearDelts: 0.5, .bicepsLongHead: 0.4],
            brand: .hammerStrength, signature: true
        ),
        seed(
            "hammer-strength-iso-lateral-low-row", "Hammer Strength Iso-Lateral low row", ["iso lateral low row"], "plate-loaded machine", .plateLoaded, .perHand,
            [.lats: 1, .rhomboids: 0.85, .middleTraps: 0.7, .rearDelts: 0.45, .bicepsLongHead: 0.45, .lowerBack: 0.25],
            brand: .hammerStrength, signature: true
        ),
        seed(
            "hammer-strength-iso-lateral-dy-row", "Hammer Strength Iso-Lateral D.Y. row", ["dy row", "dorian yates row"], "plate-loaded machine", .plateLoaded, .perHand,
            [.lats: 1, .rhomboids: 0.8, .middleTraps: 0.65, .rearDelts: 0.45, .bicepsLongHead: 0.5, .bicepsShortHead: 0.45],
            brand: .hammerStrength, signature: true
        ),
        seed(
            "hammer-strength-iso-lateral-front-lat-pulldown", "Hammer Strength Iso-Lateral front lat pulldown", ["iso lateral pulldown"], "plate-loaded machine", .plateLoaded, .perHand,
            [.lats: 1, .lowerTraps: 0.5, .rhomboids: 0.45, .bicepsLongHead: 0.5, .bicepsShortHead: 0.45, .brachialis: 0.4],
            brand: .hammerStrength, signature: true
        ),
        seed(
            "hammer-strength-iso-lateral-wide-pulldown", "Hammer Strength Iso-Lateral wide pulldown", ["iso lateral wide pulldown"], "plate-loaded machine", .plateLoaded, .perHand,
            [.lats: 1, .lowerTraps: 0.55, .rhomboids: 0.5, .rearDelts: 0.4, .bicepsLongHead: 0.4, .brachialis: 0.35],
            brand: .hammerStrength, signature: true
        ),
        seed(
            "hammer-strength-iso-lateral-bench-press", "Hammer Strength Iso-Lateral bench press", ["iso lateral chest press"], "plate-loaded machine", .plateLoaded, .perHand,
            [.middleChest: 1, .lowerChest: 0.55, .upperChest: 0.4, .frontDelts: 0.55, .tricepsLateralHead: 0.5, .tricepsLongHead: 0.35],
            brand: .hammerStrength, signature: true
        ),
        seed(
            "hammer-strength-iso-lateral-horizontal-bench-press", "Hammer Strength Iso-Lateral horizontal bench press", ["iso lateral horizontal press"], "plate-loaded machine", .plateLoaded, .perHand,
            [.middleChest: 1, .lowerChest: 0.5, .upperChest: 0.4, .frontDelts: 0.5, .tricepsLateralHead: 0.5, .tricepsLongHead: 0.35],
            brand: .hammerStrength, signature: true
        ),
        seed(
            "hammer-strength-iso-lateral-incline-press", "Hammer Strength Iso-Lateral incline press", ["iso lateral incline"], "plate-loaded machine", .plateLoaded, .perHand,
            [.upperChest: 1, .middleChest: 0.55, .frontDelts: 0.7, .tricepsLateralHead: 0.5, .tricepsLongHead: 0.35],
            brand: .hammerStrength, signature: true
        ),
        seed(
            "hammer-strength-iso-lateral-super-incline-press", "Hammer Strength Iso-Lateral super incline press", ["super incline press"], "plate-loaded machine", .plateLoaded, .perHand,
            [.upperChest: 1, .frontDelts: 0.85, .middleChest: 0.4, .tricepsLateralHead: 0.5, .tricepsLongHead: 0.35],
            brand: .hammerStrength, signature: true
        ),
        seed(
            "hammer-strength-iso-lateral-decline-press", "Hammer Strength Iso-Lateral decline press", ["iso lateral decline"], "plate-loaded machine", .plateLoaded, .perHand,
            [.lowerChest: 1, .middleChest: 0.7, .tricepsLateralHead: 0.5, .tricepsLongHead: 0.35, .frontDelts: 0.25],
            brand: .hammerStrength, signature: true
        ),
        seed(
            "hammer-strength-iso-lateral-wide-chest", "Hammer Strength Iso-Lateral wide chest", ["iso lateral wide chest"], "plate-loaded machine", .plateLoaded, .perHand,
            [.middleChest: 1, .lowerChest: 0.6, .upperChest: 0.45, .frontDelts: 0.45, .tricepsLateralHead: 0.35],
            brand: .hammerStrength, signature: true
        ),
        seed(
            "hammer-strength-iso-lateral-shoulder-press", "Hammer Strength Iso-Lateral shoulder press", ["iso lateral shoulder press"], "plate-loaded machine", .plateLoaded, .perHand,
            [.frontDelts: 1, .sideDelts: 0.7, .tricepsLateralHead: 0.55, .tricepsLongHead: 0.4, .upperChest: 0.25],
            brand: .hammerStrength, signature: true
        ),
        seed(
            "hammer-strength-iso-lateral-leg-curl", "Hammer Strength Iso-Lateral leg curl", ["iso lateral leg curl"], "plate-loaded machine", .plateLoaded, .perHand,
            [.hamstrings: 1, .gastrocnemius: 0.25],
            brand: .hammerStrength, signature: true
        ),
        seed(
            "hammer-strength-iso-lateral-kneeling-leg-curl", "Hammer Strength Iso-Lateral kneeling leg curl", ["kneeling leg curl"], "plate-loaded machine", .plateLoaded, .perHand,
            [.hamstrings: 1, .gastrocnemius: 0.25, .gluteMax: 0.2],
            brand: .hammerStrength, signature: true
        ),
        seed(
            "hammer-strength-iso-lateral-leg-extension", "Hammer Strength Iso-Lateral leg extension", ["iso lateral leg extension"], "plate-loaded machine", .plateLoaded, .perHand,
            [.rectusFemoris: 1, .vastusLateralis: 0.95, .vastusMedialis: 0.95],
            brand: .hammerStrength, signature: true
        ),
        seed(
            "hammer-strength-ground-base-jammer", "Hammer Strength Ground Base jammer", ["jammer press"], "plate-loaded machine", .plateLoaded, .total,
            [.frontDelts: 1, .upperChest: 0.8, .tricepsLateralHead: 0.5, .gluteMax: 0.45, .rectusFemoris: 0.4, .rectusAbdominis: 0.35],
            brand: .hammerStrength, signature: true
        ),
        seed(
            "hammer-strength-glute-drive", "Hammer Strength Glute Drive", ["glute drive machine"], "plate-loaded machine", .plateLoaded, .total,
            [.gluteMax: 1, .hamstrings: 0.5, .vastusLateralis: 0.3],
            brand: .hammerStrength, signature: true
        ),
        seed(
            "hammer-strength-plate-loaded-pullover", "Hammer Strength plate-loaded pullover", ["hammer pullover"], "plate-loaded machine", .plateLoaded, .total,
            [.lats: 1, .tricepsLongHead: 0.45, .lowerTraps: 0.35, .rectusAbdominis: 0.25],
            brand: .hammerStrength, signature: true
        ),
        seed(
            "hammer-strength-plate-loaded-lateral-raise", "Hammer Strength plate-loaded lateral raise", ["hammer lateral raise"], "plate-loaded machine", .plateLoaded, .total,
            [.sideDelts: 1, .upperTraps: 0.3, .frontDelts: 0.25],
            brand: .hammerStrength, signature: true
        ),
        seed(
            "hammer-strength-plate-loaded-seated-dip", "Hammer Strength plate-loaded seated dip", ["hammer seated dip"], "plate-loaded machine", .plateLoaded, .total,
            [.tricepsLateralHead: 1, .tricepsMedialHead: 0.85, .tricepsLongHead: 0.7, .lowerChest: 0.55, .frontDelts: 0.3],
            brand: .hammerStrength, signature: true
        ),
        seed(
            "hammer-strength-plate-loaded-seated-biceps", "Hammer Strength plate-loaded seated biceps", ["hammer biceps machine"], "plate-loaded machine", .plateLoaded, .total,
            [.bicepsShortHead: 1, .brachialis: 0.65, .bicepsLongHead: 0.55, .forearms: 0.2],
            brand: .hammerStrength, signature: true
        ),
        seed(
            "hammer-strength-super-squat-press", "Hammer Strength Super Squat press", ["super squat machine"], "plate-loaded machine", .plateLoaded, .total,
            [.vastusLateralis: 1, .vastusMedialis: 0.9, .rectusFemoris: 0.85, .gluteMax: 0.8, .adductors: 0.45],
            brand: .hammerStrength, signature: true
        ),
        seed(
            "hammer-strength-pendulum-x-squat", "Hammer Strength Pendulum-X squat", ["pendulum x"], "plate-loaded machine", .plateLoaded, .total,
            [.vastusLateralis: 1, .vastusMedialis: 0.95, .rectusFemoris: 0.9, .gluteMax: 0.75, .adductors: 0.4],
            brand: .hammerStrength, signature: true
        ),
        seed(
            "hammer-strength-linear-leg-press", "Hammer Strength linear leg press", ["hammer leg press"], "plate-loaded machine", .plateLoaded, .total,
            [.vastusLateralis: 1, .vastusMedialis: 0.9, .rectusFemoris: 0.85, .gluteMax: 0.7, .adductors: 0.4],
            brand: .hammerStrength, signature: true
        ),
        seed(
            "hammer-strength-plate-loaded-hack-squat", "Hammer Strength plate-loaded hack squat", ["hammer hack squat"], "plate-loaded machine", .plateLoaded, .total,
            [.vastusLateralis: 1, .vastusMedialis: 0.95, .rectusFemoris: 0.9, .gluteMax: 0.6, .adductors: 0.4],
            brand: .hammerStrength, signature: true
        ),
        seed(
            "hammer-strength-plate-loaded-belt-squat", "Hammer Strength plate-loaded belt squat", ["hammer belt squat"], "plate-loaded machine", .plateLoaded, .total,
            [.vastusLateralis: 1, .rectusFemoris: 0.85, .vastusMedialis: 0.9, .gluteMax: 0.8, .adductors: 0.45],
            brand: .hammerStrength, signature: true
        ),
        seed(
            "hammer-strength-seated-standing-shrug", "Hammer Strength seated / standing shrug", ["hammer shrug"], "plate-loaded machine", .plateLoaded, .total,
            [.upperTraps: 1, .middleTraps: 0.45, .lowerTraps: 0.2],
            brand: .hammerStrength, signature: true
        ),
        seed(
            "hammer-strength-abdominal-oblique-crunch", "Hammer Strength abdominal / oblique crunch", ["hammer ab crunch"], "plate-loaded machine", .plateLoaded, .total,
            [.rectusAbdominis: 1, .obliques: 0.6],
            brand: .hammerStrength, signature: true
        ),
        seed(
            "hammer-strength-plate-loaded-gripper", "Hammer Strength plate-loaded gripper", ["gripper machine"], "plate-loaded machine", .plateLoaded, .total,
            [.forearms: 1],
            brand: .hammerStrength, signature: true
        ),
        seed(
            "hammer-strength-plate-loaded-tibia-dorsi-flexion", "Hammer Strength tibia dorsi-flexion", ["tib dorsi flexion machine"], "plate-loaded machine", .plateLoaded, .total,
            [.tibialisAnterior: 1],
            brand: .hammerStrength, signature: true
        ),

        // Life Fitness Insignia. Dual Axis arms move independently on a free path, which
        // is a different movement from a fixed converging press.
        seed(
            "life-fitness-dual-axis-chest-press", "Life Fitness Dual Axis chest press", ["dual axis chest press"], "machine", .selectorized, .total,
            [.middleChest: 1, .lowerChest: 0.5, .upperChest: 0.45, .frontDelts: 0.55, .tricepsLateralHead: 0.5, .tricepsLongHead: 0.35],
            brand: .lifeFitness, signature: true
        ),
        seed(
            "life-fitness-dual-axis-pulldown", "Life Fitness Dual Axis pulldown", ["dual axis pulldown"], "machine", .selectorized, .total,
            [.lats: 1, .lowerTraps: 0.5, .rhomboids: 0.45, .bicepsLongHead: 0.5, .bicepsShortHead: 0.45, .brachialis: 0.4],
            brand: .lifeFitness, signature: true
        ),
        seed(
            "life-fitness-arc-leg-press", "Life Fitness Arc leg press", ["insignia arc leg press"], "machine", .selectorized, .total,
            [.vastusLateralis: 1, .vastusMedialis: 0.9, .rectusFemoris: 0.85, .gluteMax: 0.8, .adductors: 0.4],
            brand: .lifeFitness, signature: true
        ),
        seed(
            "life-fitness-glute-bridge", "Life Fitness Insignia glute bridge", ["insignia glute bridge"], "machine", .selectorized, .total,
            [.gluteMax: 1, .hamstrings: 0.5, .vastusLateralis: 0.3],
            brand: .lifeFitness, signature: true
        ),

        // Cybex. The Eagle NX leg press carriage articulates as it travels, which puts
        // the hip through more extension than a straight sled.
        seed(
            "cybex-eagle-nx-leg-press", "Cybex Eagle NX leg press", ["cybex leg press", "eagle leg press"], "machine", .selectorized, .total,
            [.gluteMax: 1, .vastusLateralis: 0.95, .vastusMedialis: 0.85, .rectusFemoris: 0.8, .hamstrings: 0.4, .adductors: 0.4],
            brand: .cybex, signature: true
        ),
        seed(
            "cybex-eagle-nx-arm-extension", "Cybex Eagle NX arm extension", ["cybex arm extension"], "machine", .selectorized, .total,
            [.tricepsLateralHead: 1, .tricepsMedialHead: 0.85, .tricepsLongHead: 0.55],
            brand: .cybex, signature: true
        ),

        // PRIME. SmartCam lets the peak resistance be moved along the range, so the
        // resistance profile is a property of the machine, not just the load.
        seed(
            "prime-evolution-lat-pulldown", "PRIME Evolution lat pulldown", ["prime pulldown", "smartcam pulldown"], "machine", .selectorized, .total,
            [.lats: 1, .lowerTraps: 0.5, .rhomboids: 0.45, .bicepsLongHead: 0.5, .bicepsShortHead: 0.45, .brachialis: 0.4],
            brand: .prime, signature: true
        ),
        seed(
            "prime-plate-loaded-extreme-row", "PRIME plate-loaded Extreme row", ["prime extreme row"], "plate-loaded machine", .plateLoaded, .perHand,
            [.lats: 1, .rhomboids: 0.85, .middleTraps: 0.7, .rearDelts: 0.5, .bicepsLongHead: 0.45],
            brand: .prime, signature: true
        ),
        seed(
            "prime-plate-loaded-pendulum-squat", "PRIME plate-loaded pendulum squat", ["prime pendulum squat"], "plate-loaded machine", .plateLoaded, .total,
            [.vastusLateralis: 1, .vastusMedialis: 0.95, .rectusFemoris: 0.95, .gluteMax: 0.7, .adductors: 0.4],
            brand: .prime, signature: true
        ),
        seed(
            "prime-hybrid-multi-hip", "PRIME Hybrid multi-hip", ["prime multi hip"], "machine", .selectorized, .total,
            [.gluteMax: 1, .gluteMed: 0.7, .abductors: 0.6, .adductors: 0.5, .hamstrings: 0.4, .rectusFemoris: 0.35],
            brand: .prime, signature: true
        ),

        // Arsenal Strength Reloaded.
        seed(
            "arsenal-reloaded-iso-incline-press", "Arsenal Reloaded ISO incline press", ["arsenal iso incline"], "plate-loaded machine", .plateLoaded, .perHand,
            [.upperChest: 1, .middleChest: 0.55, .frontDelts: 0.7, .tricepsLateralHead: 0.5, .tricepsLongHead: 0.35],
            brand: .arsenal, signature: true
        ),
        seed(
            "arsenal-reloaded-triceps-kickback-dip", "Arsenal Reloaded triceps kickback / dip", ["arsenal kickback machine"], "plate-loaded machine", .plateLoaded, .total,
            [.tricepsLongHead: 1, .tricepsLateralHead: 0.85, .tricepsMedialHead: 0.7, .lowerChest: 0.3],
            brand: .arsenal, signature: true
        ),
        // The Arsenal Multi-Flex is deliberately absent: it is a multi-station frame, so
        // which muscles a set trains depends on the station, and one muscle map would be
        // wrong for most of them.

        // Atlantis.
        seed(
            "atlantis-pivot-press", "Atlantis pivot press", ["atlantis pivot chest press"], "plate-loaded machine", .plateLoaded, .perHand,
            [.middleChest: 1, .upperChest: 0.55, .lowerChest: 0.45, .frontDelts: 0.5, .tricepsLateralHead: 0.45],
            brand: .atlantis, signature: true
        ),

        // Panatta.
        seed(
            "panatta-fit-evo-sissy-squat", "Panatta Fit Evo sissy squat", ["panatta sissy squat"], "plate-loaded machine", .plateLoaded, .total,
            [.rectusFemoris: 1, .vastusMedialis: 0.85, .vastusLateralis: 0.8],
            brand: .panatta, signature: true
        ),

        // Rogue. The LP-2 is a 1:1 plate-loaded pulldown, so the number on it is a real
        // plate weight rather than a stack reading.
        seed(
            "rogue-lp-2-lat-pulldown", "Rogue LP-2 lat pulldown", ["rogue lat pulldown", "lp 2 pulldown"], "plate-loaded machine", .plateLoaded, .total,
            [.lats: 1, .lowerTraps: 0.5, .rhomboids: 0.45, .bicepsLongHead: 0.5, .bicepsShortHead: 0.45, .brachialis: 0.4],
            brand: .rogue, signature: true
        ),
        seed(
            "rogue-rhino-belt-squat", "Rogue Rhino belt squat", ["rhino belt squat"], "plate-loaded machine", .plateLoaded, .total,
            [.vastusLateralis: 1, .rectusFemoris: 0.85, .vastusMedialis: 0.9, .gluteMax: 0.8, .adductors: 0.45],
            brand: .rogue, signature: true
        ),
    ]
}
