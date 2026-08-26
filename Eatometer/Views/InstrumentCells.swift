import UIKit

struct FaceCardConfiguration: UIContentConfiguration {
    var eyebrow: String = ""
    var title: String = ""
    var reading: String = ""
    var detail: String = ""
    var artName: String = ""
    var highlighted: Bool = false
    var isDecorativeArt: Bool = true

    func makeContentView() -> UIView & UIContentView { FaceCardView(configuration: self) }
    func updated(for state: UIConfigurationState) -> Self { self }
}

final class FaceCardView: UIView, UIContentView {
    var configuration: UIContentConfiguration {
        didSet { apply() }
    }

    private let art = UIImageView()
    private let eyebrow = UILabel()
    private let title = UILabel()
    private let reading = UILabel()
    private let detail = UILabel()
    private let stack = UIStackView()

    init(configuration: FaceCardConfiguration) {
        self.configuration = configuration
        super.init(frame: .zero)
        backgroundColor = InstrumentPalette.surface
        layer.borderWidth = 1
        layer.borderColor = InstrumentPalette.muted.withAlphaComponent(0.35).cgColor
        art.contentMode = .scaleAspectFit
        art.setContentHuggingPriority(.required, for: .horizontal)
        eyebrow.font = InstrumentTypography.prose(.caption)
        eyebrow.textColor = InstrumentPalette.muted
        eyebrow.adjustsFontForContentSizeCategory = true
        title.font = InstrumentTypography.prose(.title)
        title.textColor = InstrumentPalette.ink
        title.adjustsFontForContentSizeCategory = true
        title.numberOfLines = 2
        title.lineBreakMode = .byTruncatingTail
        title.setContentCompressionResistancePriority(.required, for: .horizontal)
        reading.font = InstrumentTypography.reading(.title)
        reading.textColor = InstrumentPalette.accent
        reading.adjustsFontForContentSizeCategory = true
        reading.adjustsFontSizeToFitWidth = true
        reading.minimumScaleFactor = 0.7
        detail.font = InstrumentTypography.prose(.caption)
        detail.textColor = InstrumentPalette.muted
        detail.adjustsFontForContentSizeCategory = true
        detail.numberOfLines = 2
        let text = UIStackView(arrangedSubviews: [eyebrow, title, reading, detail])
        text.axis = .vertical
        text.alignment = .leading
        text.spacing = InstrumentSpace.x(0.5)
        stack.axis = .horizontal
        stack.alignment = .top
        stack.spacing = InstrumentSpace.x(1.5)
        stack.addArrangedSubview(art)
        stack.addArrangedSubview(text)
        addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        art.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: InstrumentSpace.x(1.5)),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -InstrumentSpace.x(1.5)),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: InstrumentSpace.x(1.5)),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -InstrumentSpace.x(1.5)),
            art.widthAnchor.constraint(equalToConstant: 48),
            art.heightAnchor.constraint(equalToConstant: 48)
        ])
        apply()
    }

    required init?(coder: NSCoder) { preconditionFailure("Storyboards are not used.") }

    private func apply() {
        guard let config = configuration as? FaceCardConfiguration else { return }
        eyebrow.text = config.eyebrow
        title.text = config.title
        reading.text = config.reading
        reading.isHidden = config.reading.isEmpty
        detail.text = config.detail
        art.image = UIImage(named: config.artName)
        art.isAccessibilityElement = !config.isDecorativeArt
        art.accessibilityElementsHidden = config.isDecorativeArt
        backgroundColor = config.highlighted ? InstrumentPalette.accent.withAlphaComponent(0.12) : InstrumentPalette.surface
    }
}

struct EmptyDrumConfiguration: UIContentConfiguration {
    var artName: String = ""
    var title: String = ""
    var body: String = ""
    var actionTitle: String = ""
    var onAction: (() -> Void)?

    func makeContentView() -> UIView & UIContentView { EmptyDrumView(configuration: self) }
    func updated(for state: UIConfigurationState) -> Self { self }
}

final class EmptyDrumView: UIView, UIContentView {
    var configuration: UIContentConfiguration {
        didSet { apply() }
    }

    private let art = UIImageView()
    private let title = UILabel()
    private let body = UILabel()
    private let action = UIButton(type: .system)

