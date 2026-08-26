import UIKit

/// Role: single shell. Segmented control swaps bodies; search, scan and measure push.
@MainActor
final class RootInstrumentController: UIViewController {
    private let store: MeterStore
    private var token: UUID?
    private let segments = UISegmentedControl(items: InstrumentSegment.allCases.map(\.title))
    private let container = UIView()
    private var current: UIViewController?
    private var presentingMeasure = false
    private let success = UIImageView(image: UIImage(named: "etm_SuccessMark"))

    init(store: MeterStore) {
        self.store = store
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { preconditionFailure("Storyboards are not used.") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = InstrumentPalette.background
        title = "Eatometer"
        navigationController?.navigationBar.prefersLargeTitles = false
        navigationController?.navigationBar.titleTextAttributes = [
            .font: InstrumentTypography.prose(.title),
            .foregroundColor: InstrumentPalette.ink
        ]
        let texture = UIImageView(image: UIImage(named: "etm_Texture"))
        texture.contentMode = .scaleAspectFill
        texture.alpha = 0.07
        texture.accessibilityElementsHidden = true
        texture.clipsToBounds = true
        view.addSubview(texture)
        texture.translatesAutoresizingMaskIntoConstraints = false

        segments.selectedSegmentIndex = 0
        segments.addTarget(self, action: #selector(segmentChanged), for: .valueChanged)
        segments.selectedSegmentTintColor = InstrumentPalette.accent
        segments.apportionsSegmentWidthsByContent = true

        navigationItem.leftBarButtonItem = UIBarButtonItem(
            title: "Watch",
            style: .plain,
            target: self,
            action: #selector(openWatch)
        )
        navigationItem.leftBarButtonItem?.accessibilityLabel = "Open watchlist"
        navigationItem.rightBarButtonItems = [
            UIBarButtonItem(title: "Scan", style: .plain, target: self, action: #selector(openScan)),
            UIBarButtonItem(title: "Search", style: .plain, target: self, action: #selector(openSearch))
        ]
        navigationItem.rightBarButtonItems?.forEach { $0.accessibilityLabel = $0.title }

        view.addSubview(segments)
        segments.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(container)
        container.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            texture.topAnchor.constraint(equalTo: view.topAnchor),
            texture.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            texture.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            texture.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            segments.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            segments.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            segments.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            container.topAnchor.constraint(equalTo: segments.bottomAnchor, constant: 8),
            container.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            container.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            container.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])

        success.contentMode = .scaleAspectFit
        success.alpha = 0
        success.accessibilityElementsHidden = true
        view.addSubview(success)
        success.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            success.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            success.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            success.widthAnchor.constraint(equalToConstant: 120),
            success.heightAnchor.constraint(equalToConstant: 120)
        ])

        token = store.observe { [weak self] state in
            self?.render(state)
        }
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(clockShifted),
            name: UIApplication.significantTimeChangeNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(clockShifted),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if isMovingFromParent {
            NotificationCenter.default.removeObserver(self)
        }
    }

    @objc private func clockShifted() {
        store.dispatch(.clock(.calendarShifted))
    }

    private func render(_ state: AppState) {
        let index = InstrumentSegment.allCases.firstIndex(of: state.selectedSegment) ?? 0
        if segments.selectedSegmentIndex != index {
            segments.selectedSegmentIndex = index
        }
        show(segment: state.selectedSegment)

        if let _ = state.measurement {
            if !presentingMeasure, !(navigationController?.topViewController is MeasurementAssignController) {
                presentingMeasure = true
                navigationController?.pushViewController(MeasurementAssignController(store: store), animated: !InstrumentMotion.reduce)
            }
        } else if presentingMeasure {
            presentingMeasure = false
            navigationController?.popToViewController(self, animated: !InstrumentMotion.reduce)
            if state.highlightedReadingID != nil {
                flashSuccess()
            }
        }
    }

    private func show(segment: InstrumentSegment) {
        let next: UIViewController
        switch segment {
        case .reading: next = children.compactMap { $0 as? ReadingSegmentController }.first ?? ReadingSegmentController(store: store)
        case .log: next = children.compactMap { $0 as? LogSegmentController }.first ?? LogSegmentController(store: store)
        case .analytics: next = children.compactMap { $0 as? AnalyticsSegmentController }.first ?? AnalyticsSegmentController(store: store)
        case .targets: next = children.compactMap { $0 as? TargetsSegmentController }.first ?? TargetsSegmentController(store: store)
        }
        if current === next { return }
        current?.willMove(toParent: nil)
        current?.view.removeFromSuperview()
        current?.removeFromParent()
        addChild(next)
        next.view.frame = container.bounds
        next.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        container.addSubview(next.view)
        next.didMove(toParent: self)
        current = next
    }

    private func flashSuccess() {
        InstrumentHaptics.commit()
        if InstrumentMotion.reduce {
            return
        }
        success.alpha = 1
        UIView.animate(withDuration: InstrumentMotion.duration, delay: 0.4, options: InstrumentMotion.options) {
            self.success.alpha = 0
        }
    }

    @objc private func segmentChanged() {
        let index = segments.selectedSegmentIndex
        guard InstrumentSegment.allCases.indices.contains(index) else { return }
        store.dispatch(.navigation(.segment(InstrumentSegment.allCases[index])))
    }

    @objc private func openSearch() {
        navigationController?.pushViewController(CatalogSearchController(store: store), animated: !InstrumentMotion.reduce)
    }

    @objc private func openScan() {
        navigationController?.pushViewController(DialScanController(store: store), animated: !InstrumentMotion.reduce)
    }

    @objc private func openWatch() {
        navigationController?.pushViewController(WatchlistController(store: store), animated: !InstrumentMotion.reduce)
    }
}
