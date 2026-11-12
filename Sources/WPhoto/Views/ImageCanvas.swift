import AppKit

protocol ImageCanvasDelegate: AnyObject {
    func canvasNeedsFullResolution(_ canvas: ImageCanvas)
    func canvasZoomChanged(_ canvas: ImageCanvas)
    func canvasMenu(_ canvas: ImageCanvas) -> NSMenu?
    func canvasDropped(_ urls: [URL])
    /// +1 — следующий рисунок, −1 — предыдущий (колесо в режиме листания, жест трекпада).
    func canvasStep(_ delta: Int)
    func canvasKeyDown(_ event: NSEvent) -> Bool
}

/// Область рисунка. Сам рисунок — слой с готовой картинкой: масштаб, сдвиг и поворот —
/// это смена геометрии слоя, без перерисовки, поэтому всё плавно даже на больших фото.
///
/// Масштаб `zoom` — сколько пикселей экрана приходится на пиксель рисунка (1 — «реальный
/// размер»); nil — «по размеру окна»: рисунок вписывается в окно, но не растягивается.
final class ImageCanvas: NSView {
    weak var delegate: ImageCanvasDelegate?

    private let imageLayer = CALayer()
    private(set) var image: DecodedImage?
    /// Поворот на экране, четверти оборота по часовой стрелке.
    private(set) var rotation = 0
    private(set) var zoom: CGFloat?
    private var offset = CGPoint.zero
    private var dragOrigin: NSPoint?
    private var offsetAtDrag = CGPoint.zero
    private var swipeAccum: CGFloat = 0
    private var swipeFired = false

    let maxZoom: CGFloat = 16

    var message: String? {
        didSet { needsDisplay = true }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
        imageLayer.contentsGravity = .resize
        imageLayer.minificationFilter = .trilinear
        imageLayer.actions = ["bounds": NSNull(), "position": NSNull(), "transform": NSNull(),
                              "contents": NSNull(), "hidden": NSNull()]
        imageLayer.isHidden = true
        layer?.addSublayer(imageLayer)
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { false }
    override var acceptsFirstResponder: Bool { true }
    override var isOpaque: Bool { true }

    private var scale: CGFloat { window?.backingScaleFactor ?? 2 }

    // MARK: - Рисунок

    func show(_ newImage: DecodedImage?, rotation newRotation: Int) {
        image = newImage
        rotation = newRotation
        zoom = nil
        offset = .zero
        if newImage != nil { message = nil }
        imageLayer.contents = newImage?.cgImage
        layoutImage()
        delegate?.canvasZoomChanged(self)
    }

    /// Тот же рисунок в лучшем качестве — масштаб и сдвиг сохраняются.
    func replace(_ newImage: DecodedImage) {
        image = newImage
        imageLayer.contents = newImage.cgImage
        layoutImage()
    }

    func setRotation(_ newRotation: Int) {
        rotation = ((newRotation % 4) + 4) % 4
        zoom = nil
        offset = .zero
        layoutImage()
        delegate?.canvasZoomChanged(self)
    }

    /// Размер рисунка на экране в пикселях оригинала — с учётом поворота.
    private var turnedSize: CGSize {
        guard let image else { return .zero }
        return rotation % 2 == 1
            ? CGSize(width: image.fullSize.height, height: image.fullSize.width)
            : image.fullSize
    }

    var fitZoom: CGFloat {
        let size = turnedSize
        guard size.width > 0, size.height > 0, bounds.width > 0, bounds.height > 0 else { return 1 }
        return min(1, min(bounds.width * scale / size.width, bounds.height * scale / size.height))
    }

    var currentZoom: CGFloat { zoom ?? fitZoom }
    var isFit: Bool { zoom == nil }
    /// Рисунок меньше окна: «реальный размер» и «по размеру окна» совпадают.
    var fitIsActualSize: Bool { fitZoom >= 1 }

    private var displayedSize: CGSize {
        let size = turnedSize
        let z = currentZoom / scale
        return CGSize(width: size.width * z, height: size.height * z)
    }

    var canPan: Bool {
        let size = displayedSize
        return size.width > bounds.width + 0.5 || size.height > bounds.height + 0.5
    }

    private func clampOffset() {
        let size = displayedSize
        let mx = max(0, (size.width - bounds.width) / 2)
        let my = max(0, (size.height - bounds.height) / 2)
        offset.x = min(mx, max(-mx, offset.x))
        offset.y = min(my, max(-my, offset.y))
    }

    override func layout() {
        super.layout()
        layoutImage()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        layoutImage()
    }

    private func layoutImage() {
        guard let image else {
            imageLayer.isHidden = true
            return
        }
        let z = currentZoom
        clampOffset()
        let shown = displayedSize
        // Левый нижний угол — на целый пиксель экрана, иначе «реальный размер» размыт.
        let ox = ((bounds.midX + offset.x - shown.width / 2) * scale).rounded() / scale
        let oy = ((bounds.midY + offset.y - shown.height / 2) * scale).rounded() / scale
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        imageLayer.isHidden = false
        imageLayer.bounds = CGRect(x: 0, y: 0,
                                   width: image.fullSize.width * z / scale,
                                   height: image.fullSize.height * z / scale)
        imageLayer.position = CGPoint(x: ox + shown.width / 2, y: oy + shown.height / 2)
        imageLayer.transform = CATransform3DMakeRotation(-CGFloat(rotation) * .pi / 2, 0, 0, 1)
        imageLayer.magnificationFilter = z >= 3 ? .nearest : .linear
        CATransaction.commit()
        window?.invalidateCursorRects(for: self)
        if !image.isFull, !image.isPreview,
           max(image.fullSize.width, image.fullSize.height) * z > CGFloat(max(image.cgImage.width, image.cgImage.height)) * 1.02 {
            delegate?.canvasNeedsFullResolution(self)
        }
    }

    // MARK: - Масштаб

    /// nil — «по размеру окна». `anchor` — точка, которая остаётся под курсором.
    func setZoom(_ value: CGFloat?, anchor: NSPoint? = nil) {
        guard image != nil else { return }
        let old = currentZoom
        let fit = fitZoom
        var target = value.map { min(maxZoom, max(fit, $0)) }
        if let t = target, t <= fit * 1.0001 { target = nil }
        let new = target ?? fit
        if target == nil {
            offset = .zero
        } else {
            let point = anchor ?? NSPoint(x: bounds.midX, y: bounds.midY)
            let ratio = new / old
            let dx = point.x - bounds.midX, dy = point.y - bounds.midY
            offset = CGPoint(x: dx - (dx - offset.x) * ratio, y: dy - (dy - offset.y) * ratio)
        }
        zoom = target
        layoutImage()
        delegate?.canvasZoomChanged(self)
    }

    func zoomIn(anchor: NSPoint? = nil) { setZoom(currentZoom * 1.25, anchor: anchor) }
    func zoomOut(anchor: NSPoint? = nil) { setZoom(currentZoom / 1.25, anchor: anchor) }
    func fitToWindow() { setZoom(nil) }
    func actualSize(anchor: NSPoint? = nil) { setZoom(1, anchor: anchor) }

    /// Как кнопка Windows: из «по размеру окна» — в реальный размер, иначе обратно.
    func toggleFit(anchor: NSPoint? = nil) {
        if isFit, !fitIsActualSize { actualSize(anchor: anchor) } else { fitToWindow() }
    }

    func pan(dx: CGFloat, dy: CGFloat) {
        guard canPan else { return }
        offset.x += dx
        offset.y += dy
        layoutImage()
    }

    // MARK: - Мышь и трекпад

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let point = convert(event.locationInWindow, from: nil)
        if event.clickCount == 2 {
            toggleFit(anchor: point)
            return
        }
        guard canPan else { return }
        dragOrigin = event.locationInWindow
        offsetAtDrag = offset
        NSCursor.closedHand.set()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let origin = dragOrigin else { return }
        offset = CGPoint(x: offsetAtDrag.x + event.locationInWindow.x - origin.x,
                         y: offsetAtDrag.y + event.locationInWindow.y - origin.y)
        layoutImage()
    }

