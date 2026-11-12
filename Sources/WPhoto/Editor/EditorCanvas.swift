import AppKit

protocol EditorCanvasDelegate: AnyObject {
    func canvasFinished(_ annotation: Annotation)
    func canvasObscure(_ rect: CGRect, pixelate: Bool)
    func canvasRequestText(at point: CGPoint)
    func canvasCropChanged()
    func canvasApplyCrop()
    func canvasKeyDown(_ event: NSEvent) -> Bool
}

/// Холст правки: рисунок вписан в окно, поверх — то, что рисуется сейчас, и рамка обрезки.
final class EditorCanvas: NSView {
    weak var delegate: EditorCanvasDelegate?

    private let imageLayer = CALayer()
    private let overlay = OverlayView()
    private var imageSize = CGSize(width: 1, height: 1)

    var tool: EditTool = .pen {
        didSet {
            if oldValue == .crop, tool != .crop { cropRect = nil }
            current = nil
            overlay.needsDisplay = true
            window?.invalidateCursorRects(for: self)
        }
    }
    var color = NSColor(hex: 0xE02424)
    /// Толщина в точках экрана; в пиксели рисунка переводится при рисовании.
    var size: CGFloat = 4
    var fill = false
    /// Пропорции рамки обрезки (ширина / высота); nil — свободно.
    var cropRatio: CGFloat? {
        didSet { if let r = cropRatio { cropRect = fittedCrop(ratio: r) } }
    }
    private(set) var cropRect: CGRect? {
        didSet {
            overlay.needsDisplay = true
            delegate?.canvasCropChanged()
        }
    }

    private var current: Annotation?
    private var dragStart: CGPoint?
    private var obscureRect: CGRect?
    private enum CropDrag { case create(anchor: CGPoint), move(origin: CGPoint, start: CGRect), corner(anchor: CGPoint), edge(Int, start: CGRect) }
    private var cropDrag: CropDrag?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor(hex: 0x5A6170).cgColor
        imageLayer.contentsGravity = .resize
        imageLayer.minificationFilter = .trilinear
        imageLayer.magnificationFilter = .nearest
        imageLayer.shadowOpacity = 0.35
        imageLayer.shadowRadius = 6
        imageLayer.shadowOffset = CGSize(width: 0, height: -2)
        imageLayer.actions = ["bounds": NSNull(), "position": NSNull(), "contents": NSNull(), "frame": NSNull()]
        layer?.addSublayer(imageLayer)
        overlay.canvas = self
        addSubview(overlay)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    func setImage(_ image: CGImage, size: CGSize) {
        let changed = size != imageSize
        imageSize = size
        imageLayer.contents = image
        if changed { cropRect = nil }
        needsLayout = true
        layoutImage()
    }

    /// Предпросмотр коррекции (уменьшенная копия) вместо рисунка; размер рисунка тот же.
    func setPreview(_ image: CGImage) {
        imageLayer.contents = image
    }

    // MARK: - Геометрия

    /// Где рисунок на экране: вписан с полями, крупнее точки на пиксель не растягивается.
    var imageRect: CGRect {
        let area = bounds.insetBy(dx: 24, dy: 24)
        guard area.width > 0, area.height > 0 else { return .zero }
        let scale = min(1, min(area.width / imageSize.width, area.height / imageSize.height))
        let w = imageSize.width * scale, h = imageSize.height * scale
        return CGRect(x: (bounds.midX - w / 2).rounded(), y: (bounds.midY - h / 2).rounded(), width: w, height: h)
    }

    /// Точек экрана на пиксель рисунка.
    var viewScale: CGFloat { imageRect.width / imageSize.width }

    func toImage(_ p: NSPoint) -> CGPoint {
        let r = imageRect
        return CGPoint(x: (p.x - r.minX) / viewScale, y: (p.y - r.minY) / viewScale)
    }

    func toView(_ r: CGRect) -> CGRect {
        let o = imageRect.origin, s = viewScale
        return CGRect(x: o.x + r.minX * s, y: o.y + r.minY * s, width: r.width * s, height: r.height * s)
    }

    private func clampToImage(_ p: CGPoint) -> CGPoint {
        CGPoint(x: min(max(0, p.x), imageSize.width), y: min(max(0, p.y), imageSize.height))
    }

    override func layout() {
        super.layout()
        layoutImage()
    }

