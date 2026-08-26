import UIKit

/// Role: hand-drawn analytics traces. CALayer + UIBezierPath, never images.
final class TrendTraceLayer: CALayer {
    var values: [CGFloat] = [] {
        didSet { setNeedsDisplay() }
    }
    var strokeColor: CGColor = InstrumentPalette.accent.cgColor
    var gridColor: CGColor = InstrumentPalette.muted.withAlphaComponent(0.35).cgColor

    override func draw(in ctx: CGContext) {
        UIGraphicsPushContext(ctx)
        let bounds = self.bounds
        let grid = UIBezierPath()
        for step in 0...4 {
            let y = bounds.height * CGFloat(step) / 4
            grid.move(to: CGPoint(x: 0, y: y))
            grid.addLine(to: CGPoint(x: bounds.width, y: y))
        }
        ctx.setStrokeColor(gridColor)
        ctx.setLineWidth(1)
        ctx.addPath(grid.cgPath)
        ctx.strokePath()

        guard values.count > 1 else {
            UIGraphicsPopContext()
            return
        }
        let maxValue = max(values.max() ?? 1, 1)
        let path = UIBezierPath()
        for (index, value) in values.enumerated() {
            let x = bounds.width * CGFloat(index) / CGFloat(values.count - 1)
            let y = bounds.height - (CGFloat(value) / maxValue) * bounds.height
            let point = CGPoint(x: x, y: y)
            if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        ctx.setStrokeColor(strokeColor)
        ctx.setLineWidth(2)
        ctx.addPath(path.cgPath)
        ctx.strokePath()
        UIGraphicsPopContext()
    }
}

final class BarTraceLayer: CALayer {
    var values: [CGFloat] = [] {
        didSet { setNeedsDisplay() }
    }
    var fillColor: CGColor = InstrumentPalette.accent.cgColor

    override func draw(in ctx: CGContext) {
        UIGraphicsPushContext(ctx)
        let bounds = self.bounds
        guard !values.isEmpty else {
            UIGraphicsPopContext()
            return
        }
        let maxValue = max(values.max() ?? 1, 1)
        let gap: CGFloat = 4
        let width = max((bounds.width - gap * CGFloat(values.count + 1)) / CGFloat(values.count), 2)
        for (index, value) in values.enumerated() {
            let height = (CGFloat(value) / maxValue) * bounds.height
            let x = gap + CGFloat(index) * (width + gap)
            let rect = CGRect(x: x, y: bounds.height - height, width: width, height: height)
            let path = UIBezierPath(rect: rect)
            ctx.setFillColor(fillColor)
            ctx.addPath(path.cgPath)
            ctx.fillPath()
        }
        UIGraphicsPopContext()
    }
}

final class DonutTraceLayer: CALayer {
    var protein: CGFloat = 0
    var carbs: CGFloat = 0
    var fat: CGFloat = 0

    override func draw(in ctx: CGContext) {
        UIGraphicsPushContext(ctx)
        let total = max(protein + carbs + fat, 1)
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let radius = min(bounds.width, bounds.height) / 2 - 8
        var start: CGFloat = -.pi / 2
        let slices: [(CGFloat, UIColor)] = [
            (protein / total, InstrumentPalette.ink),
            (carbs / total, InstrumentPalette.accent),
            (fat / total, InstrumentPalette.muted)
        ]
        for (fraction, color) in slices {
            let end = start + fraction * .pi * 2
            let path = UIBezierPath(arcCenter: center, radius: radius, startAngle: start, endAngle: end, clockwise: true)
            path.addLine(to: center)
            path.close()
            ctx.setFillColor(color.cgColor)
            ctx.addPath(path.cgPath)
            ctx.fillPath()
            start = end
        }
        let hole = UIBezierPath(arcCenter: center, radius: radius * 0.55, startAngle: 0, endAngle: .pi * 2, clockwise: true)
        ctx.setFillColor(InstrumentPalette.surface.cgColor)
        ctx.addPath(hole.cgPath)
        ctx.fillPath()
        UIGraphicsPopContext()
    }
}

final class ChartHostView: UIView {
    enum Kind { case trend, bars, donut }
    private let kind: Kind
    private let trend = TrendTraceLayer()
    private let bars = BarTraceLayer()
    private let donut = DonutTraceLayer()

