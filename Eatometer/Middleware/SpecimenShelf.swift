import Foundation

/// Role: bundled local drum. Search falls back here so a lookup never dead-ends.
enum SpecimenShelf {
    static let bundled: [SpecimenRecord] = [
        record(
            barcode: "0025484000107",
            name: "Tofu Firm",
            brand: "Shelf Drum",
            kcal: 144, protein: 15.8, carbs: 4.3, fat: 8.7
        ),
        record(
            barcode: "0016229906139",
            name: "Coconut Milk",
            brand: "Shelf Drum",
            kcal: 230, protein: 2.3, carbs: 5.5, fat: 23.8
        ),
        record(
            barcode: "4046000000008",
            name: "Avocado",
            brand: "Shelf Drum",
            kcal: 160, protein: 2.0, carbs: 8.5, fat: 14.7
        ),
        record(
            barcode: "0041303001943",
            name: "Kidney Beans",
            brand: "Shelf Drum",
            kcal: 127, protein: 8.7, carbs: 22.8, fat: 0.5
        ),
        record(
            barcode: "0018627103257",
            name: "Granola",
            brand: "Shelf Drum",
            kcal: 471, protein: 10.0, carbs: 64.0, fat: 20.0
        ),
        record(
            barcode: "0073731000144",
            name: "Corn Tortillas",
            brand: "Shelf Drum",
            kcal: 218, protein: 5.7, carbs: 44.6, fat: 2.9
        )
    ]

    static func matches(_ query: String) -> [SpecimenRecord] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if needle.isEmpty { return [] }
        return bundled.filter {
            $0.name.lowercased().contains(needle)
                || $0.brand.lowercased().contains(needle)
                || $0.barcode.contains(needle)
        }
    }

    static func specimen(barcode: String) -> SpecimenRecord? {
        bundled.first { $0.barcode == barcode }
    }

    private static func record(
        barcode: String,
        name: String,
        brand: String,
        kcal: Double,
        protein: Double,
        carbs: Double,
        fat: Double
    ) -> SpecimenRecord {
        SpecimenRecord(
            barcode: barcode,
            name: name,
            brand: brand,
            kcal100: kcal,
            protein100: protein,
            carbs100: carbs,
            fat100: fat,
            imageURL: nil,
            shelfAsset: "etm_ProductPlaceholder",
            refreshedAt: Date(timeIntervalSince1970: 0)
        )
    }
}