    override func mouseUp(with event: NSEvent) {
        dragOrigin = nil
        window?.invalidateCursorRects(for: self)
    }

    override func resetCursorRects() {
        if canPan { addCursorRect(bounds, cursor: .openHand) }
    }

    override func scrollWheel(with event: NSEvent) {
        guard image != nil else { return }
        let point = convert(event.locationInWindow, from: nil)
        let zoomModifier = !event.modifierFlags.intersection([.command, .option, .control]).isEmpty
        if event.hasPreciseScrollingDeltas, !zoomModifier {
            // Трекпад и Magic Mouse: прокрутка двигает рисунок, а если двигать нечего —
            // смахивание вбок листает.
            if canPan {
                pan(dx: event.scrollingDeltaX, dy: -event.scrollingDeltaY)
            } else {
                if event.phase == .began {
                    swipeAccum = 0
                    swipeFired = false
                }
                guard event.momentumPhase.isEmpty else { return }
                swipeAccum += event.scrollingDeltaX
                if !swipeFired, abs(swipeAccum) > 60, abs(event.scrollingDeltaX) >= abs(event.scrollingDeltaY) {
                    swipeFired = true
                    delegate?.canvasStep(swipeAccum > 0 ? -1 : 1)
                }
            }
            return
        }
        if Settings.wheel == .navigate, !zoomModifier {
            let delta = event.scrollingDeltaY
            if delta != 0 { delegate?.canvasStep(delta > 0 ? -1 : 1) }
            return
        }
        let delta = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY / 25 : event.scrollingDeltaY
        guard delta != 0 else { return }
        setZoom(currentZoom * pow(1.2, max(-3, min(3, delta))), anchor: point)
    }

    override func magnify(with event: NSEvent) {
        setZoom(currentZoom * (1 + event.magnification), anchor: convert(event.locationInWindow, from: nil))
    }

    override func smartMagnify(with event: NSEvent) {
        toggleFit(anchor: convert(event.locationInWindow, from: nil))
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        delegate?.canvasMenu(self)
    }

    override func keyDown(with event: NSEvent) {
        if delegate?.canvasKeyDown(event) != true {
            super.keyDown(with: event)
        }
    }

    // MARK: - Перетаскивание файлов

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        sender.draggingPasteboard.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])
            ? .copy : []
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let urls = sender.draggingPasteboard.readObjects(
            forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty else { return false }
        delegate?.canvasDropped(urls)
        return true
    }

    // MARK: - Фон

    override func draw(_ dirtyRect: NSRect) {
        NSGradient(starting: Theme.canvasBottom, ending: Theme.canvasTop)?.draw(in: bounds, angle: 90)
        guard image == nil, let message else { return }
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        let text = NSAttributedString(string: message, attributes: [
            .font: NSFont.systemFont(ofSize: 14), .foregroundColor: Theme.messageColor, .paragraphStyle: style,
        ])
        let height = text.boundingRect(with: NSSize(width: bounds.width - 40, height: 1000),
                                       options: .usesLineFragmentOrigin).height
        text.draw(in: NSRect(x: 20, y: bounds.midY - height / 2, width: bounds.width - 40, height: height))
    }
}
