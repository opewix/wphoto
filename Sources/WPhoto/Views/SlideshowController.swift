import AppKit

/// Показ слайдов на весь экран: чёрный фон, плавная смена, стрелки листают, пробел — пауза,
/// Esc — выход, правая кнопка — меню со скоростью, перемешиванием и повтором.
final class SlideshowController: NSObject {
    private let window: NSWindow
    private let view: SlideView
    private let source: [URL]
    private var order: [URL]
    private var position: Int
    private var timer: Timer?
    private var paused = false
    private var token = 0
    private var exiting = false
    private var savedOptions: NSApplication.PresentationOptions = []
    private let onExit: (URL?) -> Void
    private let screen: NSScreen

    init(urls: [URL], start: Int, screen: NSScreen, onExit: @escaping (URL?) -> Void) {
        source = urls
        order = urls
        position = start
        self.screen = screen
        self.onExit = onExit
        window = SlideWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        view = SlideView(frame: NSRect(origin: .zero, size: screen.frame.size))
        super.init()
        window.setFrame(screen.frame, display: false)
        window.backgroundColor = .black
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.fullScreenAuxiliary, .moveToActiveSpace]
        window.acceptsMouseMovedEvents = true
        window.contentView = view
        view.controller = self
        if Settings.slideShuffle { reshuffle() }
    }

    func start() {
        savedOptions = NSApp.presentationOptions
        if !savedOptions.contains(.fullScreen) {
            NSApp.presentationOptions = [.hideDock, .hideMenuBar]
        }
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(view)
        NSCursor.setHiddenUntilMouseMoves(true)
        show(animated: false)
    }

    private var current: URL? { order.indices.contains(position) ? order[position] : nil }

    private var target: CGSize {
        CGSize(width: screen.frame.width * screen.backingScaleFactor, height: screen.frame.height * screen.backingScaleFactor)
    }

    private func show(animated: Bool) {
        token += 1
        let mine = token
        timer?.invalidate()
        guard let url = current else { return }
        ImageLoader.shared.load(url, fit: target) { [weak self] image in
            guard let self, mine == self.token, !self.exiting else { return }
            self.view.display(image, animated: animated)
            self.scheduleNext()
            let n = self.order.count
            if n > 1 { ImageLoader.shared.prefetch([self.order[(self.position + 1) % n]], fit: self.target) }
        }
    }

    private func scheduleNext() {
        timer?.invalidate()
        guard !paused else { return }
        timer = Timer.scheduledTimer(withTimeInterval: Settings.slideSpeed.interval, repeats: false) { [weak self] _ in
            self?.advance(1, automatic: true)
        }
    }

    func advance(_ delta: Int, automatic: Bool = false) {
        let n = order.count
        guard n > 0 else { return }
        var next = position + delta
        if next >= n {
            if automatic, !Settings.slideLoop {
                exit()
                return
            }
            next = 0
        }
        if next < 0 { next = n - 1 }
        position = next
        show(animated: true)
    }

    @objc func togglePause() {
        paused.toggle()
        if paused { timer?.invalidate() } else { scheduleNext() }
    }

    @objc func exit() {
        guard !exiting else { return }
        exiting = true
        timer?.invalidate()
        if !savedOptions.contains(.fullScreen) {
            NSApp.presentationOptions = savedOptions
        }
        window.orderOut(nil)
        onExit(current)
    }

    private func reshuffle() {
        guard let now = current else { return }
        var rest = source.filter { $0 != now }
        rest.shuffle()
        order = [now] + rest
        position = 0
    }

    @objc private func toggleShuffle() {
        Settings.slideShuffle.toggle()
        if Settings.slideShuffle {
            reshuffle()
        } else if let now = current {
            order = source
            position = source.firstIndex(of: now) ?? 0
        }
    }

    @objc private func toggleLoop() { Settings.slideLoop.toggle() }
    @objc private func nextSlide() { advance(1) }
    @objc private func previousSlide() { advance(-1) }

    @objc private func setSpeed(_ item: NSMenuItem) {
        guard let raw = item.representedObject as? String, let speed = SlideSpeed(rawValue: raw) else { return }
        Settings.slideSpeed = speed
        scheduleNext()
    }

    func menu() -> NSMenu {
        let menu = NSMenu()
        func add(_ title: String, _ action: Selector, state: Bool = false) {
            let item = menu.addItem(withTitle: title, action: action, keyEquivalent: "")
            item.target = self
            item.state = state ? .on : .off
        }
        add(paused ? L.t("Продолжить", "Play") : L.t("Пауза", "Pause"), #selector(togglePause))
        add(L.t("Следующий", "Next"), #selector(nextSlide))
        add(L.t("Предыдущий", "Previous"), #selector(previousSlide))
        menu.addItem(.separator())
        add(L.t("Перемешать", "Shuffle"), #selector(toggleShuffle), state: Settings.slideShuffle)
        add(L.t("Повторять", "Loop"), #selector(toggleLoop), state: Settings.slideLoop)
        menu.addItem(.separator())
        for speed in SlideSpeed.allCases {
            let item = menu.addItem(withTitle: L.t("Скорость: ", "Speed: ") + speed.title.lowercased(),
                                    action: #selector(setSpeed(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = speed.rawValue
            item.state = Settings.slideSpeed == speed ? .on : .off
        }
        menu.addItem(.separator())
        add(L.t("Выход", "Exit"), #selector(exit))
        return menu
    }
}

private final class SlideWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

private final class SlideView: NSView {
    weak var controller: SlideshowController?
    private let imageLayer = CALayer()
    private var image: DecodedImage?
    private var hideCursor: DispatchWorkItem?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        imageLayer.contentsGravity = .resize
        imageLayer.minificationFilter = .trilinear
        imageLayer.actions = ["bounds": NSNull(), "position": NSNull(), "contents": NSNull()]
        layer?.addSublayer(imageLayer)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }

    func display(_ newImage: DecodedImage?, animated: Bool) {
        image = newImage
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if animated {
            let fade = CATransition()
            fade.type = .fade
            fade.duration = 0.45
            imageLayer.add(fade, forKey: "fade")
        }
        imageLayer.contents = newImage?.cgImage
        layoutImage()
        CATransaction.commit()
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layoutImage()
        CATransaction.commit()
    }

    /// Вписать в экран, не растягивая больше реального размера.
    private func layoutImage() {
        guard let image, image.fullSize.width > 0, image.fullSize.height > 0 else {
            imageLayer.frame = .zero
            return
        }
        let scale = window?.backingScaleFactor ?? 2
        let fit = min(1, min(bounds.width * scale / image.fullSize.width, bounds.height * scale / image.fullSize.height))
        let w = image.fullSize.width * fit / scale, h = image.fullSize.height * fit / scale
        imageLayer.frame = NSRect(x: ((bounds.width - w) / 2 * scale).rounded() / scale,
                                  y: ((bounds.height - h) / 2 * scale).rounded() / scale,
                                  width: w, height: h)
    }

    override func keyDown(with event: NSEvent) {
        let code = event.charactersIgnoringModifiers?.unicodeScalars.first.map { Int($0.value) } ?? 0
        switch code {
        case 0x1B, NSF5FunctionKey, NSF11FunctionKey: controller?.exit()
        case NSRightArrowFunctionKey, NSDownArrowFunctionKey, NSPageDownFunctionKey: controller?.advance(1)
        case NSLeftArrowFunctionKey, NSUpArrowFunctionKey, NSPageUpFunctionKey: controller?.advance(-1)
        case 0x20: controller?.togglePause()
        default:
            if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "." {
                controller?.exit()
            } else {
                super.keyDown(with: event)
            }
        }
    }

    override func cancelOperation(_ sender: Any?) {
        controller?.exit()
    }

    override func mouseDown(with event: NSEvent) {
        controller?.advance(1)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        controller?.menu()
    }

    override func mouseMoved(with event: NSEvent) {
        NSCursor.unhide()
        hideCursor?.cancel()
        let work = DispatchWorkItem { NSCursor.setHiddenUntilMouseMoves(true) }
        hideCursor = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: work)
    }
}
