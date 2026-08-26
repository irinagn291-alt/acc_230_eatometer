import UIKit
import OrderedCollections

enum MeasureItem: Hashable {
    case header, macros, grams, totals, slot(DialSlot), date, wish, commit, note
}

/// Role: fused detail + assign. One push takes the measurement.
@MainActor
final class MeasurementAssignController: UIViewController {
    private let store: MeterStore
    private var token: UUID?
    private var collection: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<Int, MeasureItem>!

    init(store: MeterStore) {
        self.store = store
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { preconditionFailure("Storyboards are not used.") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Take measurement"
        view.backgroundColor = InstrumentPalette.background
        collection = UICollectionView(frame: view.bounds, collectionViewLayout: InstrumentLayout.list(estimated: 96))
        collection.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        collection.backgroundColor = .clear
        collection.keyboardDismissMode = .onDrag
        view.addSubview(collection)
        let backdrop = UIImageView(image: UIImage(named: "etm_CardBackdrop"))
        backdrop.contentMode = .scaleAspectFill
        backdrop.alpha = 0.25
        backdrop.accessibilityElementsHidden = true
        backdrop.clipsToBounds = true
        collection.backgroundView = backdrop
        let tap = UITapGestureRecognizer(target: self, action: #selector(endEdit))
        tap.cancelsTouchesInView = false
        view.addGestureRecognizer(tap)
        let registration = UICollectionView.CellRegistration<DialCell, MeasureItem> { [weak self] cell, _, item in
            self?.paint(cell, item: item)
        }
        dataSource = UICollectionViewDiffableDataSource(collectionView: collection) { collection, path, item in
            collection.dequeueConfiguredReusableCell(using: registration, for: path, item: item)
        }
        token = store.observe { [weak self] _ in
            self?.apply()
        }
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardFrame(_:)),
            name: UIResponder.keyboardWillChangeFrameNotification,
            object: nil
        )
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            title: "Back",
            style: .plain,
            target: self,
            action: #selector(abandon)
        )
        navigationItem.leftBarButtonItem?.accessibilityLabel = "Back"
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if isMovingFromParent {
            NotificationCenter.default.removeObserver(self)
        }
    }

    @objc private func keyboardFrame(_ note: Notification) {
        adjustKeyboard(note)
    }

    private func apply() {
        guard store.state.measurement != nil else { return }
        var items = OrderedSet<MeasureItem>()
        items.append(contentsOf: [.header, .macros, .grams, .totals])
        for slot in DialSlot.allCases { items.append(.slot(slot)) }
        items.append(.date)
        items.append(.wish)
        items.append(.commit)
        if store.state.measurement?.remappedNote != nil {
            items.append(.note)
        }
        var snapshot = NSDiffableDataSourceSnapshot<Int, MeasureItem>()
        snapshot.appendSections([0])
        snapshot.appendItems(Array(items), toSection: 0)
        dataSource.apply(snapshot, animatingDifferences: false)
    }

    private func paint(_ cell: DialCell, item: MeasureItem) {
        guard let draft = store.state.measurement else { return }
        let totals = CatalogSelector.liveTotals(draft)
        switch item {
        case .header:
            var config = FaceCardConfiguration()
            config.artName = draft.specimen.shelfAsset ?? "etm_ProductPlaceholder"
            config.eyebrow = draft.specimen.brand.isEmpty ? draft.specimen.barcode : draft.specimen.brand
            config.title = draft.specimen.name
            config.reading = InstrumentFormatters.unknownEnergy(draft.specimen.kcal100)
            config.detail = draft.specimen.kcal100 == nil ? "Energy is uncalibrated for this specimen." : "kcal / 100 g"
            cell.contentConfiguration = config
        case .macros:
            var config = FaceCardConfiguration()
            config.artName = "etm_MacroCarbs"
            config.eyebrow = "Per 100 g"
            config.title = "P \(InstrumentFormatters.macro(draft.specimen.protein100))   C \(InstrumentFormatters.macro(draft.specimen.carbs100))   F \(InstrumentFormatters.macro(draft.specimen.fat100))"
            config.detail = "Unknown stays unknown."
            cell.contentConfiguration = config
        case .grams:
            var config = FieldConfiguration()
            config.label = "Grams"
            config.text = draft.gramsText
            config.onChange = { [weak self] text in
                self?.store.dispatch(.catalog(.gramsEdited(text)))
            }
            cell.contentConfiguration = config
        case .totals:
            var config = FaceCardConfiguration()
            config.artName = "etm_ControlFace"
            config.eyebrow = "This stroke"
            config.title = "Energy \(InstrumentFormatters.unknownEnergy(totals.kcal))"
            config.reading = InstrumentFormatters.macro(draft.grams) + " g"
            config.detail = "P \(InstrumentFormatters.macro(totals.protein))  C \(InstrumentFormatters.macro(totals.carbs))  F \(InstrumentFormatters.macro(totals.fat))"
            cell.contentConfiguration = config
        case .slot(let slot):
            let future = !draft.eatenToday
            let enabled = !(slot == .spotCheck && future)
            var config = ActionRowConfiguration()
            config.title = slot.title + (draft.slot == slot ? "  · selected" : "")
            config.enabled = enabled
            config.onTap = { [weak self] in
                self?.store.dispatch(.catalog(.slotPicked(slot)))
            }
            cell.contentConfiguration = config
        case .date:
            var config = ActionRowConfiguration()
            config.title = draft.eatenToday
                ? "Eaten today"
                : "Horizon " + InstrumentFormatters.dayTitle(draft.dayKey)
            config.onTap = { [weak self] in
                self?.toggleDate()
            }
            cell.contentConfiguration = config
        case .wish:
            let saved = CatalogSelector.alreadyWatched(store.state, barcode: draft.specimen.barcode)
            var config = ActionRowConfiguration()
            config.title = saved ? "Already on watchlist" : "Add to watchlist"
            config.enabled = !saved
            config.onTap = { [weak self] in
                self?.store.dispatch(.watchlist(.mark))
                InstrumentHaptics.commit()
            }
            cell.contentConfiguration = config
        case .commit:
            var config = ActionRowConfiguration()
            config.title = "Commit measurement"
            config.enabled = draft.gramsAreLegal && !draft.isCommitting
            config.onTap = { [weak self] in
                self?.store.dispatch(.reading(.commitRequested))
            }
            cell.contentConfiguration = config
        case .note:
            var config = FaceCardConfiguration()
            config.eyebrow = "Remap"
            config.title = draft.remappedNote ?? ""
            cell.contentConfiguration = config
        }
    }

    private func toggleDate() {
        guard let draft = store.state.measurement else { return }
        if draft.eatenToday {
            store.dispatch(.catalog(.eatenToggled(false)))
            return
        }
        let next = DayKey.shift(draft.dayKey, days: 1)
        let limit = DayKey.shift(store.state.clockDayKey, days: 14)
        if next <= limit {
            store.dispatch(.catalog(.dayPicked(next)))
        } else {
            store.dispatch(.catalog(.eatenToggled(true)))
        }
    }

    private func adjustKeyboard(_ note: Notification) {
        guard let frame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
        let converted = view.convert(frame, from: nil)
        let overlap = max(0, view.bounds.maxY - converted.minY)
        collection.contentInset.bottom = overlap
        collection.verticalScrollIndicatorInsets.bottom = overlap
    }

    @objc private func endEdit() { view.endEditing(true) }

    @objc private func abandon() {
        store.dispatch(.catalog(.abandonMeasurement))
        navigationController?.popViewController(animated: !InstrumentMotion.reduce)
    }
}
