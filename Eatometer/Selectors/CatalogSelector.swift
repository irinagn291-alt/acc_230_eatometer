import Foundation

/// Role: catalog and measurement derived values.
enum CatalogSelector {
    static func alreadyWatched(_ state: AppState, barcode: String) -> Bool {
        WatchlistPolicy.contains(state.watchlist, barcode: barcode)
    }

    static func liveTotals(_ draft: MeasurementDraft) -> (kcal: Double?, protein: Double?, carbs: Double?, fat: Double?) {
        guard let grams = draft.grams, grams > 0 else {
            return (nil, nil, nil, nil)
        }
        return (
            GaugeMaths.scale(draft.specimen.kcal100, grams: grams),
            GaugeMaths.scale(draft.specimen.protein100, grams: grams),
            GaugeMaths.scale(draft.specimen.carbs100, grams: grams),
            GaugeMaths.scale(draft.specimen.fat100, grams: grams)
        )
    }

    static func merge(remote: [SpecimenRecord], local: [SpecimenRecord]) -> [SpecimenRecord] {
        var seen = Set<String>()
        var out: [SpecimenRecord] = []
        for item in remote + local {
            if item.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { continue }
            if seen.insert(item.barcode).inserted {
                out.append(item)
            }
        }
        return out
    }
}
