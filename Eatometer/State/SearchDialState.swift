import Foundation

/// Role: search needle state. Phases keep the catalog lookup honest.
enum SearchPhase: Equatable, Sendable {
    case idle
    case pending
    case loading
    case results
    case empty
    case transport
}

struct SearchDialState: Equatable, Sendable {
    var query: String = ""
    var phase: SearchPhase = .idle
    var hits: [SpecimenRecord] = []
    var notice: String?
}

struct ScanDialState: Equatable, Sendable {
    var liveReadout: String = ""
    var phase: ScanPhase = .idle
    var notice: String?
}

enum ScanPhase: Equatable, Sendable {
    case idle
    case seeking
    case resolving
    case denied
    case restricted
    case noPickup
    case miss
    case offline
}

struct MeasurementDraft: Equatable, Sendable {
    var specimen: SpecimenRecord
    var gramsText: String
    var slot: DialSlot
    var dayKey: String
    var eatenToday: Bool
    var isCommitting: Bool
    var remappedNote: String?

    var grams: Double? {
        GaugeMaths.parseGrams(gramsText)
    }

    var gramsAreLegal: Bool {
        guard let grams else { return false }
        return grams > 0 && grams <= 10_000
    }
}

struct DayBoard: Equatable, Sendable {
    var energy: Double
    var protein: Double?
    var carbs: Double?
    var fat: Double?
    var bySlot: [DialSlot: [GaugeReading]]
    var slotEnergy: [DialSlot: Double]
}

struct DayPoint: Equatable, Sendable, Hashable {
    var dayKey: String
    var kcal: Double
    var protein: Double
    var carbs: Double
    var fat: Double
}

/// Role: derived analytics ledger for the twist screens.
struct AnalyticsLedger: Equatable, Sendable {
    var windowDays: Int
    var daily: [DayPoint]
    var weeklyWindows: [Double]
    var weekdayAverages: [Double]
    var proteinTotal: Double
    var carbsTotal: Double
    var fatTotal: Double
    var adherencePercent: Double
    var bestDay: DayPoint?
    var worstDay: DayPoint?
}

struct PersistenceSnapshot: Equatable, Sendable {
    var calibration: DialCalibration
    var specimens: [String: SpecimenRecord]
    var readings: [GaugeReading]
    var watchlist: [WatchlistMark]
    var notice: String?
}
