import Foundation

/// Role: pure reducer. The only function that writes AppState. No I/O, no UIKit.
func meterReducer(state: AppState, action: MeterAction) -> AppState {
    var next = state
    switch action {
    case .onboarding(.skipWithFactory):
        next.calibration = .factory
        next.onboardingComplete = true
    case .onboarding(.finish(let calibration)):
        guard calibration.kcal >= 800, calibration.kcal <= 6000 else { return state }
        next.calibration = calibration
        next.onboardingComplete = true
    case .onboarding(.reopen):
        next.onboardingComplete = false

    case .calibration(.write(let calibration)):
        guard calibration.kcal >= 800, calibration.kcal <= 6000 else { return state }
        next.calibration = calibration

    case .reading(.commitRequested):
        guard var draft = next.measurement, draft.gramsAreLegal, !draft.isCommitting else { return state }
        draft.isCommitting = true
        let today = next.clockDayKey
        if !draft.eatenToday {
            draft.slot = DialSlotPolicy.resolved(slot: draft.slot, dayKey: draft.dayKey, today: today)
            if draft.slot != .spotCheck || draft.dayKey == today {
                draft.remappedNote = draft.dayKey > today && state.measurement?.slot == .spotCheck
                    ? "Spot Check is a same-day reading; the needle moved to Reading I."
                    : draft.remappedNote
            }
        } else {
            draft.dayKey = today
        }
        next.measurement = draft

    case .reading(.deleteRequested), .reading(.consume):
        break
    case .reading(.highlight(let id)):
        next.highlightedReadingID = id
    case .reading(.clearHighlight):
        next.highlightedReadingID = nil

    case .catalog(.searchTextChanged(let query)):
        next.search.query = query
        if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            next.search.phase = .idle
            next.search.hits = []
            next.search.notice = nil
        } else {
            next.search.phase = .pending
        }
    case .catalog(.searchSpinner):
        if next.search.phase == .pending {
            next.search.phase = .loading
        }
    case .catalog(.searchFinished(let hits, let notice)):
        next.search.hits = hits
        next.search.notice = notice
        next.search.phase = hits.isEmpty ? .empty : .results
    case .catalog(.searchFailed):
        next.search.phase = .transport
    case .catalog(.searchRetry):
        if !next.search.query.isEmpty {
            next.search.phase = .pending
        }
    case .catalog(.resolveBarcode):
        next.scan.phase = .resolving
    case .catalog(.resolving):
        next.scan.phase = .resolving
    case .catalog(.resolved(let specimen)):
        next.specimens[specimen.barcode] = specimen
        next.scan.phase = .idle
        let today = next.clockDayKey
        next.measurement = MeasurementDraft(
            specimen: specimen,
            gramsText: "100",
            slot: .readingI,
            dayKey: today,
            eatenToday: true,
            isCommitting: false,
            remappedNote: nil
        )
    case .catalog(.resolveMiss):
        next.scan.phase = .miss
    case .catalog(.resolveOffline):
        next.scan.phase = .offline
    case .catalog(.gramsEdited(let text)):
        next.measurement?.gramsText = sanitizedGrams(text)
    case .catalog(.slotPicked(let slot)):
        guard var draft = next.measurement else { return state }
        if !draft.eatenToday {
            draft.slot = DialSlotPolicy.resolved(slot: slot, dayKey: draft.dayKey, today: next.clockDayKey)
            if slot == .spotCheck && draft.dayKey > next.clockDayKey {
                draft.remappedNote = "Spot Check is a same-day reading; the needle moved to Reading I."
            }
        } else {
            draft.slot = slot
            draft.remappedNote = nil
        }
        next.measurement = draft
    case .catalog(.dayPicked(let key)):
        guard var draft = next.measurement else { return state }
        draft.dayKey = key
        draft.eatenToday = key == next.clockDayKey
        if !draft.eatenToday {
            let previous = draft.slot
            draft.slot = DialSlotPolicy.resolved(slot: draft.slot, dayKey: key, today: next.clockDayKey)
            if previous == .spotCheck && draft.slot == .readingI {
                draft.remappedNote = "Spot Check is a same-day reading; the needle moved to Reading I."
            }
        }
        next.measurement = draft
    case .catalog(.eatenToggled(let eaten)):
        guard var draft = next.measurement else { return state }
        draft.eatenToday = eaten
        if eaten {
            draft.dayKey = next.clockDayKey
            draft.remappedNote = nil
        } else if draft.dayKey == next.clockDayKey {
            draft.dayKey = DayKey.shift(next.clockDayKey, days: 1)
            let previous = draft.slot
            draft.slot = DialSlotPolicy.resolved(slot: draft.slot, dayKey: draft.dayKey, today: next.clockDayKey)
            if previous == .spotCheck {
                draft.remappedNote = "Spot Check is a same-day reading; the needle moved to Reading I."
            }
        }
        next.measurement = draft
    case .catalog(.abandonMeasurement):
        next.measurement = nil

    case .watchlist:
        break

    case .navigation(.segment(let segment)):
        next.selectedSegment = segment
    case .navigation(.logHorizon(let horizon)):
        next.logShowsHorizon = horizon
    case .navigation(.analyticsWindow(let days)):
        next.analyticsWindowDays = [7, 30, 90].contains(days) ? days : 7
    case .navigation(.dayShift(let delta)):
        next.selectedDayKey = DayKey.shift(next.selectedDayKey, days: delta)
    case .navigation(.jumpDay(let key)):
        next.selectedDayKey = key
    case .navigation(.reveal(let segment, let horizon)):
        next.selectedSegment = segment
        next.logShowsHorizon = horizon
        next.measurement = nil
    case .navigation(.scanReadout(let text)):
        next.scan.liveReadout = text
    case .navigation(.scanPhase(let phase)):
        next.scan.phase = phase

    case .persistence(.hydrate(let snapshot)):
        next.calibration = snapshot.calibration
        next.specimens = snapshot.specimens
        next.readings = snapshot.readings
        next.watchlist = snapshot.watchlist
        if let notice = snapshot.notice {
            next.persistenceNotice = notice
        }
    case .persistence(.notice(let notice)):
        next.persistenceNotice = notice
    case .persistence(.resetRequested):
        next.isResetting = true
    case .persistence(.resetFinished):
        next.isResetting = false
        next.watchlist = []
        next.readings = []
        next.highlightedReadingID = nil
    case .persistence(.onboardingFlag(let flag)):
        next.onboardingComplete = flag

    case .clock(.calendarShifted):
        let today = DayKey.today()
        if next.selectedDayKey == next.clockDayKey {
            next.selectedDayKey = today
        }
        next.clockDayKey = today
    }
    return next
}

private func sanitizedGrams(_ raw: String) -> String {
    let allowed = CharacterSet(charactersIn: "0123456789,.")
    return String(raw.unicodeScalars.filter { allowed.contains($0) })
}
