import Foundation
import Testing
@testable import Health_Tracker

@MainActor
struct ExerciseCatalogHistoryTests {
    /// Every id that existed before the catalog was expanded. Logged workouts reference
    /// these strings, so losing one silently orphans real training history.
    private let legacyIDs = [
        "machine-chest-fly",
        "lat-pulldown",
        "pull-up",
        "seated-machine-row",
        "incline-machine-chest-press",
        "neutral-grip-machine-shoulder-press",
        "rope-triceps-pushdown",
        "straight-bar-triceps-pushdown",
        "incline-dumbbell-curl",
        "dumbbell-wrist-curl",
        "reverse-dumbbell-wrist-curl",
        "single-arm-cable-lateral-raise",
        "seated-leg-extension",
        "seated-leg-curl",
        "lying-leg-curl",
        "hip-adductor-machine",
        "hip-abductor-machine",
        "calf-raise",
        "plate-loaded-squat",
        "kneeling-rope-cable-crunch",
        "crunch",
    ]

    @Test func everyPreviouslyExistingExerciseStillResolves() {
        let catalog = ExerciseCatalog(cacheURL: temporaryURL("legacy-ids"))

        for id in legacyIDs {
            #expect(catalog.exercise(id: id) != nil, "lost exercise id \(id)")
        }
    }

    @Test func everyStarterExerciseStillResolves() {
        let catalog = ExerciseCatalog(cacheURL: temporaryURL("legacy-defaults"))

        for kind in WorkoutKind.allCases {
            for id in catalog.defaultExerciseIDs(for: kind) {
                #expect(catalog.exercise(id: id) != nil, "\(kind) starts with missing \(id)")
            }
        }
    }

    @Test func legacyExercisesKeptTheirHandTunedMuscleMaps() throws {
        let catalog = ExerciseCatalog(cacheURL: temporaryURL("legacy-muscles"))
        let fly = try #require(catalog.exercise(id: "machine-chest-fly"))
        let squat = try #require(catalog.exercise(id: "plate-loaded-squat"))

        #expect(fly.muscles.contains { $0.muscle == .middleChest && $0.intensity == 1 })
        #expect(fly.muscles.contains { $0.muscle == .upperChest && $0.intensity == 0.55 })
        #expect(fly.muscles.contains { $0.muscle == .lowerChest && $0.intensity == 0.45 })
        #expect(fly.muscles.contains { $0.muscle == .frontDelts && $0.intensity == 0.3 })
        #expect(squat.muscles.contains { $0.muscle == .vastusLateralis && $0.intensity == 1 })
        #expect(squat.muscles.contains { $0.muscle == .gluteMax && $0.intensity == 0.8 })
    }

    @Test func unknownIdentifiersStillResolveToNothing() {
        let catalog = ExerciseCatalog(cacheURL: temporaryURL("unknown-ids"))

        #expect(catalog.exercise(id: "not-a-real-exercise") == nil)
        #expect(catalog.exercise(id: "not-a-real-exercise@cybex") == nil)
        #expect(catalog.exercise(id: "lat-pulldown@not-a-real-brand") == nil)
        #expect(catalog.exercise(id: "") == nil)
    }
}

@MainActor
struct ExerciseCatalogBrandTests {
    @Test func brandIsAnAttributeRatherThanARowPerMaker() {
        let catalog = ExerciseCatalog(cacheURL: temporaryURL("brand-rows"))
        let pulldowns = catalog.exercises.filter { $0.baseID == "lat-pulldown" }

        // One movement, one row. Fourteen makers must not become fourteen rows.
        #expect(pulldowns.count == 1)
        #expect(catalog.exercises.allSatisfy { !$0.id.contains("@") })
    }

    @Test func choosingAMakerKeepsItsOwnWeightHistory() throws {
        let catalog = ExerciseCatalog(cacheURL: temporaryURL("brand-history"))
        let cybex = catalog.qualifiedID(for: "lat-pulldown", brand: .cybex)
        let hammer = catalog.qualifiedID(for: "lat-pulldown", brand: .hammerStrength)

        // 150 on one maker's stack is not 150 on another's, so the ids differ and the
        // store, which keys history by exercise id, cannot average them together.
        #expect(cybex != hammer)
        #expect(cybex != "lat-pulldown")

        let resolved = try #require(catalog.exercise(id: cybex))
        let base = try #require(catalog.exercise(id: "lat-pulldown"))
        #expect(resolved.brand == .cybex)
        #expect(resolved.baseID == "lat-pulldown")
        #expect(resolved.name.contains("Cybex"))
        #expect(resolved.muscles == base.muscles)
        #expect(resolved.loadMode == base.loadMode)
    }

