import AVFoundation
import UIKit
import VisionKit

/// Role: VisionKit optical pickup with instrument crosshair and live readout.
@MainActor
final class DialScanController: UIViewController, DataScannerViewControllerDelegate, UITextFieldDelegate {
    private let store: MeterStore
    private var token: UUID?
    private var scanner: DataScannerViewController?
    private let overlay = UIImageView(image: UIImage(named: "etm_ScanOverlay"))
    private let crosshair = CrosshairView()
    private let readout = UILabel()
    private let field = UITextField()
    private let measure = UIButton(type: .system)
    private let chips = UIStackView()
    private let message = UILabel()
    private let settingsButton = UIButton(type: .system)
    private var lastPayload = ""
    private var lastAt = Date.distantPast

    init(store: MeterStore) {
        self.store = store
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { preconditionFailure("Storyboards are not used.") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Optical pickup"
        view.backgroundColor = InstrumentPalette.background
        overlay.contentMode = .scaleAspectFit
        overlay.accessibilityElementsHidden = true
        crosshair.isUserInteractionEnabled = false
        crosshair.accessibilityElementsHidden = true
        readout.font = InstrumentTypography.reading(.title)
        readout.textColor = InstrumentPalette.accent
        readout.textAlignment = .center
        readout.adjustsFontForContentSizeCategory = true
        readout.accessibilityLabel = "Live readout"
        message.font = InstrumentTypography.prose(.body)
        message.textColor = InstrumentPalette.ink
        message.numberOfLines = 0
        message.adjustsFontForContentSizeCategory = true
        field.placeholder = "Type a barcode"
        field.keyboardType = .numberPad
        field.font = InstrumentTypography.reading(.title)
        field.delegate = self
        field.borderStyle = .roundedRect
        field.accessibilityLabel = "Manual barcode"
        field.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        var config = UIButton.Configuration.filled()
        config.title = "Measure"
        config.baseBackgroundColor = InstrumentPalette.accent
        config.baseForegroundColor = InstrumentPalette.ink
        measure.configuration = config
        measure.addTarget(self, action: #selector(manualMeasure), for: .touchUpInside)
        measure.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        measure.accessibilityLabel = "Measure typed code"
        settingsButton.setTitle("Open Settings", for: .normal)
        settingsButton.addTarget(self, action: #selector(openSettings), for: .touchUpInside)
        settingsButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        settingsButton.isHidden = true
        chips.axis = .vertical
        chips.spacing = InstrumentSpace.x(1)
        for sample in SpecimenShelf.bundled {
            let button = UIButton(type: .system)
            button.setTitle("\(sample.name) · \(sample.barcode)", for: .normal)
            button.tag = SpecimenShelf.bundled.firstIndex(where: { $0.barcode == sample.barcode }) ?? 0
            button.addTarget(self, action: #selector(chipTapped(_:)), for: .touchUpInside)
            button.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
            button.accessibilityLabel = "Sample \(sample.name)"
            chips.addArrangedSubview(button)
        }
        let column = UIStackView(arrangedSubviews: [readout, message, settingsButton, field, measure, chips])
        column.axis = .vertical
        column.spacing = InstrumentSpace.x(1.5)
        view.addSubview(column)
        column.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            column.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: InstrumentSpace.x(2)),
            column.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -InstrumentSpace.x(2)),
            column.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -InstrumentSpace.x(2))
        ])
        token = store.observe { [weak self] state in
            self?.readout.text = state.scan.liveReadout.isEmpty ? "—" : state.scan.liveReadout
            self?.apply(phase: state.scan.phase)
        }
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appBackgrounded),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
        let tap = UITapGestureRecognizer(target: self, action: #selector(endEdit))
        tap.cancelsTouchesInView = false
        view.addGestureRecognizer(tap)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        evaluatePickup()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stopScanner()
        if isMovingFromParent {
            NotificationCenter.default.removeObserver(self)
        }
    }

    @objc private func appBackgrounded() {
        stopScanner()
    }

    private func evaluatePickup() {
        let deviceExists = AVCaptureDevice.default(for: .video) != nil
        let supported = DataScannerViewController.isSupported && DataScannerViewController.isAvailable && deviceExists
        if !supported {
            store.dispatch(.navigation(.scanPhase(.noPickup)))
            message.text = "This instrument has no optical pickup. Enter a code or use a sample from the local drum."
            chips.isHidden = false
            return
        }
        chips.isHidden = true
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            startScanner()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                Task { @MainActor in
                    if granted { self?.startScanner() } else {
                        self?.store.dispatch(.navigation(.scanPhase(.denied)))
                    }
                }
            }
        case .denied:
            store.dispatch(.navigation(.scanPhase(.denied)))
        case .restricted:
            store.dispatch(.navigation(.scanPhase(.restricted)))
        @unknown default:
            store.dispatch(.navigation(.scanPhase(.denied)))
        }
    }

    private func startScanner() {
        stopScanner()
        let controller = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.ean8, .ean13, .upce, .qr])],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: true,
            isHighlightingEnabled: true
        )
        controller.delegate = self
        addChild(controller)
        view.insertSubview(controller.view, at: 0)
        controller.view.frame = view.bounds
        controller.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        controller.didMove(toParent: self)
        controller.overlayContainerView.addSubview(overlay)
        controller.overlayContainerView.addSubview(crosshair)
        overlay.translatesAutoresizingMaskIntoConstraints = false
        crosshair.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            overlay.centerXAnchor.constraint(equalTo: controller.overlayContainerView.centerXAnchor),
            overlay.centerYAnchor.constraint(equalTo: controller.overlayContainerView.centerYAnchor),
            overlay.widthAnchor.constraint(equalToConstant: 240),
            overlay.heightAnchor.constraint(equalToConstant: 240),
            crosshair.centerXAnchor.constraint(equalTo: overlay.centerXAnchor),
            crosshair.centerYAnchor.constraint(equalTo: overlay.centerYAnchor),
            crosshair.widthAnchor.constraint(equalToConstant: 120),
            crosshair.heightAnchor.constraint(equalToConstant: 120)
        ])
        scanner = controller
        try? controller.startScanning()
        store.dispatch(.navigation(.scanPhase(.seeking)))
        message.text = "Hold a package inside the reticle."
        settingsButton.isHidden = true
    }

    private func stopScanner() {
        scanner?.stopScanning()
        scanner?.willMove(toParent: nil)
        scanner?.view.removeFromSuperview()
        scanner?.removeFromParent()
        scanner = nil
    }

    func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
        for item in addedItems {
            if case .barcode(let barcode) = item {
                let payload = barcode.payloadStringValue ?? ""
                handle(payload)
            }
        }
    }

    private func handle(_ payload: String) {
        guard !payload.isEmpty else { return }
        let now = Date()
        if payload == lastPayload && now.timeIntervalSince(lastAt) < 1.8 { return }
        lastPayload = payload
        lastAt = now
        store.dispatch(.navigation(.scanReadout(payload)))
        store.dispatch(.catalog(.resolveBarcode(payload)))
    }

    private func apply(phase: ScanPhase) {
        settingsButton.isHidden = !(phase == .denied || phase == .restricted)
        switch phase {
        case .denied:
            message.text = "The optical pickup is closed. Open Settings to admit the camera."
        case .restricted:
            message.text = "The optical pickup is restricted on this device."
        case .miss:
            message.text = "No specimen is registered for this code."
        case .offline:
            message.text = "This code is not in the local drum, and the wire is down."
        case .resolving:
            message.text = "Resolving the specimen…"
        default:
            break
        }
    }

    @objc private func manualMeasure() {
        store.dispatch(.catalog(.resolveBarcode(field.text ?? "")))
    }

    @objc private func chipTapped(_ sender: UIButton) {
        let samples = SpecimenShelf.bundled
        guard samples.indices.contains(sender.tag) else { return }
        store.dispatch(.catalog(.resolved(samples[sender.tag])))
    }

    @objc private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }

    @objc private func endEdit() { view.endEditing(true) }
}

final class CrosshairView: UIView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
    }

    required init?(coder: NSCoder) { preconditionFailure("Storyboards are not used.") }

    override func draw(_ rect: CGRect) {
        let path = UIBezierPath()
        let mid = CGPoint(x: bounds.midX, y: bounds.midY)
        path.move(to: CGPoint(x: mid.x - 40, y: mid.y))
        path.addLine(to: CGPoint(x: mid.x + 40, y: mid.y))
        path.move(to: CGPoint(x: mid.x, y: mid.y - 40))
        path.addLine(to: CGPoint(x: mid.x, y: mid.y + 40))
        InstrumentPalette.accent.setStroke()
        path.lineWidth = 2
        path.stroke()
        let ring = UIBezierPath(arcCenter: mid, radius: 28, startAngle: 0, endAngle: .pi * 2, clockwise: true)
        ring.lineWidth = 1
        ring.stroke()
    }
}
