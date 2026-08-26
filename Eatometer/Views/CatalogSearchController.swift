import UIKit
import OrderedCollections

enum SearchItem: Hashable {
    case field
    case notice
    case hit(String)
    case empty
    case error
}

/// Role: debounced catalog search. Results push the fused measurement screen via the store.
@MainActor
final class CatalogSearchController: UIViewController, UISearchBarDelegate, UICollectionViewDelegate {
    private let store: MeterStore
    private var token: UUID?
    private var collection: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<Int, SearchItem>!
    private let searchBar = UISearchBar()

    init(store: MeterStore) {
        self.store = store
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { preconditionFailure("Storyboards are not used.") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Catalog search"
        view.backgroundColor = InstrumentPalette.background
        searchBar.delegate = self
        searchBar.placeholder = "Name a specimen"
        searchBar.searchBarStyle = .minimal
        searchBar.autocapitalizationType = .none
        searchBar.accessibilityLabel = "Search the catalog"
        searchBar.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true

        collection = UICollectionView(frame: .zero, collectionViewLayout: InstrumentLayout.list(estimated: 88))
        collection.backgroundColor = .clear
        collection.keyboardDismissMode = .onDrag
        collection.delegate = self

        let stack = UIStackView(arrangedSubviews: [searchBar, collection])
        stack.axis = .vertical
        view.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            stack.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])

        let registration = UICollectionView.CellRegistration<DialCell, SearchItem> { [weak self] cell, _, item in
            self?.paint(cell, item: item)
        }
        dataSource = UICollectionViewDiffableDataSource(collectionView: collection) { collection, path, item in
            collection.dequeueConfiguredReusableCell(using: registration, for: path, item: item)
        }
        token = store.observe { [weak self] state in
            self?.apply(state.search)
        }
    }

    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        store.dispatch(.catalog(.searchTextChanged(searchText)))
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard let item = dataSource.itemIdentifier(for: indexPath), case .hit(let barcode) = item,
              let record = store.state.search.hits.first(where: { $0.barcode == barcode })
        else { return }
        store.dispatch(.catalog(.resolved(record)))
    }

    private func apply(_ search: SearchDialState) {
        var items = OrderedSet<SearchItem>()
        if let notice = search.notice, !notice.isEmpty {
            items.append(.notice)
        }
        switch search.phase {
        case .idle:
            break
        case .pending, .loading:
            items.append(.notice)
        case .results:
            for hit in search.hits { items.append(.hit(hit.barcode)) }
        case .empty:
            items.append(.empty)
        case .transport:
            items.append(.error)
        }
        var snapshot = NSDiffableDataSourceSnapshot<Int, SearchItem>()
        snapshot.appendSections([0])
        snapshot.appendItems(Array(items), toSection: 0)
        dataSource.apply(snapshot, animatingDifferences: !InstrumentMotion.reduce)
    }

    private func paint(_ cell: DialCell, item: SearchItem) {
        let search = store.state.search
        switch item {
        case .field:
            break
        case .notice:
            var config = FaceCardConfiguration()
            config.eyebrow = search.phase == .loading ? "Seeking" : "Note"
            config.title = search.phase == .loading ? "Consulting the catalog…" : (search.notice ?? "Waiting on the needle.")
            cell.contentConfiguration = config
        case .hit(let barcode):
            guard let hit = search.hits.first(where: { $0.barcode == barcode }) else { return }
            var config = FaceCardConfiguration()
            config.artName = hit.shelfAsset ?? "etm_ProductPlaceholder"
            config.eyebrow = hit.brand.isEmpty ? hit.barcode : hit.brand
            config.title = hit.name
            config.reading = InstrumentFormatters.unknownEnergy(hit.kcal100)
            config.detail = hit.kcal100 == nil ? "Energy unknown" : "kcal / 100 g"
            cell.contentConfiguration = config
        case .empty:
            var config = EmptyDrumConfiguration()
            config.artName = "etm_EmptySearch"
            config.title = "No specimen in the catalog."
            config.body = "The remote drum and the local shelf both came back empty."
            config.actionTitle = "Retry"
            config.onAction = { [weak self] in self?.store.dispatch(.catalog(.searchRetry)) }
            cell.contentConfiguration = config
        case .error:
            var config = EmptyDrumConfiguration()
            config.artName = "etm_EmptySearch"
            config.title = "The wire did not hold."
            config.body = "Open Food Facts did not answer. Retry, or rely on the local shelf names."
            config.actionTitle = "Retry"
            config.onAction = { [weak self] in self?.store.dispatch(.catalog(.searchRetry)) }
            cell.contentConfiguration = config
        }
    }
}