    @Test func aLoggedSetRemembersWhichMakerItWasDoneOn() {
        let logged = LoggedExercise(
            exerciseID: "seated-machine-row@technogym",
            sets: [LoggedSet(weight: 150, reps: 8, isComplete: true)]
        )
        let unbranded = LoggedExercise(
            exerciseID: "seated-machine-row",
            sets: [LoggedSet(weight: 150, reps: 8, isComplete: true)]
        )

        #expect(logged.brand == .technogym)
        #expect(logged.baseExerciseID == "seated-machine-row")
        #expect(unbranded.brand == nil)
        #expect(unbranded.baseExerciseID == "seated-machine-row")
    }

    @Test func freeWeightsAndBodyweightOfferNoBrand() {
        let catalog = ExerciseCatalog(cacheURL: temporaryURL("brandless"))

        // A dumbbell curl is a dumbbell curl. Recording the maker here would fragment
        // history for a load that does not change.
        for id in ["incline-dumbbell-curl", "barbell-bench-press", "pull-up", "back-squat"] {
            #expect(catalog.brands(for: id).isEmpty, "\(id) should not ask for a brand")
        }
        #expect(catalog.qualifiedID(for: "pull-up", brand: .rogue) == "pull-up")
    }

    @Test func machinesCablesAndSmithBarsOfferBrands() {
        let catalog = ExerciseCatalog(cacheURL: temporaryURL("brandful"))

        for id in ["lat-pulldown", "seated-machine-row", "leg-press", "smith-machine-squat"] {
            #expect(catalog.brands(for: id).count >= 2, "\(id) should offer brands")
        }
    }

    @Test func brandListsOnlyContainMakersOfThatHardware() {
        let catalog = ExerciseCatalog(cacheURL: temporaryURL("brand-fit"))

        // Rogue and Eleiko build bars, racks, plate-loaded levers, and cable towers,
        // not pin-loaded stack machines.
        #expect(!catalog.brands(for: "seated-machine-row").contains(.rogue))
        #expect(!catalog.brands(for: "seated-machine-row").contains(.eleiko))
        #expect(catalog.brands(for: "reverse-hyperextension").contains(.rogue))
        #expect(catalog.brands(for: "leg-press").contains(.rogue))
        // PRIME builds machines, not Smith bars.
        #expect(!catalog.brands(for: "smith-machine-squat").contains(.prime))
        #expect(catalog.brands(for: "smith-machine-squat").contains(.matrix))
        #expect(catalog.brands(for: "seated-machine-row").contains(.lifeFitness))
        #expect(catalog.brands(for: "lat-pulldown").contains(.lifeFitness))
    }

    @Test func makerSpecificMachinesCannotBeRebranded() throws {
        let catalog = ExerciseCatalog(cacheURL: temporaryURL("signature"))
        let isoRow = try #require(catalog.exercise(id: "hammer-strength-iso-lateral-row"))

        // The maker is the movement here, so it is one row that already knows its brand.
        #expect(isoRow.brand == .hammerStrength)
        #expect(isoRow.isBrandSignature)
        #expect(!isoRow.acceptsBrand)
        #expect(catalog.brands(for: "hammer-strength-iso-lateral-row").isEmpty)
        #expect(
            catalog.qualifiedID(for: "hammer-strength-iso-lateral-row", brand: .cybex)
                == "hammer-strength-iso-lateral-row"
        )
    }

    @Test func everySignatureMachineDeclaresItsMaker() {
        let catalog = ExerciseCatalog(cacheURL: temporaryURL("signature-brands"))
        let signatures = catalog.exercises.filter(\.isBrandSignature)

        #expect(signatures.count >= 20)
        #expect(signatures.allSatisfy { $0.brand != nil })
        #expect(signatures.allSatisfy { !$0.acceptsBrand })
    }

    @Test func brandSuffixParsingRoundTrips() {
        for brand in EquipmentBrand.allCases {
            let id = ExerciseDefinition.qualifiedID(base: "lat-pulldown", brand: brand)
            let parts = ExerciseDefinition.components(of: id)
            #expect(parts.base == "lat-pulldown")
            #expect(parts.brand == brand)
        }
        #expect(ExerciseDefinition.components(of: "lat-pulldown").brand == nil)
        #expect(ExerciseDefinition.components(of: "lat-pulldown@bogus").base == "lat-pulldown@bogus")
    }

    @Test func starterWeightsSurviveABrandChoice() {
        let catalog = ExerciseCatalog(cacheURL: temporaryURL("brand-defaults"))

        #expect(catalog.defaultSets(for: "machine-chest-fly@precor")[0].weight == 235)
        #expect(catalog.defaultSets(for: "crunch")[0].reps == 12)
    }
}

