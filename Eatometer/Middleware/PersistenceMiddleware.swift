import CoreData
import Foundation

/// Role: FRC callback hop. FRC is not MainActor-isolated; this bridge publishes on the store.
final class LedgerFRCBridge: NSObject, NSFetchedResultsControllerDelegate {
    private let hop: () -> Void

    init(hop: @escaping () -> Void) {
        self.hop = hop
    }

    func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        hop()
    }
}

/// Role: persistence middleware. FRC maps managed objects to value types and hydrates the store.
@MainActor
final class PersistenceMiddleware: NSObject, MeterMiddleware {
    private let stack: DialPersistenceStack
    private var readingsFRC: NSFetchedResultsController<ReadingEntity>?
    private var watchFRC: NSFetchedResultsController<WatchlistEntity>?
    private var frcBridge: LedgerFRCBridge?
    private weak var store: MeterStore?
    private var didSeedShelf = false

    init(stack: DialPersistenceStack) {
        self.stack = stack
        super.init()
    }

    func attach(_ store: MeterStore) {
        self.store = store
    }

    func boot() {
        let bridge = LedgerFRCBridge { [weak self] in
            Task { @MainActor in
                self?.publish()
            }
        }
        frcBridge = bridge
        let today = store?.state.clockDayKey ?? DayKey.today()
        let readings = stack.makeReadingsController(today: today)
        readings.delegate = bridge
        readingsFRC = readings
        try? readings.performFetch()

        let watch = stack.makeWatchController()
        watch.delegate = bridge
        watchFRC = watch
        try? watch.performFetch()

        publish()
        Task { [weak self] in
            await self?.seedShelfIfNeeded()
            await self?.seedDemoIfNeeded()
            self?.restoreFlags()
            self?.applyReviewScreenIfNeeded()
        }
    }

    func enact(_ action: MeterAction, store: MeterStore) {
        switch action {
        case .reading(.commitRequested):
            Task { await commit(store.state) }
        case .reading(.deleteRequested(let id)):
            Task { await deleteReading(id) }
        case .reading(.consume(let id)):
            Task { await consume(id, today: store.state.clockDayKey) }
        case .calibration(.write(let calibration)):
            Task { await persistCalibration(calibration) }
        case .onboarding(.finish(let calibration)):
            UserDefaults.standard.set(true, forKey: "etm.onboarded.v1")
            Task { await persistCalibration(calibration) }
        case .onboarding(.skipWithFactory):
            UserDefaults.standard.set(true, forKey: "etm.onboarded.v1")
            Task { await persistCalibration(.factory) }
        case .catalog(.resolved(let specimen)):
            Task { await persistSpecimen(specimen) }
        case .watchlist(.mark):
            Task { await markWatchlist(store.state) }
        case .watchlist(.drop(let barcode)):
            Task { await dropWatchlist(barcode) }
        case .persistence(.resetRequested):
            Task { await resetAll() }
        case .onboarding(.reopen):
            UserDefaults.standard.set(false, forKey: "etm.onboarded.v1")
        case .navigation(.segment(let segment)):
            UserDefaults.standard.set(segment.rawValue, forKey: "etm.segment")
        default:
            break
        }
    }

    private func publish() {
        guard let store else { return }
        store.dispatch(.persistence(.hydrate(stack.snapshot(today: store.state.clockDayKey))))
    }

