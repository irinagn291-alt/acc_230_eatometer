import Foundation

/// Role: product specimen held in the catalog drum. Optional macros stay optional.
struct SpecimenRecord: Equatable, Sendable, Hashable, Identifiable {
    var id: String { barcode }
    var barcode: String
    var name: String
    var brand: String
    var kcal100: Double?
    var protein100: Double?
    var carbs100: Double?
    var fat100: Double?
    var imageURL: String?
    var shelfAsset: String?
    var refreshedAt: Date
}

/// Role: a single gauge stroke — one portion assigned to a slot and day.
struct GaugeReading: Equatable, Sendable, Hashable, Identifiable {
    var id: UUID
    var barcode: String
    var specimenName: String
    var brand: String
    var grams: Double
    var slot: DialSlot
    var dayKey: String
    var isEaten: Bool
    var createdAt: Date
    var kcal100: Double?
    var protein100: Double?
    var carbs100: Double?
    var fat100: Double?
    var imageURL: String?
    var shelfAsset: String?
}

/// Role: daily energy and macro dials. Macro nil means the needle is unset.
struct DialCalibration: Equatable, Sendable {
    var kcal: Double
    var protein: Double?
    var carbs: Double?
    var fat: Double?

    static let factory = DialCalibration(kcal: 2200, protein: 140, carbs: 220, fat: 70)
}

/// Role: a specimen parked on the watchlist.
struct WatchlistMark: Equatable, Sendable, Hashable, Identifiable {
    var id: String { barcode }
    var barcode: String
    var name: String
    var brand: String
    var addedAt: Date
    var kcal100: Double?
    var imageURL: String?
    var shelfAsset: String?
}

enum WatchlistPolicy {
    static func integrating(existing: [WatchlistMark], incoming: WatchlistMark) -> [WatchlistMark] {
        if let index = existing.firstIndex(where: { $0.barcode == incoming.barcode }) {
            var next = existing
            next[index] = incoming
            return next
        }
        return existing + [incoming]
    }

    static func contains(_ marks: [WatchlistMark], barcode: String) -> Bool {
        marks.contains { $0.barcode == barcode }
    }
}

enum InstrumentSegment: String, Equatable, Sendable, CaseIterable {
    case reading
    case log
    case analytics
    case targets

    var title: String {
        switch self {
        case .reading: "Reading"
        case .log: "Log"
        case .analytics: "Analytics"
        case .targets: "Targets"
        }
    }
}