@MainActor
struct ExerciseCatalogSearchTests {
    @Test func searchingAMovementFindsTheGenericMovementFirst() throws {
        let catalog = ExerciseCatalog(cacheURL: temporaryURL("search-generic"))

        let pulldown = catalog.search("lat pulldown")
        #expect(pulldown.first?.id == "lat-pulldown")

        let row = try #require(catalog.search("row").first)
        #expect(!row.isBrandSignature, "a maker-specific row outranked every generic row")
    }

    @Test func makerSpecificMachinesDoNotDrownTheResults() {
        let catalog = ExerciseCatalog(cacheURL: temporaryURL("search-flood"))

        for query in ["row", "pulldown", "press", "leg curl", "squat"] {
            let top = catalog.search(query).prefix(10)
            let signatures = top.filter(\.isBrandSignature).count
            #expect(signatures <= 3, "\"\(query)\" returned \(signatures) maker rows in its top 10")
        }
    }

    @Test func anExactNameBeatsALongerNameThatContainsIt() {
        let catalog = ExerciseCatalog(cacheURL: temporaryURL("search-exact"))

        #expect(catalog.search("crunch").first?.id == "crunch")
        #expect(catalog.search("push-up").first?.id == "push-up")
        #expect(catalog.search("leg press").first?.id == "leg-press")
    }

    @Test func aliasesStillFindTheirExercise() {
        let catalog = ExerciseCatalog(cacheURL: temporaryURL("search-alias"))

        #expect(catalog.search("pec deck").contains { $0.id == "machine-chest-fly" })
        #expect(catalog.search("rdl").contains { $0.id == "romanian-deadlift" })
        #expect(catalog.search("skullcrusher").contains { $0.id == "lying-triceps-extension" })
        #expect(catalog.search("hex bar deadlift").contains { $0.id == "trap-bar-deadlift" })
    }

    @Test func searchingAMakerNameFindsThatMakersMachines() {
        let catalog = ExerciseCatalog(cacheURL: temporaryURL("search-brand"))

        #expect(catalog.search("hammer strength").allSatisfy { $0.brand == .hammerStrength })
        #expect(catalog.search("hammer strength").count >= 10)
    }

    @Test func anEmptyQueryStillReturnsSomethingToTapOn() {
        let catalog = ExerciseCatalog(cacheURL: temporaryURL("search-empty"))

        #expect(catalog.search("").count == 80)
        #expect(catalog.search("   ").count == 80)
    }
}

@MainActor
struct ExerciseCatalogCoverageTests {
    @Test func theBundledLibraryIsUsableWithNoNetwork() {
        // A cache url that will never exist, so this is the offline catalog exactly.
        let catalog = ExerciseCatalog(cacheURL: temporaryURL("offline"))

        #expect(catalog.exercises.count >= 200)
        #expect(catalog.exercises.count(where: { $0.equipmentClass == .selectorized }) >= 30)
        #expect(catalog.exercises.count(where: { $0.equipmentClass == .plateLoaded }) >= 30)
        #expect(catalog.exercises.count(where: { $0.equipmentClass == .cable }) >= 25)
        #expect(catalog.exercises.count(where: { $0.equipmentClass == .smith }) >= 5)
        #expect(catalog.exercises.count(where: { $0.equipmentClass == .barbell }) >= 25)
        #expect(catalog.exercises.count(where: { $0.equipmentClass == .dumbbell }) >= 25)
        #expect(catalog.exercises.count(where: { $0.equipmentClass == .bodyweight }) >= 10)
    }