    init(configuration: EmptyDrumConfiguration) {
        self.configuration = configuration
        super.init(frame: .zero)
        art.contentMode = .scaleAspectFit
        art.accessibilityElementsHidden = true
        title.font = InstrumentTypography.prose(.title)
        title.textColor = InstrumentPalette.ink
        title.textAlignment = .center
        title.adjustsFontForContentSizeCategory = true
        title.numberOfLines = 0
        body.font = InstrumentTypography.prose(.body)
        body.textColor = InstrumentPalette.muted
        body.textAlignment = .center
        body.adjustsFontForContentSizeCategory = true
        body.numberOfLines = 0
        var config = UIButton.Configuration.filled()
        config.baseBackgroundColor = InstrumentPalette.accent
        config.baseForegroundColor = InstrumentPalette.ink
        config.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16)
        action.configuration = config
        action.addTarget(self, action: #selector(tap), for: .touchUpInside)
        let stack = UIStackView(arrangedSubviews: [art, title, body, action])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = InstrumentSpace.x(1.5)
        addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            art.widthAnchor.constraint(equalToConstant: 160),
            art.heightAnchor.constraint(equalToConstant: 160),
            action.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: InstrumentSpace.x(2)),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -InstrumentSpace.x(2)),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: InstrumentSpace.x(2)),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -InstrumentSpace.x(2))
        ])
        apply()
    }

    required init?(coder: NSCoder) { preconditionFailure("Storyboards are not used.") }

    @objc private func tap() {
        (configuration as? EmptyDrumConfiguration)?.onAction?()
    }

    private func apply() {
        guard let config = configuration as? EmptyDrumConfiguration else { return }
        art.image = UIImage(named: config.artName)
        title.text = config.title
        body.text = config.body
        action.setTitle(config.actionTitle, for: .normal)
        action.accessibilityLabel = config.actionTitle
    }
}

struct FieldConfiguration: UIContentConfiguration {
    var label: String = ""
    var text: String = ""
    var keyboard: UIKeyboardType = .decimalPad
    var onChange: ((String) -> Void)?

    func makeContentView() -> UIView & UIContentView { FieldCardView(configuration: self) }
    func updated(for state: UIConfigurationState) -> Self { self }
}

final class FieldCardView: UIView, UIContentView, UITextFieldDelegate {
    var configuration: UIContentConfiguration {
        didSet { apply() }
    }

    private let caption = UILabel()
    private let field = UITextField()

    init(configuration: FieldConfiguration) {
        self.configuration = configuration
        super.init(frame: .zero)
        backgroundColor = InstrumentPalette.surface
        layer.borderWidth = 1
        layer.borderColor = InstrumentPalette.muted.withAlphaComponent(0.35).cgColor
        caption.font = InstrumentTypography.prose(.caption)
        caption.textColor = InstrumentPalette.muted
        caption.adjustsFontForContentSizeCategory = true
        field.font = InstrumentTypography.reading(.title)
        field.textColor = InstrumentPalette.ink
        field.adjustsFontForContentSizeCategory = true
        field.delegate = self
        field.addTarget(self, action: #selector(changed), for: .editingChanged)
        field.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        let stack = UIStackView(arrangedSubviews: [caption, field])
        stack.axis = .vertical
        stack.spacing = InstrumentSpace.x(0.5)
        addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: InstrumentSpace.x(1.5)),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -InstrumentSpace.x(1.5)),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: InstrumentSpace.x(1.5)),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -InstrumentSpace.x(1.5))
        ])
        apply()
    }

    required init?(coder: NSCoder) { preconditionFailure("Storyboards are not used.") }

    @objc private func changed() {
        (configuration as? FieldConfiguration)?.onChange?(field.text ?? "")
    }

    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        if string.isEmpty { return true }
        let allowed = CharacterSet(charactersIn: "0123456789,.")
        return string.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    private func apply() {
        guard let config = configuration as? FieldConfiguration else { return }
        caption.text = config.label
        if field.text != config.text && !field.isFirstResponder {
            field.text = config.text
        }
        field.keyboardType = config.keyboard
        field.accessibilityLabel = config.label
    }
}

struct ActionRowConfiguration: UIContentConfiguration {
    var title: String = ""
    var destructive: Bool = false
    var enabled: Bool = true
    var onTap: (() -> Void)?

    func makeContentView() -> UIView & UIContentView { ActionRowView(configuration: self) }
    func updated(for state: UIConfigurationState) -> Self { self }
}

final class ActionRowView: UIView, UIContentView {
    var configuration: UIContentConfiguration {
        didSet { apply() }
    }

    private let button = UIButton(type: .system)

    init(configuration: ActionRowConfiguration) {
        self.configuration = configuration
        super.init(frame: .zero)
        button.addTarget(self, action: #selector(tap), for: .touchUpInside)
        addSubview(button)
        button.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            button.topAnchor.constraint(equalTo: topAnchor),
            button.bottomAnchor.constraint(equalTo: bottomAnchor),
            button.leadingAnchor.constraint(equalTo: leadingAnchor),
            button.trailingAnchor.constraint(equalTo: trailingAnchor),
            button.heightAnchor.constraint(greaterThanOrEqualToConstant: 44)
        ])
        apply()
    }

    required init?(coder: NSCoder) { preconditionFailure("Storyboards are not used.") }

    @objc private func tap() {
        (configuration as? ActionRowConfiguration)?.onTap?()
    }

    private func apply() {
        guard let config = configuration as? ActionRowConfiguration else { return }
        var style = UIButton.Configuration.filled()
        style.baseBackgroundColor = config.destructive ? InstrumentPalette.ink : InstrumentPalette.accent
        style.baseForegroundColor = config.destructive ? InstrumentPalette.surface : InstrumentPalette.ink
        style.title = config.title
        style.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16)
        button.configuration = style
        button.isEnabled = config.enabled
        button.accessibilityLabel = config.title
    }
}