    init(kind: Kind) {
        self.kind = kind
        super.init(frame: .zero)
        backgroundColor = InstrumentPalette.surface
        isAccessibilityElement = true
        switch kind {
        case .trend:
            layer.addSublayer(trend)
        case .bars:
            layer.addSublayer(bars)
        case .donut:
            layer.addSublayer(donut)
        }
    }

    required init?(coder: NSCoder) { preconditionFailure("Storyboards are not used.") }

    override func layoutSubviews() {
        super.layoutSubviews()
        let target = bounds
        switch kind {
        case .trend:
            trend.frame = target
            trend.contentsScale = traitCollection.displayScale
            trend.setNeedsDisplay()
        case .bars:
            bars.frame = target
            bars.contentsScale = traitCollection.displayScale
            bars.setNeedsDisplay()
        case .donut:
            donut.frame = target
            donut.contentsScale = traitCollection.displayScale
            donut.setNeedsDisplay()
        }
    }

    func setTrend(_ values: [CGFloat]) {
        trend.values = values
        accessibilityLabel = "Energy trend"
    }

    func setBars(_ values: [CGFloat]) {
        bars.values = values
        accessibilityLabel = "Weekday averages"
    }

    func setDonut(protein: CGFloat, carbs: CGFloat, fat: CGFloat) {
        donut.protein = protein
        donut.carbs = carbs
        donut.fat = fat
        donut.setNeedsDisplay()
        accessibilityLabel = "Macro split"
    }
}

struct ChartCardConfiguration: UIContentConfiguration {
    var title: String = ""
    var kind: ChartHostView.Kind = .trend
    var values: [CGFloat] = []
    var protein: CGFloat = 0
    var carbs: CGFloat = 0
    var fat: CGFloat = 0
    var footnote: String = ""

    func makeContentView() -> UIView & UIContentView { ChartCardView(configuration: self) }
    func updated(for state: UIConfigurationState) -> Self { self }
}

final class ChartCardView: UIView, UIContentView {
    var configuration: UIContentConfiguration {
        didSet { apply() }
    }

    private let title = UILabel()
    private let footnote = UILabel()
    private var chart: ChartHostView?

    init(configuration: ChartCardConfiguration) {
        self.configuration = configuration
        super.init(frame: .zero)
        backgroundColor = InstrumentPalette.surface
        layer.borderWidth = 1
        layer.borderColor = InstrumentPalette.muted.withAlphaComponent(0.35).cgColor
        title.font = InstrumentTypography.prose(.title)
        title.textColor = InstrumentPalette.ink
        title.adjustsFontForContentSizeCategory = true
        title.numberOfLines = 0
        footnote.font = InstrumentTypography.prose(.caption)
        footnote.textColor = InstrumentPalette.muted
        footnote.adjustsFontForContentSizeCategory = true
        footnote.numberOfLines = 0
        addSubview(title)
        addSubview(footnote)
        title.translatesAutoresizingMaskIntoConstraints = false
        footnote.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: topAnchor, constant: InstrumentSpace.x(1.5)),
            title.leadingAnchor.constraint(equalTo: leadingAnchor, constant: InstrumentSpace.x(1.5)),
            title.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -InstrumentSpace.x(1.5)),
            footnote.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            footnote.trailingAnchor.constraint(equalTo: title.trailingAnchor),
            footnote.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -InstrumentSpace.x(1.5))
        ])
        apply()
    }

    required init?(coder: NSCoder) { preconditionFailure("Storyboards are not used.") }

    private func apply() {
        guard let config = configuration as? ChartCardConfiguration else { return }
        title.text = config.title
        footnote.text = config.footnote
        chart?.removeFromSuperview()
        let host = ChartHostView(kind: config.kind)
        chart = host
        addSubview(host)
        host.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            host.topAnchor.constraint(equalTo: title.bottomAnchor, constant: InstrumentSpace.x(1)),
            host.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            host.trailingAnchor.constraint(equalTo: title.trailingAnchor),
            host.bottomAnchor.constraint(equalTo: footnote.topAnchor, constant: -InstrumentSpace.x(1)),
            host.heightAnchor.constraint(equalToConstant: 180)
        ])
        switch config.kind {
        case .trend: host.setTrend(config.values)
        case .bars: host.setBars(config.values)
        case .donut: host.setDonut(protein: config.protein, carbs: config.carbs, fat: config.fat)
        }
    }
}