    @Test func everyMuscleGroupInTheAnatomyViewIsReachable() {
        let catalog = ExerciseCatalog(cacheURL: temporaryURL("anatomy"))
        let covered = Set(catalog.exercises.flatMap { $0.muscles.map(\.muscle) })

        for muscle in MuscleGroup.allCases {
            #expect(covered.contains(muscle), "nothing in the catalog trains \(muscle.rawValue)")
        }
    }

    @Test func bundledExercisesAreWellFormed() {
        let catalog = ExerciseCatalog(cacheURL: temporaryURL("well-formed"))
        let bundled = ExerciseCatalog.seedExercises

        #expect(Set(bundled.map(\.id)).count == bundled.count, "duplicate seed id")
        for exercise in bundled {
            #expect(!exercise.id.contains("@"), "\(exercise.id) collides with the brand suffix")
            #expect(!exercise.name.isEmpty)
            #expect(!exercise.muscles.isEmpty, "\(exercise.id) has no muscle mapping")
            #expect(
                exercise.muscles.contains { $0.intensity == 1 },
                "\(exercise.id) has no primary muscle at full intensity"
            )
            #expect(
                exercise.muscles.allSatisfy { $0.intensity > 0 && $0.intensity <= 1 },
                "\(exercise.id) has an out-of-range intensity"
            )
            #expect(
                Set(exercise.muscles.map(\.muscle)).count == exercise.muscles.count,
                "\(exercise.id) lists a muscle twice"
            )
        }
        #expect(catalog.exercises.count >= bundled.count)
    }

    @Test func heavyMovementsUseIndividualHeadsRatherThanGenericGroups() {
        let catalog = ExerciseCatalog(cacheURL: temporaryURL("heads-detail"))
        let bundled = ExerciseCatalog.seedExercises

        // The anatomy view needs heads, not "triceps". Anything the catalog ships must
        // name the individual heads when it trains them at all.
        let triceps: Set<MuscleGroup> = [.tricepsLongHead, .tricepsLateralHead, .tricepsMedialHead]
        let biceps: Set<MuscleGroup> = [.bicepsLongHead, .bicepsShortHead, .brachialis]
        let quads: Set<MuscleGroup> = [.rectusFemoris, .vastusLateralis, .vastusMedialis]

        for name in ["Close-grip bench press", "Machine triceps extension", "Lying triceps extension"] {
            let exercise = bundled.first { $0.name == name }
            let worked = Set(exercise?.muscles.map(\.muscle) ?? [])
            #expect(worked.intersection(triceps).count >= 2, "\(name) is too coarse")
        }
        for name in ["Barbell curl", "Machine preacher curl", "Hammer curl"] {
            let exercise = bundled.first { $0.name == name }
            let worked = Set(exercise?.muscles.map(\.muscle) ?? [])
            #expect(worked.intersection(biceps).count >= 2, "\(name) is too coarse")
        }
        for name in ["Leg press", "Hack squat machine", "Back squat"] {
            let exercise = bundled.first { $0.name == name }
            let worked = Set(exercise?.muscles.map(\.muscle) ?? [])
            #expect(worked.intersection(quads).count >= 2, "\(name) is too coarse")
        }
        _ = catalog
    }

    @Test func strapsKeepIncidentalForearmWorkOutOfEveryPull() {
        let bundled = ExerciseCatalog.seedExercises
        let backMuscles: Set<MuscleGroup> = [.lats, .rhomboids, .middleTraps, .lowerTraps, .upperTraps]

        // He straps in for heavy back work. Crediting forearms on every row would light
        // up the anatomy view for work that is not happening.
        for exercise in bundled {
            let worked = Set(exercise.muscles.map(\.muscle))
            guard !worked.isDisjoint(with: backMuscles) else { continue }
            guard exercise.id != "farmers-carry" else { continue }
            #expect(
                !worked.contains(.forearms),
                "\(exercise.id) credits forearms on a pulling movement"
            )
        }
    }

    @Test func importedExercisesNeverShadowACuratedOne() throws {
        let cache = temporaryURL("import-dedupe")
        let remote = """
        [
          {"id":"Lat_Pulldown","name":"Lat Pulldown","equipment":"cable",
           "primaryMuscles":["lats"],"secondaryMuscles":["biceps"],"category":"strength"},
          {"id":"Pullups","name":"Pullups","equipment":"body only",
           "primaryMuscles":["lats"],"secondaryMuscles":["biceps"],"category":"strength"},
          {"id":"Pec_Deck","name":"Pec Deck","equipment":"machine",
           "primaryMuscles":["chest"],"secondaryMuscles":["shoulders"],"category":"strength"},
          {"id":"Sledgehammer_Swings","name":"Sledgehammer Swings","equipment":"other",
           "primaryMuscles":["shoulders"],"secondaryMuscles":["forearms"],"category":"strength"}
        ]
        """
        try Data(remote.utf8).write(to: cache)
        let catalog = ExerciseCatalog(cacheURL: cache)

        // "Lat Pulldown" matches a curated name and "Pec Deck" matches a curated alias,
        // so neither should appear a second time. Only the genuinely new row is added.
        #expect(catalog.exercises.filter { $0.name.lowercased() == "lat pulldown" }.count == 1)
        #expect(try #require(catalog.exercise(id: "lat-pulldown")).muscles.count > 3)
        #expect(!catalog.exercises.contains { $0.name == "Pec Deck" })
        #expect(!catalog.exercises.contains { $0.name == "Pullups" })
        #expect(catalog.exercises.contains { $0.name == "Sledgehammer Swings" })
    }

    @Test func importedMachinesStillGetABrandChoice() throws {
        let cache = temporaryURL("import-brands")
        let remote = """
        [
          {"id":"Weird_Machine_Row","name":"Weird Machine Row","equipment":"machine",
           "primaryMuscles":["middle back"],"secondaryMuscles":["biceps"],"category":"strength"},
          {"id":"Weird_Barbell_Lift","name":"Weird Barbell Lift","equipment":"barbell",
           "primaryMuscles":["quadriceps"],"secondaryMuscles":["glutes"],"category":"strength"}
        ]
        """
        try Data(remote.utf8).write(to: cache)
        let catalog = ExerciseCatalog(cacheURL: cache)
        let machine = try #require(catalog.exercises.first { $0.name == "Weird Machine Row" })
        let barbell = try #require(catalog.exercises.first { $0.name == "Weird Barbell Lift" })

        #expect(!catalog.brands(for: machine.id).isEmpty)
        #expect(catalog.brands(for: barbell.id).isEmpty)
    }

    @Test func cardioAndStretchingStayOutOfTheLiftingCatalog() throws {
        let cache = temporaryURL("import-filter")
        let remote = """
        [
          {"id":"Running","name":"Treadmill Running","equipment":"machine",
           "primaryMuscles":["quadriceps"],"secondaryMuscles":[],"category":"cardio"},
          {"id":"Hamstring_Stretch","name":"Seated Hamstring Stretch","equipment":"body only",
           "primaryMuscles":["hamstrings"],"secondaryMuscles":[],"category":"stretching"}
        ]
        """
        try Data(remote.utf8).write(to: cache)
        let catalog = ExerciseCatalog(cacheURL: cache)

        #expect(!catalog.exercises.contains { $0.name == "Treadmill Running" })
        #expect(!catalog.exercises.contains { $0.name == "Seated Hamstring Stretch" })
    }

    @Test func definitionsWrittenBeforeBrandsExistedStillDecode() throws {
        let legacy = """
        {"id":"machine-chest-fly","name":"Machine chest fly","aliases":["pec deck"],
         "equipment":"machine","loadMode":"total","weightIncrement":5,
         "muscles":[{"muscle":"middleChest","intensity":1}]}
        """
        let decoded = try JSONDecoder().decode(ExerciseDefinition.self, from: Data(legacy.utf8))

        #expect(decoded.id == "machine-chest-fly")
        #expect(decoded.brand == nil)
        #expect(!decoded.isBrandSignature)
        #expect(decoded.equipmentClass == .other)
    }
}

@MainActor
private func temporaryURL(_ name: String) -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("TodayCatalogTests-\(name)-\(UUID().uuidString).json")
}
