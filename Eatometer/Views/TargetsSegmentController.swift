import UIKit
import OrderedCollections

enum TargetItem: Hashable {
    case kcal, protein, carbs, fat, save, onboard, reset, contact
}

/// Role: dial calibration plus support, reset, and onboarding replay.
@MainActor
final class TargetsSegmentController: UIViewController {
    private let store: MeterStore
    private var token: UUID?
    private var collection: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<Int, TargetItem>!
    private var kcalText: String = ""
    private var proteinText: String = ""
    private var carbsText: String = ""
    private var fatText: String = ""

    init(store: MeterStore) {
        self.store = store
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { preconditionFailure("Storyboards are not used.") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        seedFields(store.state.calibration)
        collection = UICollectionView(frame: view.bounds, collectionViewLayout: InstrumentLayout.list(estimated: 88))
        collection.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        collection.backgroundColor = .clear
        collection.keyboardDismissMode = .onDrag
        view.addSubview(collection)
        let tap = UITapGestureRecognizer(target: self, action: #selector(endEdit))
        tap.cancelsTouchesInView = false
        view.addGestureRecognizer(tap)
        let registration = UICollectionView.CellRegistration<DialCell, TargetItem> { [weak self] cell, _, item in
            self?.paint(cell, item: item)
        }
        dataSource = UICollectionViewDiffableDataSource(collectionView: collection) { collection, path, item in
            collection.dequeueConfiguredReusableCell(using: registration, for: path, item: item)
        }
        var snapshot = NSDiffableDataSourceSnapshot<Int, TargetItem>()
        snapshot.appendSections([0])
        snapshot.appendItems([.kcal, .protein, .carbs, .fat, .save, .onboard, .reset, .contact], toSection: 0)
        dataSource.apply(snapshot, animatingDifferences: false)
        token = store.observe { [weak self] state in
            guard let self else { return }
            if self.view.findFirstResponder() == nil {
                self.seedFields(state.calibration)
                self.collection.reloadData()
            }
        }
    }

    private func seedFields(_ calibration: DialCalibration) {
        kcalText = InstrumentFormatters.energy(calibration.kcal)
        proteinText = calibration.protein.map { InstrumentFormatters.macro($0) } ?? ""
        carbsText = calibration.carbs.map { InstrumentFormatters.macro($0) } ?? ""
        fatText = calibration.fat.map { InstrumentFormatters.macro($0) } ?? ""
    }

    private func paint(_ cell: DialCell, item: TargetItem) {
        switch item {
        case .kcal:
            cell.contentConfiguration = field("Energy kcal", kcalText) { [weak self] in self?.kcalText = $0 }
        case .protein:
            cell.contentConfiguration = field("Protein g (blank = unset)", proteinText) { [weak self] in self?.proteinText = $0 }
        case .carbs:
            cell.contentConfiguration = field("Carbs g (blank = unset)", carbsText) { [weak self] in self?.carbsText = $0 }
        case .fat:
            cell.contentConfiguration = field("Fat g (blank = unset)", fatText) { [weak self] in self?.fatText = $0 }
        case .save:
            var config = ActionRowConfiguration()
            config.title = "Write dials"
            config.onTap = { [weak self] in self?.save() }
            cell.contentConfiguration = config
        case .onboard:
            var config = ActionRowConfiguration()
            config.title = "Re-run onboarding"
            config.onTap = { [weak self] in self?.store.dispatch(.onboarding(.reopen)) }
            cell.contentConfiguration = config
        case .reset:
            var config = ActionRowConfiguration()
            config.title = "Reset all data"
            config.destructive = true
            config.enabled = !store.state.isResetting
            config.onTap = { [weak self] in self?.confirmReset() }
            cell.contentConfiguration = config
        case .contact:
            var config = ActionRowConfiguration()
            config.title = "Contact eatometer.pro"
            config.onTap = { [weak self] in
                guard let self else { return }
                WebContentHost.presentContact(from: self)
            }
            cell.contentConfiguration = config
        }
    }

    private func field(_ label: String, _ text: String, onChange: @escaping (String) -> Void) -> FieldConfiguration {
        var config = FieldConfiguration()
        config.label = label
        config.text = text
        config.onChange = onChange
        return config
    }

    private func save() {
        guard let kcal = GaugeMaths.parseGrams(kcalText), kcal >= 800, kcal <= 6000 else { return }
        let protein = optionalMacro(proteinText)
        let carbs = optionalMacro(carbsText)
        let fat = optionalMacro(fatText)
        store.dispatch(.calibration(.write(DialCalibration(kcal: kcal, protein: protein, carbs: carbs, fat: fat))))
        InstrumentHaptics.commit()
    }

    private func optionalMacro(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        let value = GaugeMaths.parseGrams(trimmed)
        if value == 0 { return nil }
        return value
    }

    private func confirmReset() {
        let alert = UIAlertController(
            title: "Reset the ledger?",
            message: "Every stroke, watch mark and custom dial will be erased.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Reset", style: .destructive) { [weak self] _ in
            self?.store.dispatch(.persistence(.resetRequested))
        })
        present(alert, animated: !InstrumentMotion.reduce)
    }

    @objc private func endEdit() { view.endEditing(true) }
}