    private func commit(_ state: AppState) async {
        guard let draft = state.measurement, let grams = draft.grams, draft.gramsAreLegal else {
            store?.dispatch(.persistence(.notice("The grams field is out of range.")))
            return
        }
        let today = state.clockDayKey
        let slot = DialSlotPolicy.resolved(slot: draft.slot, dayKey: draft.eatenToday ? today : draft.dayKey, today: today)
        let dayKey = draft.eatenToday ? today : draft.dayKey
        let identifier = UUID()
        do {
            try await stack.write { context in
                let specimen = try LedgerWriter.upsertSpecimen(draft.specimen, in: context)
                let entity = ReadingEntity(context: context)
                entity.id = identifier
                entity.grams = grams
                entity.slotRaw = slot.rawValue
                entity.dayKey = dayKey
                entity.isEaten = draft.eatenToday
                entity.createdAt = Date()
                entity.specimen = specimen
            }
            store?.dispatch(.reading(.highlight(identifier)))
            store?.dispatch(.navigation(.reveal(draft.eatenToday ? .reading : .log, horizon: !draft.eatenToday)))
            Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(350))
                self?.store?.dispatch(.reading(.clearHighlight))
            }
        } catch {
            store?.dispatch(.persistence(.notice("The ledger rejected this stroke.")))
        }
    }

    private func deleteReading(_ id: UUID) async {
        do {
            try await stack.write { context in
                let request = ReadingEntity.fetchRequest()
                request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
                request.fetchLimit = 1
                if let entity = try context.fetch(request).first {
                    context.delete(entity)
                }
            }
        } catch {
            store?.dispatch(.persistence(.notice("The ledger could not erase that stroke.")))
        }
    }

    private func consume(_ id: UUID, today: String) async {
        do {
            try await stack.write { context in
                let request = ReadingEntity.fetchRequest()
                request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
                request.fetchLimit = 1
                if let entity = try context.fetch(request).first {
                    entity.isEaten = true
                    entity.dayKey = today
                }
            }
        } catch {
            store?.dispatch(.persistence(.notice("The planned stroke could not be consumed.")))
        }
    }

    private func persistCalibration(_ calibration: DialCalibration) async {
        do {
            try await stack.write { context in
                try LedgerWriter.writeCalibration(calibration, in: context)
            }
        } catch {
            store?.dispatch(.persistence(.notice("The dials could not be written.")))
        }
    }

    private func persistSpecimen(_ record: SpecimenRecord) async {
        do {
            try await stack.write { context in
                _ = try LedgerWriter.upsertSpecimen(record, in: context)
            }
        } catch {
            store?.dispatch(.persistence(.notice("The specimen drum rejected this cache write.")))
        }
    }

    private func markWatchlist(_ state: AppState) async {
        guard let specimen = state.measurement?.specimen else { return }
        do {
            try await stack.write { context in
                let specimenEntity = try LedgerWriter.upsertSpecimen(specimen, in: context)
                let request = WatchlistEntity.fetchRequest()
                request.predicate = NSPredicate(format: "barcode == %@", specimen.barcode)
                request.fetchLimit = 1
                let entity = try context.fetch(request).first ?? WatchlistEntity(context: context)
                entity.barcode = specimen.barcode
                entity.addedAt = Date()
                entity.specimen = specimenEntity
            }
        } catch {
            store?.dispatch(.persistence(.notice("The watchlist could not take that mark.")))
        }
    }

    private func dropWatchlist(_ barcode: String) async {
        do {
            try await stack.write { context in
                let request = WatchlistEntity.fetchRequest()
                request.predicate = NSPredicate(format: "barcode == %@", barcode)
                if let entity = try context.fetch(request).first {
                    context.delete(entity)
                }
            }
        } catch {
            store?.dispatch(.persistence(.notice("The watchlist mark could not be lifted.")))
        }
    }

    private func resetAll() async {
        do {
            try await stack.resetAllData()
            didSeedShelf = false
            await seedShelfIfNeeded()
            store?.dispatch(.persistence(.resetFinished))
            publish()
        } catch {
            store?.dispatch(.persistence(.notice("Reset failed; the drum is still loaded.")))
            store?.dispatch(.persistence(.resetFinished))
        }
    }

    private func seedShelfIfNeeded() async {
        guard !didSeedShelf else { return }
        do {
            try await stack.write { context in
                for record in SpecimenShelf.bundled {
                    _ = try LedgerWriter.upsertSpecimen(record, in: context)
                }
                let request = CalibrationEntity.fetchRequest()
                request.fetchLimit = 1
                if (try context.fetch(request)).isEmpty {
                    try LedgerWriter.writeCalibration(.factory, in: context)
                }
            }
            didSeedShelf = true
            publish()
        } catch {
            store?.dispatch(.persistence(.notice("The local shelf could not be seated.")))
        }
    }

    private func seedDemoIfNeeded() async {
        #if targetEnvironment(simulator)
        let key = "etm.demo.v1"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        let today = DayKey.today()
        do {
            try await stack.write { context in
                func add(barcode: String, grams: Double, slot: DialSlot) throws {
                    guard let specimen = SpecimenShelf.specimen(barcode: barcode) else { return }
                    let entity = ReadingEntity(context: context)
                    entity.id = UUID()
                    entity.grams = grams
                    entity.slotRaw = slot.rawValue
                    entity.dayKey = today
                    entity.isEaten = true
                    entity.createdAt = Date()
                    entity.specimen = try LedgerWriter.upsertSpecimen(specimen, in: context)
                }
                try add(barcode: "0025484000107", grams: 150, slot: .readingI)
                try add(barcode: "4046000000008", grams: 80, slot: .readingII)
                try add(barcode: "0018627103257", grams: 40, slot: .readingIII)
                try add(barcode: "0073731000144", grams: 50, slot: .spotCheck)
            }
            UserDefaults.standard.set(true, forKey: key)
            UserDefaults.standard.set(true, forKey: "etm.onboarded.v1")
            store?.dispatch(.persistence(.onboardingFlag(true)))
            publish()
        } catch {
            store?.dispatch(.persistence(.notice("Demo seed did not seat.")))
        }
        #endif
    }

    private func applyReviewScreenIfNeeded() {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "-ReviewScreen"), index + 1 < args.count else { return }
        switch args[index + 1] {
        case "log": store?.dispatch(.navigation(.segment(.log)))
        case "goals": store?.dispatch(.navigation(.segment(.targets)))
        default: break
        }
    }

    private func restoreFlags() {
        let onboarded = UserDefaults.standard.bool(forKey: "etm.onboarded.v1")
        store?.dispatch(.persistence(.onboardingFlag(onboarded)))
        if let raw = UserDefaults.standard.string(forKey: "etm.segment"),
           let segment = InstrumentSegment(rawValue: raw) {
            store?.dispatch(.navigation(.segment(segment)))
        }
    }
}
