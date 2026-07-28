import Combine
import Foundation

/// Remembers which maker's version of a machine was last logged, so a brand is
/// chosen once rather than every session.
///
/// This lives in `UserDefaults` rather than in the training archive on purpose.
/// It is a preference, not a record: the archive already carries the brand
/// inside every logged exercise id, so losing this map costs one tap and no
/// history. Putting it in `StoredTodayData` would mean changing a persisted
/// format that the coach sync and the widget both read.
///
/// Keys are always the *base* movement id, never a qualified one, so
/// `lat-pulldown` has one remembered maker rather than one per maker.
@MainActor
final class BrandPreferences: ObservableObject {
    static let shared = BrandPreferences()

    /// Written when he deliberately picks "No brand", so that choice sticks
    /// instead of being re-overwritten by whatever he picked the session before.
    private static let unbrandedSentinel = ""

    private let defaults: UserDefaults
    private let storageKey: String

    @Published private var brandSlugsByExercise: [String: String]

    init(defaults: UserDefaults = .standard, storageKey: String = "today.brand-by-exercise") {
        self.defaults = defaults
        self.storageKey = storageKey
        brandSlugsByExercise = defaults.dictionary(forKey: storageKey) as? [String: String] ?? [:]
    }

    /// The maker to default to for a movement. `nil` means unbranded, whether
    /// because he chose that or because he has never chosen at all.
    func lastBrand(for exerciseID: String) -> EquipmentBrand? {
        let base = ExerciseDefinition.components(of: exerciseID).base
        guard let slug = brandSlugsByExercise[base], slug != Self.unbrandedSentinel else { return nil }
        return EquipmentBrand(rawValue: slug)
    }

    /// Whether a choice has ever been made, which is the difference between
    /// "he wants this unbranded" and "he has not said".
    func hasChoice(for exerciseID: String) -> Bool {
        brandSlugsByExercise[ExerciseDefinition.components(of: exerciseID).base] != nil
    }

    func remember(_ brand: EquipmentBrand?, for exerciseID: String) {
        let base = ExerciseDefinition.components(of: exerciseID).base
        guard !base.isEmpty else { return }
        brandSlugsByExercise[base] = brand?.rawValue ?? Self.unbrandedSentinel
        defaults.set(brandSlugsByExercise, forKey: storageKey)
    }

    func forget(_ exerciseID: String) {
        brandSlugsByExercise.removeValue(forKey: ExerciseDefinition.components(of: exerciseID).base)
        defaults.set(brandSlugsByExercise, forKey: storageKey)
    }
}
