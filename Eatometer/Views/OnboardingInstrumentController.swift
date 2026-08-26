import UIKit

/// Role: first-run calibration. Writes factory or custom dials and the completion flag.
@MainActor
final class OnboardingInstrumentController: UIViewController, UICollectionViewDelegate {
    private let store: MeterStore
    private var collection: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<Int, Int>!
    private let kcalField = UITextField()
    private let proteinField = UITextField()
    private let carbsField = UITextField()
    private let fatField = UITextField()

    init(store: MeterStore) {
        self.store = store
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { preconditionFailure("Storyboards are not used.") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = InstrumentPalette.background
        let layout = UICollectionViewCompositionalLayout { _, environment in
            let item = NSCollectionLayoutItem(
                layoutSize: NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .fractionalHeight(1))
            )
            let group = NSCollectionLayoutGroup.horizontal(
                layoutSize: NSCollectionLayoutSize(
                    widthDimension: .fractionalWidth(1),
                    heightDimension: .fractionalHeight(1)
                ),
                subitems: [item]
            )
            let section = NSCollectionLayoutSection(group: group)
            section.orthogonalScrollingBehavior = .groupPaging
            return section
        }
        collection = UICollectionView(frame: view.bounds, collectionViewLayout: layout)
        collection.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        collection.backgroundColor = .clear
        collection.isPagingEnabled = true
        collection.delegate = self
        view.addSubview(collection)

        let registration = UICollectionView.CellRegistration<DialCell, Int> { [weak self] cell, _, page in
            self?.configure(cell: cell, page: page)
        }
        dataSource = UICollectionViewDiffableDataSource(collectionView: collection) { collection, indexPath, item in
            collection.dequeueConfiguredReusableCell(using: registration, for: indexPath, item: item)
        }
        var snapshot = NSDiffableDataSourceSnapshot<Int, Int>()
        snapshot.appendSections([0])
        snapshot.appendItems([0, 1, 2, 3], toSection: 0)
        dataSource.apply(snapshot, animatingDifferences: false)
        configureFields()
        let tap = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
        tap.cancelsTouchesInView = false
        view.addGestureRecognizer(tap)
    }

    private func configureFields() {
        for field in [kcalField, proteinField, carbsField, fatField] {
            field.keyboardType = .decimalPad
            field.font = InstrumentTypography.reading(.title)
            field.textColor = InstrumentPalette.ink
            field.adjustsFontForContentSizeCategory = true
            field.borderStyle = .none
            field.backgroundColor = InstrumentPalette.surface
            field.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        }
        kcalField.text = "2200"
        proteinField.text = "140"
        carbsField.text = "220"
        fatField.text = "70"
        kcalField.accessibilityLabel = "Energy target"
        proteinField.accessibilityLabel = "Protein target"
        carbsField.accessibilityLabel = "Carbohydrate target"
        fatField.accessibilityLabel = "Fat target"
    }

