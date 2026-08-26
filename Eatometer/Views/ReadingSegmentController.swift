import UIKit
import OrderedCollections

enum ReadingItem: Hashable {
    case header
    case energy
    case macros
    case slot(DialSlot)
    case twist
    case empty
}

/// Role: today board. Slots, energy dial, and the analytics teaser.
@MainActor
final class ReadingSegmentController: UIViewController {
    private let store: MeterStore
    private var token: UUID?
    private var collection: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<Int, ReadingItem>!
    private var didAppear = false
    private let energyLabel = UILabel()

    init(store: MeterStore) {
        self.store = store
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { preconditionFailure("Storyboards are not used.") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        collection = UICollectionView(frame: view.bounds, collectionViewLayout: InstrumentLayout.list(estimated: 96))
        collection.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        collection.backgroundColor = .clear
        collection.keyboardDismissMode = .onDrag
        view.addSubview(collection)

        let registration = UICollectionView.CellRegistration<DialCell, ReadingItem> { [weak self] cell, _, item in
            self?.paint(cell, item: item)
        }
        dataSource = UICollectionViewDiffableDataSource(collectionView: collection) { collection, path, item in
            collection.dequeueConfiguredReusableCell(using: registration, for: path, item: item)
        }
        token = store.observe { [weak self] state in
            self?.apply(state)
        }
    }

    private func apply(_ state: AppState) {
        let board = ReadingSelector.board(from: state, dayKey: state.clockDayKey, eaten: true)
        var items = OrderedSet<ReadingItem>()
        items.append(.header)
        items.append(.energy)
        items.append(.macros)
        for slot in ReadingSelector.sectionOrder() {
            items.append(.slot(slot))
        }
        items.append(.twist)
        if board.energy == 0 {
            items.append(.empty)
        }
        var snapshot = NSDiffableDataSourceSnapshot<Int, ReadingItem>()
        snapshot.appendSections([0])
        snapshot.appendItems(Array(items), toSection: 0)
        dataSource.apply(snapshot, animatingDifferences: didAppear && !InstrumentMotion.reduce)
        didAppear = true
        animateEnergy(board.energy)
    }

    private func animateEnergy(_ value: Double) {
        let text = InstrumentFormatters.energy(value)
        if InstrumentMotion.reduce || !didAppear {
            energyLabel.text = text
            return
        }
        UIView.transition(with: energyLabel, duration: InstrumentMotion.duration, options: [.transitionCrossDissolve, InstrumentMotion.options]) {
            self.energyLabel.text = text
        }
    }

    private func paint(_ cell: DialCell, item: ReadingItem) {
        let state = store.state
        let board = ReadingSelector.board(from: state, dayKey: state.clockDayKey, eaten: true)
        switch item {
        case .header:
            var config = FaceCardConfiguration()
            config.artName = "etm_HeaderDecor"
            config.eyebrow = "Today"
            config.title = "Reading drum"
            config.reading = ""
            config.detail = InstrumentFormatters.dayTitle(state.clockDayKey)
            cell.contentConfiguration = config
        case .energy:
            var config = FaceCardConfiguration()
            config.artName = "etm_ControlFace"
            config.eyebrow = "Energy"
            config.title = remainingCopy(board: board, calibration: state.calibration)
            config.reading = InstrumentFormatters.energy(board.energy) + " kcal"
            config.detail = "Target " + InstrumentFormatters.energy(state.calibration.kcal) + " kcal"
            cell.contentConfiguration = config
        case .macros:
            var config = FaceCardConfiguration()
            config.artName = "etm_MacroProtein"
            config.eyebrow = "Macros"
            config.title = macroLine(board.protein, state.calibration.protein, "P")
                + "   " + macroLine(board.carbs, state.calibration.carbs, "C")
                + "   " + macroLine(board.fat, state.calibration.fat, "F")
            config.reading = ""
            config.detail = "Unknown macros stay unknown. Colour is paired with initials."
            cell.contentConfiguration = config
        case .slot(let slot):
            let rows = board.bySlot[slot] ?? []
            var config = FaceCardConfiguration()
            config.artName = slot.assetName
            config.eyebrow = slot.title
            config.title = rows.isEmpty ? "No stroke yet" : rows.map(\.specimenName).joined(separator: ", ")
            config.reading = InstrumentFormatters.energy(board.slotEnergy[slot] ?? 0)
            config.detail = rows.isEmpty ? "Search or scan to take a measurement." : (rows.count == 1 ? "1 specimen" : "\(rows.count) specimens")
            config.highlighted = rows.contains { $0.id == state.highlightedReadingID }
            cell.contentConfiguration = config
        case .twist:
            var config = FaceCardConfiguration()
            config.artName = "etm_TwistHero"
            config.eyebrow = "Analytics"
            config.title = "Deep dive traces"
            config.reading = ""
            config.detail = "7 / 30 / 90 day trends sit on the Analytics segment."
            cell.contentConfiguration = config
        case .empty:
            var config = EmptyDrumConfiguration()
            config.artName = "etm_EmptyLog"
            config.title = "The drum is unmarked."
            config.body = "No energy has been recorded today. Take a measurement from Search or Scan."
            config.actionTitle = "Search the catalog"
            config.onAction = { [weak self] in
                guard let self else { return }
                self.navigationController?.pushViewController(CatalogSearchController(store: self.store), animated: !InstrumentMotion.reduce)
            }
            cell.contentConfiguration = config
        }
    }

    private func remainingCopy(board: DayBoard, calibration: DialCalibration) -> String {
        let remain = ReadingSelector.remainingEnergy(board: board, calibration: calibration)
        if remain < 0 {
            return "Over target by " + InstrumentFormatters.energy(-remain) + " kcal"
        }
        return InstrumentFormatters.energy(remain) + " kcal still on the dial"
    }

    private func macroLine(_ value: Double?, _ target: Double?, _ mark: String) -> String {
        let shown = InstrumentFormatters.macro(value)
        if let target {
            return "\(mark) \(shown)/\(InstrumentFormatters.macro(target))"
        }
        return "\(mark) \(shown) (unset)"
    }
}
