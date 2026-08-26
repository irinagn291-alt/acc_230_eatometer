import UIKit
import OrderedCollections

enum LogItem: Hashable {
    case ribbon
    case mode
    case slotHead(DialSlot)
    case row(UUID)
    case dayHead(String)
    case empty
}

/// Role: eaten log and 14-day horizon. Deletes confirm. Day switching stays on this segment.
@MainActor
final class LogSegmentController: UIViewController, UICollectionViewDelegate {
    private let store: MeterStore
    private var token: UUID?
    private var collection: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<Int, LogItem>!

    init(store: MeterStore) {
        self.store = store
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { preconditionFailure("Storyboards are not used.") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        collection = UICollectionView(frame: view.bounds, collectionViewLayout: InstrumentLayout.list(estimated: 88))
        collection.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        collection.backgroundColor = .clear
        collection.delegate = self
        view.addSubview(collection)
        let registration = UICollectionView.CellRegistration<DialCell, LogItem> { [weak self] cell, _, item in
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
        var items = OrderedSet<LogItem>()
        items.append(.ribbon)
        items.append(.mode)
        if state.logShowsHorizon {
            let planned = ReadingSelector.horizon(from: state, today: state.clockDayKey)
            if planned.isEmpty {
                items.append(.empty)
            } else {
                var lastDay = ""
                for row in planned {
                    if row.dayKey != lastDay {
                        items.append(.dayHead(row.dayKey))
                        lastDay = row.dayKey
                    }
                    items.append(.row(row.id))
                }
            }
        } else {
            let board = ReadingSelector.board(from: state, dayKey: state.selectedDayKey, eaten: true)
            let rows = DialSlot.allCases.flatMap { board.bySlot[$0] ?? [] }
            if rows.isEmpty {
                items.append(.empty)
            } else {
                for slot in ReadingSelector.sectionOrder() {
                    items.append(.slotHead(slot))
                    for row in board.bySlot[slot] ?? [] {
                        items.append(.row(row.id))
                    }
                }
            }
        }
        var snapshot = NSDiffableDataSourceSnapshot<Int, LogItem>()
        snapshot.appendSections([0])
        snapshot.appendItems(Array(items), toSection: 0)
        dataSource.apply(snapshot, animatingDifferences: !InstrumentMotion.reduce)
    }

    private func paint(_ cell: DialCell, item: LogItem) {
        let state = store.state
        switch item {
        case .ribbon:
            var config = FaceCardConfiguration()
            config.eyebrow = "Day"
            config.title = InstrumentFormatters.dayTitle(state.selectedDayKey)
            config.reading = ""
            config.detail = "Previous and next stay on this segment."
            cell.contentConfiguration = config
            installDayButtons(on: cell)
        case .mode:
            var config = ActionRowConfiguration()
            config.title = state.logShowsHorizon ? "Show recorded strokes" : "Show 14-day horizon"
            config.onTap = { [weak self] in
                self?.store.dispatch(.navigation(.logHorizon(!state.logShowsHorizon)))
            }
            cell.contentConfiguration = config
        case .slotHead(let slot):
            let board = ReadingSelector.board(from: state, dayKey: state.selectedDayKey, eaten: true)
            var config = FaceCardConfiguration()
            config.artName = slot.assetName
            config.eyebrow = slot.title
            config.title = "Subtotal"
            config.reading = InstrumentFormatters.energy(board.slotEnergy[slot] ?? 0)
            let strokes = board.bySlot[slot]?.count ?? 0
            config.detail = strokes == 1 ? "1 stroke" : "\(strokes) strokes"
            cell.contentConfiguration = config
        case .dayHead(let key):
            var config = FaceCardConfiguration()
            config.eyebrow = "Horizon"
            config.title = InstrumentFormatters.dayTitle(key)
            config.reading = ""
            cell.contentConfiguration = config
        case .row(let id):
            guard let row = state.readings.first(where: { $0.id == id }) else { return }
            var config = FaceCardConfiguration()
            config.artName = row.shelfAsset ?? "etm_ProductPlaceholder"
            config.eyebrow = row.slot.title
            config.title = row.specimenName
            config.reading = InstrumentFormatters.energy(GaugeMaths.energy(of: row))
            config.detail = InstrumentFormatters.macro(row.grams) + " g"
            config.highlighted = state.highlightedReadingID == id
            cell.contentConfiguration = config
        case .empty:
            var config = EmptyDrumConfiguration()
            if state.logShowsHorizon {
                config.artName = "etm_EmptyPlan"
                config.title = "The horizon is clear."
                config.body = "No planned strokes in the next 14 days."
            } else {
                config.artName = "etm_EmptyLog"
                config.title = "No strokes on this day."
                config.body = "Search the catalog to take a measurement."
            }
            config.actionTitle = "Search the catalog"
            config.onAction = { [weak self] in
                guard let self else { return }
                self.navigationController?.pushViewController(CatalogSearchController(store: self.store), animated: !InstrumentMotion.reduce)
            }
            cell.contentConfiguration = config
        }
    }

    private func installDayButtons(on cell: DialCell) {
        cell.contentView.viewWithTag(71)?.removeFromSuperview()
        let prev = UIButton(type: .system)
        prev.setTitle("Prev", for: .normal)
        prev.accessibilityLabel = "Previous day"
        prev.addTarget(self, action: #selector(prevDay), for: .touchUpInside)
        let next = UIButton(type: .system)
        next.setTitle("Next", for: .normal)
        next.accessibilityLabel = "Next day"
        next.addTarget(self, action: #selector(nextDay), for: .touchUpInside)
        let row = UIStackView(arrangedSubviews: [prev, next])
        row.tag = 71
        row.axis = .horizontal
        row.spacing = InstrumentSpace.x(2)
        row.distribution = .fillEqually
        cell.contentView.addSubview(row)
        row.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            prev.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
            next.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
            row.trailingAnchor.constraint(equalTo: cell.contentView.trailingAnchor, constant: -InstrumentSpace.x(1)),
            row.bottomAnchor.constraint(equalTo: cell.contentView.bottomAnchor, constant: -InstrumentSpace.x(1)),
            row.widthAnchor.constraint(equalToConstant: 160)
        ])
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard let item = dataSource.itemIdentifier(for: indexPath), case .row(let id) = item else { return }
        let state = store.state
        guard let row = state.readings.first(where: { $0.id == id }) else { return }
        let alert = UIAlertController(title: "Erase this stroke?", message: row.specimenName, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Delete", style: .destructive) { [weak self] _ in
            self?.store.dispatch(.reading(.deleteRequested(id)))
        })
        if !row.isEaten {
            alert.addAction(UIAlertAction(title: "Mark eaten today", style: .default) { [weak self] _ in
                self?.store.dispatch(.reading(.consume(id)))
                InstrumentHaptics.commit()
            })
        }
        present(alert, animated: !InstrumentMotion.reduce)
    }

    @objc private func prevDay() { store.dispatch(.navigation(.dayShift(-1))) }
    @objc private func nextDay() { store.dispatch(.navigation(.dayShift(1))) }
}
