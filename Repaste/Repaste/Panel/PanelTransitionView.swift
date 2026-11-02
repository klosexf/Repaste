import AppKit

/// 外壳随窗口改变宽高，SwiftUI 内容始终按完整尺寸排版；遮罩负责逐步露出内容。
final class PanelTransitionView: NSView {
    override var isFlipped: Bool { true }
    private let shell = CAShapeLayer()
    private let clipping = CAShapeLayer()
    private var hosting: NSView
    var contentSize: CGSize
    private let panelRadius: CGFloat
    var progress: CGFloat = 1
    var isNotch = true
    var isCapsule = false

    init(hosting: NSView, contentWidth: CGFloat, cornerRadius: CGFloat) {
        self.hosting = hosting
        self.contentSize = CGSize(width: contentWidth, height: 290)
        self.panelRadius = cornerRadius
        super.init(frame: .zero)
        wantsLayer = true
        layer?.addSublayer(shell)
        layer?.mask = clipping
        autoresizingMask = [.width, .height]
        addSubview(hosting)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func replaceHosting(_ hosting: NSView) {
        self.hosting.removeFromSuperview()
        self.hosting = hosting
        addSubview(hosting)
        updateGeometry()
    }

    override func layout() {
        super.layout()
        updateGeometry()
    }

    func updateGeometry() {
        let p = min(1, max(0, progress))
        let radius = isNotch ? (isCapsule ? 5 : 13) + (panelRadius - (isCapsule ? 5 : 13)) * p : panelRadius
        let path = CGMutablePath()
        let rect = bounds
        let r = min(radius, min(rect.width, rect.height) / 2)
        if isNotch {
            path.move(to: .zero)
            path.addLine(to: CGPoint(x: rect.maxX, y: 0))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
            path.addQuadCurve(to: CGPoint(x: rect.maxX - r, y: rect.maxY), control: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: r, y: rect.maxY))
            path.addQuadCurve(to: CGPoint(x: 0, y: rect.maxY - r), control: CGPoint(x: 0, y: rect.maxY))
            path.closeSubpath()
        } else {
            path.addRoundedRect(in: rect, cornerWidth: r, cornerHeight: r)
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        shell.frame = bounds
        clipping.frame = bounds
        shell.path = path
        clipping.path = path
        let grey = isCapsule ? 1 - (1 - 10.0 / 255) * p : 10.0 / 255
        shell.fillColor = NSColor(white: grey, alpha: isCapsule ? 0.34 + 0.66 * p : 1).cgColor
        CATransaction.commit()
        hosting.autoresizingMask = []
        hosting.frame = CGRect(x: (bounds.width - contentSize.width) / 2,
                               y: isNotch ? -7 * (1 - p) : 0,
                               width: contentSize.width, height: contentSize.height)
        hosting.alphaValue = isNotch ? min(1, max(0, (p - 0.18) / 0.66)) : 1
    }
}