    private func configure(cell: DialCell, page: Int) {
        cell.contentView.subviews.forEach { $0.removeFromSuperview() }
        let art = UIImageView()
        art.contentMode = .scaleAspectFit
        art.accessibilityElementsHidden = true
        let title = UILabel()
        title.font = InstrumentTypography.prose(.display)
        title.textColor = InstrumentPalette.ink
        title.numberOfLines = 0
        title.adjustsFontForContentSizeCategory = true
        let body = UILabel()
        body.font = InstrumentTypography.prose(.body)
        body.textColor = InstrumentPalette.muted
        body.numberOfLines = 0
        body.adjustsFontForContentSizeCategory = true
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = InstrumentSpace.x(2)
        stack.alignment = .fill
        switch page {
        case 0:
            art.image = UIImage(named: "etm_Onboarding1")
            title.text = "Measure the week, not the meal."
            body.text = "Eatometer is a personal food log. It is not medical advice. Nutrition figures come from Open Food Facts."
        case 1:
            art.image = UIImage(named: "etm_Onboarding2")
            title.text = "Search or scan a specimen."
            body.text = "The optical pickup reads a package. The catalog search names it. Either path takes one measurement."
        case 2:
            art.image = UIImage(named: "etm_Onboarding3")
            title.text = "The analytics drum."
            body.text = "Seven, thirty and ninety-day traces, weekday averages, a macro donut and adherence sit on their own segment."
        default:
            art.image = UIImage(named: "etm_ControlFace")
            title.text = "Set the daily dials."
            body.text = "Skip writes a factory calibration. You can retune these later on Targets."
            let fields = UIStackView(arrangedSubviews: [
                labeled("Energy kcal", kcalField),
                labeled("Protein g", proteinField),
                labeled("Carbs g", carbsField),
                labeled("Fat g", fatField)
            ])
            fields.axis = .vertical
            fields.spacing = InstrumentSpace.x(1)
            stack.addArrangedSubview(fields)
            let start = makeButton("Calibrate", action: #selector(finish))
            let skip = makeButton("Skip with factory dials", action: #selector(skipFactory), filled: false)
            stack.addArrangedSubview(start)
            stack.addArrangedSubview(skip)
        }
        stack.insertArrangedSubview(art, at: 0)
        stack.insertArrangedSubview(title, at: 1)
        stack.insertArrangedSubview(body, at: 2)
        cell.contentView.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            art.heightAnchor.constraint(equalTo: cell.contentView.heightAnchor, multiplier: 0.36),
            stack.topAnchor.constraint(equalTo: cell.contentView.safeAreaLayoutGuide.topAnchor, constant: InstrumentSpace.x(2)),
            stack.leadingAnchor.constraint(equalTo: cell.contentView.leadingAnchor, constant: InstrumentSpace.x(3)),
            stack.trailingAnchor.constraint(equalTo: cell.contentView.trailingAnchor, constant: -InstrumentSpace.x(3)),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: cell.contentView.safeAreaLayoutGuide.bottomAnchor, constant: -InstrumentSpace.x(2))
        ])
    }

    private func labeled(_ title: String, _ field: UITextField) -> UIView {
        let caption = UILabel()
        caption.text = title
        caption.font = InstrumentTypography.prose(.caption)
        caption.textColor = InstrumentPalette.muted
        caption.adjustsFontForContentSizeCategory = true
        let box = UIStackView(arrangedSubviews: [caption, field])
        box.axis = .vertical
        box.spacing = InstrumentSpace.x(0.5)
        return box
    }

    private func makeButton(_ title: String, action: Selector, filled: Bool = true) -> UIButton {
        var config = filled ? UIButton.Configuration.filled() : UIButton.Configuration.bordered()
        config.title = title
        config.baseBackgroundColor = filled ? InstrumentPalette.accent : InstrumentPalette.surface
        config.baseForegroundColor = InstrumentPalette.ink
        config.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16)
        let button = UIButton(configuration: config)
        button.addTarget(self, action: action, for: .touchUpInside)
        button.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        button.accessibilityLabel = title
        return button
    }

    @objc private func dismissKeyboard() {
        view.endEditing(true)
    }

    @objc private func skipFactory() {
        store.dispatch(.onboarding(.skipWithFactory))
        InstrumentHaptics.commit()
    }

    @objc private func finish() {
        let kcal = GaugeMaths.parseGrams(kcalField.text ?? "") ?? 0
        let protein = GaugeMaths.parseGrams(proteinField.text ?? "")
        let carbs = GaugeMaths.parseGrams(carbsField.text ?? "")
        let fat = GaugeMaths.parseGrams(fatField.text ?? "")
        let calibration = DialCalibration(
            kcal: kcal,
            protein: protein == 0 ? nil : protein,
            carbs: carbs == 0 ? nil : carbs,
            fat: fat == 0 ? nil : fat
        )
        store.dispatch(.onboarding(.finish(calibration)))
        if store.state.onboardingComplete {
            InstrumentHaptics.commit()
        }
    }
}
