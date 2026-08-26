import UIKit
import OrderedCollections

enum AnalyticsItem: Hashable {
    case hero
    case window
    case trend
    case weekday
    case donut
    case adherence
    case extremes
}

/// Role: analytics deep dive. Charts are CALayer traces driven by selectors.
@MainActor
final class AnalyticsSegmentController: UIViewController {
    private let store: MeterStore
    private var token: UUID?
    private var collection: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<Int, AnalyticsItem>!

    init(store: MeterStore) {
        self.store = store
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { preconditionFailure("Storyboards are not used.") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        collection = UICollectionView(frame: view.bounds, collectionViewLayout: InstrumentLayout.list(estimated: 220))
        collection.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        collection.backgroundColor = .clear
        view.addSubview(collection)
        let registration = UICollectionView.CellRegistration<DialCell, AnalyticsItem> { [weak self] cell, _, item in
            self?.paint(cell, item: item)
        }
        dataSource = UICollectionViewDiffableDataSource(collectionView: collection) { collection, path, item in
            collection.dequeueConfiguredReusableCell(using: registration, for: path, item: item)
        }
        token = store.observe { [weak self] _ in
            self?.apply()
        }
    }

    private func apply() {
        var items = OrderedSet<AnalyticsItem>()
        items.append(contentsOf: [.hero, .window, .trend, .weekday, .donut, .adherence, .extremes])
        var snapshot = NSDiffableDataSourceSnapshot<Int, AnalyticsItem>()
        snapshot.appendSections([0])
        snapshot.appendItems(Array(items), toSection: 0)
        dataSource.apply(snapshot, animatingDifferences: false)
    }

    private func paint(_ cell: DialCell, item: AnalyticsItem) {
        let ledger = AnalyticsSelector.ledger(from: store.state, days: store.state.analyticsWindowDays)
        switch item {
        case .hero:
            var config = FaceCardConfiguration()
            config.artName = "etm_TwistHero"
            config.eyebrow = "Deep dive"
            config.title = "The week, not the meal"
            config.detail = "Traces use persisted strokes. Windowed weekly means come from swift-algorithms."
            cell.contentConfiguration = config
        case .window:
            var config = ActionRowConfiguration()
            config.title = "Window: \(store.state.analyticsWindowDays) days  (tap to cycle 7/30/90)"
            config.onTap = { [weak self] in
                guard let self else { return }
                let next = store.state.analyticsWindowDays == 7 ? 30 : store.state.analyticsWindowDays == 30 ? 90 : 7
                store.dispatch(.navigation(.analyticsWindow(next)))
            }
            cell.contentConfiguration = config
        case .trend:
            var config = ChartCardConfiguration()
            config.title = "Energy trend"
            config.kind = .trend
            config.values = ledger.daily.map { CGFloat($0.kcal) }
            config.footnote = "Daily kcal across \(ledger.windowDays) days."
            cell.contentConfiguration = config
        case .weekday:
            var config = ChartCardConfiguration()
            config.title = "Weekday averages"
            config.kind = .bars
            config.values = ledger.weekdayAverages.map { CGFloat($0) }
            config.footnote = "Sunday through Saturday mean energy."
            cell.contentConfiguration = config
        case .donut:
            var config = ChartCardConfiguration()
            config.title = "Macro split"
            config.kind = .donut
            config.protein = CGFloat(ledger.proteinTotal)
            config.carbs = CGFloat(ledger.carbsTotal)
            config.fat = CGFloat(ledger.fatTotal)
            config.footnote = "P \(InstrumentFormatters.macro(ledger.proteinTotal))  C \(InstrumentFormatters.macro(ledger.carbsTotal))  F \(InstrumentFormatters.macro(ledger.fatTotal))"
            cell.contentConfiguration = config
        case .adherence:
            var config = FaceCardConfiguration()
            config.artName = "etm_ControlFace"
            config.eyebrow = "Adherence"
            config.title = "Days inside 80–110% of the energy dial"
            config.reading = InstrumentFormatters.energy(ledger.adherencePercent) + "%"
            cell.contentConfiguration = config
        case .extremes:
            var config = FaceCardConfiguration()
            config.artName = "etm_SuccessMark"
            config.eyebrow = "Best / worst"
            let best = ledger.bestDay.map { InstrumentFormatters.dayTitle($0.dayKey) + " " + InstrumentFormatters.energy($0.kcal) } ?? "—"
            let worst = ledger.worstDay.map { InstrumentFormatters.dayTitle($0.dayKey) + " " + InstrumentFormatters.energy($0.kcal) } ?? "—"
            config.title = "Best \(best)"
            config.detail = "Worst \(worst)"
            cell.contentConfiguration = config
        }
    }
}
