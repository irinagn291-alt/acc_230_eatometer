import UIKit
import OrderedCollections

enum WatchItem: Hashable {
    case row(String)
    case empty
}

/// Role: barcode-unique watchlist. Promote dispatches a resolved specimen.
@MainActor
final class WatchlistController: UIViewController, UICollectionViewDelegate {
    private let store: MeterStore
    private var token: UUID?
    private var collection: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<Int, WatchItem>!

    init(store: MeterStore) {
        self.store = store
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { preconditionFailure("Storyboards are not used.") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Watchlist"
        view.backgroundColor = InstrumentPalette.background
        collection = UICollectionView(frame: view.bounds, collectionViewLayout: InstrumentLayout.list(estimated: 88))
        collection.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        collection.backgroundColor = .clear
        collection.delegate = self
        view.addSubview(collection)
        let registration = UICollectionView.CellRegistration<DialCell, WatchItem> { [weak self] cell, _, item in
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
        var items = OrderedSet<WatchItem>()
        if state.watchlist.isEmpty {
            items.append(.empty)
        } else {
            for mark in state.watchlist {
                items.append(.row(mark.barcode))
            }
        }
        var snapshot = NSDiffableDataSourceSnapshot<Int, WatchItem>()
        snapshot.appendSections([0])
        snapshot.appendItems(Array(items), toSection: 0)
        dataSource.apply(snapshot, animatingDifferences: !InstrumentMotion.reduce)
    }

    private func paint(_ cell: DialCell, item: WatchItem) {
        switch item {
        case .empty:
            var config = EmptyDrumConfiguration()
            config.artName = "etm_EmptyWish"
            config.title = "The watchlist is empty."
            config.body = "Park a specimen while taking a measurement."
            config.actionTitle = "Search the catalog"
            config.onAction = { [weak self] in
                guard let self else { return }
                self.navigationController?.pushViewController(CatalogSearchController(store: self.store), animated: !InstrumentMotion.reduce)
            }
            cell.contentConfiguration = config
        case .row(let barcode):
            guard let mark = store.state.watchlist.first(where: { $0.barcode == barcode }) else { return }
            var config = FaceCardConfiguration()
            config.artName = mark.shelfAsset ?? "etm_ProductPlaceholder"
            config.eyebrow = mark.brand
            config.title = mark.name
            config.reading = InstrumentFormatters.unknownEnergy(mark.kcal100)
            config.detail = "Tap to measure · swipe not required"
            cell.contentConfiguration = config
        }
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard let item = dataSource.itemIdentifier(for: indexPath), case .row(let barcode) = item else { return }
        let alert = UIAlertController(title: "Watchlist mark", message: barcode, preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: "Measure", style: .default) { [weak self] _ in
            guard let self, let specimen = self.store.state.specimens[barcode] ?? SpecimenShelf.specimen(barcode: barcode) else { return }
            self.store.dispatch(.catalog(.resolved(specimen)))
        })
        alert.addAction(UIAlertAction(title: "Remove", style: .destructive) { [weak self] _ in
            self?.store.dispatch(.watchlist(.drop(barcode)))
        })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: !InstrumentMotion.reduce)
    }
}
