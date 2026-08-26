import UIKit

enum InstrumentSpace {
    static let unit: CGFloat = 8
    static func x(_ n: CGFloat) -> CGFloat { unit * n }
}

@MainActor
enum InstrumentMotion {
    static let duration: TimeInterval = 0.28
    static let options: UIView.AnimationOptions = .curveEaseInOut

    static var reduce: Bool {
        UIAccessibility.isReduceMotionEnabled
    }
}

@MainActor
enum InstrumentHaptics {
    static func commit() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}

@MainActor
enum InstrumentFormatters {
    private static let energyFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        formatter.minimumFractionDigits = 0
        return formatter
    }()

    private static let macroFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 1
        formatter.minimumFractionDigits = 0
        return formatter
    }()

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    static func energy(_ value: Double) -> String {
        energyFormatter.string(from: NSNumber(value: value.rounded())) ?? "0"
    }

    static func macro(_ value: Double?) -> String {
        guard let value else { return "—" }
        return macroFormatter.string(from: NSNumber(value: value)) ?? "—"
    }

    static func dayTitle(_ key: String) -> String {
        guard let date = DayKey.date(from: key) else { return key }
        return dayFormatter.string(from: date)
    }

    static func unknownEnergy(_ value: Double?) -> String {
        guard let value else { return "unknown" }
        return energy(value)
    }
}

@MainActor
enum InstrumentLayout {
    static func list(estimated: CGFloat) -> UICollectionViewCompositionalLayout {
        UICollectionViewCompositionalLayout { _, _ in
            let item = NSCollectionLayoutItem(
                layoutSize: NSCollectionLayoutSize(
                    widthDimension: .fractionalWidth(1),
                    heightDimension: .estimated(estimated)
                )
            )
            let group = NSCollectionLayoutGroup.vertical(
                layoutSize: NSCollectionLayoutSize(
                    widthDimension: .fractionalWidth(1),
                    heightDimension: .estimated(estimated)
                ),
                subitems: [item]
            )
            let section = NSCollectionLayoutSection(group: group)
            section.interGroupSpacing = InstrumentSpace.x(1)
            section.contentInsets = NSDirectionalEdgeInsets(
                top: InstrumentSpace.x(1),
                leading: InstrumentSpace.x(2),
                bottom: InstrumentSpace.x(1),
                trailing: InstrumentSpace.x(2)
            )
            return section
        }
    }
}

final class DialCell: UICollectionViewCell {
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundConfiguration = .clear()
    }

    required init?(coder: NSCoder) {
        // Programmer error: cells are registered in code.
        preconditionFailure("Storyboards are not used.")
    }
}

actor PlateImageCache {
    static let shared = PlateImageCache()
    private var memory: [URL: Data] = [:]

    func data(for url: URL) async -> Data? {
        if let cached = memory[url] { return cached }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            memory[url] = data
            return data
        } catch {
            return nil
        }
    }
}

extension UIView {
    func findFirstResponder() -> UIView? {
        if isFirstResponder { return self }
        for child in subviews {
            if let found = child.findFirstResponder() { return found }
        }
        return nil
    }
}

@MainActor
enum SpecimenImagery {
    static func apply(to view: UIImageView, recordName: String?, url: String?, shelf: String?) {
        view.image = UIImage(named: "etm_ProductPlaceholder")
        view.accessibilityLabel = recordName
        if let shelf, let bundled = UIImage(named: shelf) {
            view.image = bundled
        }
        guard let url, let remote = URL(string: url) else { return }
        Task {
            if let data = await PlateImageCache.shared.data(for: remote),
               let image = UIImage(data: data) {
                view.image = image
            }
        }
    }
}
