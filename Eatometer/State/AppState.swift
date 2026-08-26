import Foundation

/// Role: the single Redux tree. Views read slices through selectors; they never mutate this directly.
struct AppState: Equatable, Sendable {
    var onboardingComplete: Bool
    var calibration: DialCalibration
    var specimens: [String: SpecimenRecord]
    var readings: [GaugeReading]
    var watchlist: [WatchlistMark]
    var selectedDayKey: String
    var clockDayKey: String
    var selectedSegment: InstrumentSegment
    var logShowsHorizon: Bool
    var analyticsWindowDays: Int
    var search: SearchDialState
    var scan: ScanDialState
    var measurement: MeasurementDraft?
    var highlightedReadingID: UUID?
    var persistenceNotice: String?
    var isResetting: Bool
    var restoreSegmentRaw: String?

    static func launch(now: Date = Date(), calendar: Calendar = .current) -> AppState {
        let today = DayKey.today(calendar: calendar, now: now)
        return AppState(
            onboardingComplete: false,
            calibration: .factory,
            specimens: [:],
            readings: [],
            watchlist: [],
            selectedDayKey: today,
            clockDayKey: today,
            selectedSegment: .reading,
            logShowsHorizon: false,
            analyticsWindowDays: 7,
            search: SearchDialState(),
            scan: ScanDialState(),
            measurement: nil,
            highlightedReadingID: nil,
            persistenceNotice: nil,
            isResetting: false,
            restoreSegmentRaw: nil
        )
    }
}
