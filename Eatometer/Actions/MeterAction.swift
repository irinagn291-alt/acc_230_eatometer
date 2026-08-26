import Foundation

/// Role: every mutation of AppState is a MeterAction. Views dispatch; they never write state.
enum MeterAction: Equatable, Sendable {
    case onboarding(OnboardingAction)
    case calibration(CalibrationAction)
    case reading(ReadingAction)
    case catalog(CatalogAction)
    case watchlist(WatchlistAction)
    case navigation(NavigationAction)
    case persistence(PersistenceAction)
    case clock(ClockAction)
}

enum OnboardingAction: Equatable, Sendable {
    case skipWithFactory
    case finish(DialCalibration)
    case reopen
}

enum CalibrationAction: Equatable, Sendable {
    case write(DialCalibration)
}

enum ReadingAction: Equatable, Sendable {
    case commitRequested
    case deleteRequested(UUID)
    case consume(UUID)
    case highlight(UUID)
    case clearHighlight
}

enum CatalogAction: Equatable, Sendable {
    case searchTextChanged(String)
    case searchSpinner
    case searchFinished([SpecimenRecord], notice: String?)
    case searchFailed
    case searchRetry
    case resolveBarcode(String)
    case resolving
    case resolved(SpecimenRecord)
    case resolveMiss
    case resolveOffline
    case gramsEdited(String)
    case slotPicked(DialSlot)
    case dayPicked(String)
    case eatenToggled(Bool)
    case abandonMeasurement
}

enum WatchlistAction: Equatable, Sendable {
    case mark
    case drop(String)
}

enum NavigationAction: Equatable, Sendable {
    case segment(InstrumentSegment)
    case logHorizon(Bool)
    case analyticsWindow(Int)
    case dayShift(Int)
    case jumpDay(String)
    case reveal(InstrumentSegment, horizon: Bool)
    case scanReadout(String)
    case scanPhase(ScanPhase)
}

enum PersistenceAction: Equatable, Sendable {
    case hydrate(PersistenceSnapshot)
    case notice(String?)
    case resetRequested
    case resetFinished
    case onboardingFlag(Bool)
}

enum ClockAction: Equatable, Sendable {
    case calendarShifted
}
