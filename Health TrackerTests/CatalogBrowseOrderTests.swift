import Foundation
import Testing
@testable import Health_Tracker

/// What the picker shows before he types anything.
///
/// Ranked search already sorted imported rows below curated ones, but browsing
/// skipped ranking entirely and took the first eighty of one merged alphabetical
/// list. The screen he actually opened therefore led with "3/4 Sit-Up",
/// "Ab Roller" and "Advanced Kettlebell Windmill" from the imported set, which is
/// the list he called poor, while the hand-mapped catalog was off screen.
@MainActor
struct CatalogBrowseOrderTests {
    /// Names chosen to sort ahead of almost everything curated, which is exactly
    /// how the real imported set behaves.
    private static let importedJSON = """
    [
      {"id":"Aardvark_Press","name":"Aardvark Press","equipment":"barbell",
       "primaryMuscles":["chest"],"secondaryMuscles":["triceps"],"category":"strength"},
      {"id":"Ab_Roller_Thing","name":"Ab Roller Thing","equipment":"other",
       "primaryMuscles":["abdominals"],"secondaryMuscles":[],"category":"strength"},
      {"id":"Aaa_Kettlebell_Windmill","name":"Aaa Kettlebell Windmill","equipment":"kettlebells",
       "primaryMuscles":["abdominals"],"secondaryMuscles":["shoulders"],"category":"strength"}
    ]
    """

    private func catalogWithImports(_ label: String) throws -> ExerciseCatalog {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("BrowseOrder-\(label)-\(UUID().uuidString).json")
        try Self.importedJSON.data(using: .utf8)!.write(to: url)
        return ExerciseCatalog(cacheURL: url)
    }

    @Test func theImportedRowsAreActuallyMergedIn() throws {
        let catalog = try catalogWithImports("merged")

        #expect(catalog.exercises.contains { $0.name == "Aardvark Press" })
        #expect(catalog.exercises.first?.name == "Aaa Kettlebell Windmill")
    }

    /// The fix. Nothing imported appears until every curated row has.
    @Test func browsingLeadsWithTheHandMappedCatalog() throws {
        let catalog = try catalogWithImports("browse")

        let browse = catalog.search("")

        #expect(!browse.isEmpty)
        #expect(browse.allSatisfy { !ExerciseCatalog.isImported($0) })
    }

    @Test func browsingIsStillAlphabeticalWithinTheCuratedRows() throws {
        let catalog = try catalogWithImports("alpha")

        let names = catalog.search("").map(\.name)

        #expect(names == names.sorted { $0.localizedStandardCompare($1) == .orderedAscending })
    }

    /// Curated first must not mean imported never. They still sort in behind.
    @Test func theImportedRowsAreKeptJustPushedBehind() throws {
        let catalog = try catalogWithImports("kept")

        let ordered = catalog.curatedFirst
        let firstImported = try #require(ordered.firstIndex { ExerciseCatalog.isImported($0) })
        let lastCurated = try #require(ordered.lastIndex { !ExerciseCatalog.isImported($0) })

        #expect(lastCurated < firstImported)
        #expect(ordered.count == catalog.exercises.count)
        #expect(Set(ordered.map(\.id)) == Set(catalog.exercises.map(\.id)))
    }

    /// Typing still ranks across the whole catalog, so pushing imports back in
    /// browse must not hide them from search.
    @Test func searchStillReachesTheImportedRows() throws {
        let catalog = try catalogWithImports("search")

        #expect(catalog.search("aardvark").contains { $0.name == "Aardvark Press" })
    }

    @Test func anEmptyQueryStillFillsAScreen() throws {
        let catalog = try catalogWithImports("count")

        #expect(catalog.search("").count == 80)
        #expect(catalog.search("   ").count == 80)
    }

    /// A catalog with no imports at all, which is the offline case, must be
    /// unchanged by any of this.
    @Test func theOfflineCatalogBrowsesExactlyAsBefore() {
        let catalog = ExerciseCatalog(
            cacheURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("BrowseOrder-offline-\(UUID().uuidString).json")
        )

        #expect(catalog.search("").map(\.id) == Array(catalog.exercises.prefix(80)).map(\.id))
    }
}