    private func layoutImage() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        imageLayer.frame = imageRect
        CATransaction.commit()
        overlay.frame = bounds
        overlay.needsDisplay = true
    }

    // MARK: - Мышь

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let p = toImage(convert(event.locationInWindow, from: nil))
        switch tool {
        case .crop:
            beginCrop(at: convert(event.locationInWindow, from: nil), image: p)
        case .text:
            guard bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
            delegate?.canvasRequestText(at: p)
        case .blur, .pixelate:
            dragStart = clampToImage(p)
            obscureRect = nil
        default:
            current = Annotation(tool: tool, points: [p, p], color: color, width: size / viewScale, fill: fill && tool.canFill)
            if tool.isStroke { current?.points = [p] }
        }
        overlay.needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        var p = toImage(convert(event.locationInWindow, from: nil))
        switch tool {
        case .crop:
            dragCrop(to: p)
        case .blur, .pixelate:
            guard let start = dragStart else { return }
            p = clampToImage(p)
            obscureRect = CGRect(x: min(start.x, p.x), y: min(start.y, p.y), width: abs(p.x - start.x), height: abs(p.y - start.y))
        default:
            guard var a = current else { return }
            if a.tool.isStroke {
                a.points.append(p)
            } else {
                if event.modifierFlags.contains(.shift) { p = constrained(from: a.points[0], to: p, tool: a.tool) }
                a.points[a.points.count - 1] = p
            }
            current = a
        }
        overlay.needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        switch tool {
        case .crop:
            cropDrag = nil
            if let r = cropRect, r.width < 4 || r.height < 4 { cropRect = nil }
        case .blur, .pixelate:
            if let r = obscureRect, r.width >= 3, r.height >= 3 {
                delegate?.canvasObscure(r, pixelate: tool == .pixelate)
            }
            obscureRect = nil
            dragStart = nil
        default:
            if let a = current {
                let moved = a.tool.isStroke || hypot(a.points[0].x - a.points[1].x, a.points[0].y - a.points[1].y) * viewScale > 2
                if moved { delegate?.canvasFinished(a) }
            }
            current = nil
        }
        overlay.needsDisplay = true
    }

    override func mouseMoved(with event: NSEvent) {}

    /// Shift: квадрат, круг, линия под углом, кратным 45°.
    private func constrained(from a: CGPoint, to b: CGPoint, tool: EditTool) -> CGPoint {
        let dx = b.x - a.x, dy = b.y - a.y
        if tool == .rectangle || tool == .ellipse {
            let side = max(abs(dx), abs(dy))
            return CGPoint(x: a.x + side * (dx < 0 ? -1 : 1), y: a.y + side * (dy < 0 ? -1 : 1))
        }
        let angle = (atan2(dy, dx) / (.pi / 4)).rounded() * (.pi / 4)
        let length = hypot(dx, dy)
        return CGPoint(x: a.x + cos(angle) * length, y: a.y + sin(angle) * length)
    }

    override func resetCursorRects() {
        let cursor: NSCursor
        switch tool {
        case .text: cursor = .iBeam
        case .crop, .blur, .pixelate, .rectangle, .ellipse, .line, .arrow: cursor = .crosshair
        default: cursor = .crosshair
        }
        addCursorRect(imageRect, cursor: cursor)
    }

    override func keyDown(with event: NSEvent) {
        if delegate?.canvasKeyDown(event) != true { super.keyDown(with: event) }
    }

    // MARK: - Обрезка

    /// Самая большая рамка нужных пропорций по центру рисунка.
    private func fittedCrop(ratio: CGFloat) -> CGRect {
        var w = imageSize.width, h = w / ratio
        if h > imageSize.height { h = imageSize.height; w = h * ratio }
        return CGRect(x: (imageSize.width - w) / 2, y: (imageSize.height - h) / 2, width: w, height: h)
    }

    func clearCrop() { cropRect = nil }

    func selectAllCrop() {
        cropRect = cropRatio.map(fittedCrop) ?? CGRect(origin: .zero, size: imageSize)
    }

    /// Ручки рамки в точках экрана: 0–3 углы (лн, пн, пв, лв), 4–7 стороны (н, п, в, л).
    private func handles(_ r: CGRect) -> [CGPoint] {
        [CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.maxX, y: r.minY), CGPoint(x: r.maxX, y: r.maxY), CGPoint(x: r.minX, y: r.maxY),
         CGPoint(x: r.midX, y: r.minY), CGPoint(x: r.maxX, y: r.midY), CGPoint(x: r.midX, y: r.maxY), CGPoint(x: r.minX, y: r.midY)]
    }

    private func beginCrop(at viewPoint: NSPoint, image p: CGPoint) {
        if let r = cropRect {
            let v = toView(r)
            let hs = handles(v)
            let count = cropRatio == nil ? 8 : 4
            if let i = (0..<count).first(where: { hypot(hs[$0].x - viewPoint.x, hs[$0].y - viewPoint.y) < 9 }) {
                if i < 4 {
                    let opposite = handles(r)[(i + 2) % 4]
                    cropDrag = .corner(anchor: opposite)
                } else {
                    cropDrag = .edge(i - 4, start: r)
                }
                return
            }
            if v.contains(viewPoint) {
                cropDrag = .move(origin: p, start: r)
                return
            }
        }
        let anchor = clampToImage(p)
        cropDrag = .create(anchor: anchor)
        cropRect = CGRect(origin: anchor, size: .zero)
    }

    private func dragCrop(to raw: CGPoint) {
        guard let drag = cropDrag else { return }
        let p = clampToImage(raw)
        switch drag {
        case .create(let anchor), .corner(let anchor):
            cropRect = rect(anchor: anchor, to: p)
        case .move(let origin, let start):
            var r = start.offsetBy(dx: raw.x - origin.x, dy: raw.y - origin.y)
            r.origin.x = min(max(0, r.minX), imageSize.width - r.width)
            r.origin.y = min(max(0, r.minY), imageSize.height - r.height)
            cropRect = r
        case .edge(let side, let start):
            var r = start
            switch side {
            case 0: r = CGRect(x: r.minX, y: min(p.y, r.maxY), width: r.width, height: abs(r.maxY - p.y))
            case 1: r = CGRect(x: min(r.minX, p.x), y: r.minY, width: abs(p.x - r.minX), height: r.height)
            case 2: r = CGRect(x: r.minX, y: min(r.minY, p.y), width: r.width, height: abs(p.y - r.minY))
            default: r = CGRect(x: min(p.x, r.maxX), y: r.minY, width: abs(r.maxX - p.x), height: r.height)
            }
            cropRect = r
        }
    }

    /// Рамка от неподвижного угла до курсора, с пропорциями, если они заданы.
    private func rect(anchor a: CGPoint, to p: CGPoint) -> CGRect {
        var w = abs(p.x - a.x), h = abs(p.y - a.y)
        if let ratio = cropRatio {
            if w / max(h, 0.001) > ratio { w = h * ratio } else { h = w / ratio }
            // Не выходить за рисунок.
            let maxW = p.x >= a.x ? imageSize.width - a.x : a.x
            let maxH = p.y >= a.y ? imageSize.height - a.y : a.y
            if w > maxW { w = maxW; h = w / ratio }
            if h > maxH { h = maxH; w = h * ratio }
        }
        return CGRect(x: p.x >= a.x ? a.x : a.x - w, y: p.y >= a.y ? a.y : a.y - h, width: w, height: h)
    }

    // MARK: - Слой поверх рисунка

    fileprivate func drawOverlay() {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let r = imageRect
        if let a = current {
            ctx.saveGState()
            ctx.clip(to: r)
            ctx.translateBy(x: r.minX, y: r.minY)
            ctx.scaleBy(x: viewScale, y: viewScale)
            var preview = a
            if preview.tool == .highlighter { preview.color = preview.color.withAlphaComponent(1) }
            preview.draw(in: ctx)
            ctx.restoreGState()
        }
        if let o = obscureRect {
            let v = toView(o)
            NSColor(white: 1, alpha: 0.25).setFill()
            v.fill()
            dashed(v, color: .white)
        }
        if tool == .crop, let c = cropRect {
            let v = toView(c)
            // Затемнить всё вне рамки.
            let shade = NSBezierPath(rect: r)
            shade.append(NSBezierPath(rect: v).reversed)
            NSColor(white: 0, alpha: 0.5).setFill()
            shade.fill()
            NSColor.white.setStroke()
            let border = NSBezierPath(rect: v.insetBy(dx: 0.5, dy: 0.5))
            border.lineWidth = 1
            border.stroke()
            // Сетка третей.
            let thirds = NSBezierPath()
            for i in 1...2 {
                let x = v.minX + v.width * CGFloat(i) / 3, y = v.minY + v.height * CGFloat(i) / 3
                thirds.move(to: NSPoint(x: x, y: v.minY)); thirds.line(to: NSPoint(x: x, y: v.maxY))
                thirds.move(to: NSPoint(x: v.minX, y: y)); thirds.line(to: NSPoint(x: v.maxX, y: y))
            }
            NSColor(white: 1, alpha: 0.45).setStroke()
            thirds.lineWidth = 0.5
            thirds.stroke()
            let count = cropRatio == nil ? 8 : 4
            for h in handles(v).prefix(count) {
                let box = NSRect(x: h.x - 4, y: h.y - 4, width: 8, height: 8)
                NSColor.white.setFill()
                box.fill()
                NSColor(hex: 0x2F5C93).setStroke()
                NSBezierPath(rect: box.insetBy(dx: 0.5, dy: 0.5)).stroke()
            }
        }
    }

    private func dashed(_ rect: CGRect, color: NSColor) {
        let path = NSBezierPath(rect: rect.insetBy(dx: 0.5, dy: 0.5))
        path.setLineDash([5, 3], count: 2, phase: 0)
        color.setStroke()
        path.stroke()
    }
}

/// Прозрачный вид над слоем рисунка — для предпросмотра и рамок.
private final class OverlayView: NSView {
    weak var canvas: EditorCanvas?

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        canvas?.drawOverlay()
    }
}
