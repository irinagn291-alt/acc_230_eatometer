import UIKit

/// Role: the only type scale. Baskerville for prose; Baskerville with monospaced digits for readings.
enum InstrumentTypography {
    enum Step: Int, CaseIterable {
        case caption
        case body
        case title
        case display
        case gauge
        case hero

        var pointSize: CGFloat {
            switch self {
            case .caption: 13
            case .body: 17
            case .title: 22
            case .display: 28
            case .gauge: 40
            case .hero: 56
            }
        }

        var textStyle: UIFont.TextStyle {
            switch self {
            case .caption: .caption1
            case .body: .body
            case .title: .title2
            case .display: .title1
            case .gauge: .largeTitle
            case .hero: .largeTitle
            }
        }
    }

    static func prose(_ step: Step) -> UIFont {
        scaled(face(step.pointSize, bold: step == .title || step == .display), step: step)
    }

    static func reading(_ step: Step) -> UIFont {
        let base = face(step.pointSize, bold: step == .gauge || step == .hero)
        let descriptor = base.fontDescriptor.addingAttributes([
            .featureSettings: [[
                UIFontDescriptor.FeatureKey.type: kNumberSpacingType,
                UIFontDescriptor.FeatureKey.selector: kMonospacedNumbersSelector
            ]]
        ])
        return scaled(UIFont(descriptor: descriptor, size: step.pointSize), step: step)
    }

    private static let family = "Baskerville"

    private static func face(_ size: CGFloat, bold: Bool) -> UIFont {
        let name = bold ? "Baskerville-Bold" : family
        return UIFont(name: name, size: size) ?? UIFont.systemFont(ofSize: size, weight: bold ? .bold : .regular)
    }

    private static func scaled(_ font: UIFont, step: Step) -> UIFont {
        UIFontMetrics(forTextStyle: step.textStyle).scaledFont(for: font)
    }
}
