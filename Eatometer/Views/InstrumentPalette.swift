import UIKit

/// Role: the only colour accessor. Hex values live here and nowhere else.
enum InstrumentPalette {
    static var background: UIColor { color("etm_background", 0xF8F5EE) }
    static var surface: UIColor { color("etm_surface", 0xFFFFFF) }
    static var ink: UIColor { color("etm_ink", 0x333333) }
    static var accent: UIColor { color("etm_accent", 0xC9A227) }
    static var muted: UIColor { color("etm_muted", 0x9B968C) }

    private static func color(_ name: String, _ hex: UInt32) -> UIColor {
        if let named = UIColor(named: name) { return named }
        return UIColor(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}
