import Foundation

/// Role: instrument slot identity. Spot Check is the snack needle and cannot be planned.
enum DialSlot: String, Equatable, Sendable, CaseIterable, Hashable {
    case readingI
    case readingII
    case readingIII
    case spotCheck

    var title: String {
        switch self {
        case .readingI: "Reading I"
        case .readingII: "Reading II"
        case .readingIII: "Reading III"
        case .spotCheck: "Spot Check"
        }
    }

    var assetName: String {
        switch self {
        case .readingI: "etm_SlotReadingI"
        case .readingII: "etm_SlotReadingIi"
        case .readingIII: "etm_SlotReadingIii"
        case .spotCheck: "etm_SlotSpotCheck"
        }
    }

    var canPlan: Bool { self != .spotCheck }
}

enum DialSlotPolicy {
    /// Remap Spot Check to Reading I (Morning) when the day is ahead of today.
    static func resolved(slot: DialSlot, dayKey: String, today: String) -> DialSlot {
        if slot == .spotCheck && dayKey > today {
            return .readingI
        }
        return slot
    }
}
