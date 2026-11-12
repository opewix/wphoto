import AppKit

/// Раскладка окна: панель команд сверху (Vista/7), рисунок, панель кнопок снизу.
final class ViewerContentView: NSView {
    let canvas: ImageCanvas
    var topBar: NSView? {
        didSet {
            oldValue?.removeFromSuperview()
            if let topBar { addSubview(topBar) }
            needsLayout = true
        }
    }
    var bottomBar: NSView? {
        didSet {
            oldValue?.removeFromSuperview()
            if let bottomBar { addSubview(bottomBar) }
            needsLayout = true
        }
    }

    init(canvas: ImageCanvas) {
        self.canvas = canvas
        super.init(frame: NSRect(x: 0, y: 0, width: 960, height: 680))
        addSubview(canvas)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        let top = topBar == nil ? 0 : Theme.commandBarHeight
        let bottom = bottomBar == nil ? 0 : Theme.controlBarHeight
        bottomBar?.frame = NSRect(x: 0, y: 0, width: bounds.width, height: bottom)
        topBar?.frame = NSRect(x: 0, y: bounds.height - top, width: bounds.width, height: top)
        canvas.frame = NSRect(x: 0, y: bottom, width: bounds.width, height: max(0, bounds.height - top - bottom))
    }
}

/// Окно просмотра: один рисунок и список, по которому листают.
final class ViewerController: NSWindowController, NSWindowDelegate, ImageCanvasDelegate, NSMenuItemValidation {
    private(set) static var controllers: [ViewerController] = []

    /// Окно, в котором открывать: активное, иначе последнее, иначе новое.
    static func target() -> ViewerController {
        if let main = NSApp.mainWindow?.windowController as? ViewerController { return main }
        if let last = controllers.last { return last }
        return make()
    }

    static func make() -> ViewerController {
        let controller = ViewerController()
        if let previous = controllers.last?.window, let window = controller.window {
            window.setFrameTopLeftPoint(window.cascadeTopLeft(from: NSPoint(x: previous.frame.minX, y: previous.frame.maxY)))
        }
        controllers.append(controller)
        return controller
    }

    let canvas = ImageCanvas(frame: .zero)
    private let content: ViewerContentView
    private var controlBar: ControlBar?
    private var commandBar: CommandBar?
    private(set) var list: ImageList?
    private(set) var shownURL: URL?
    private var token = 0
    private var fullRequestKey: String?
    /// Поворот, который не удалось записать в файл (формат не позволяет), — только на экране.
    private var unsavedRotation: [URL: Int] = [:]
    /// Повороты, которые ещё записываются в файл.
    private var savingTurns: [URL: Int] = [:]
    private var zoomPopover: NSPopover?
    private weak var zoomSlider: NSSlider?
    private var slideshow: SlideshowController?
    private var properties: PropertiesPanel?

    private init() {
        content = ViewerContentView(canvas: canvas)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 960, height: 680),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.minSize = NSSize(width: 520, height: 360)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .aqua)
        window.collectionBehavior = [.fullScreenPrimary]
        window.tabbingMode = .disallowed
        window.title = L10nApp.name
        super.init(window: window)
        window.delegate = self
        window.contentView = content
        canvas.delegate = self
        rebuildBars()
        if !window.setFrameUsingName("WPhotoViewer") { window.center() }
        window.setFrameAutosaveName("WPhotoViewer")
        NotificationCenter.default.addObserver(self, selector: #selector(themeChanged), name: Theme.changed, object: nil)
        showCurrent()
        window.makeFirstResponder(canvas)
    }

    required init?(coder: NSCoder) { fatalError() }

    private func rebuildBars() {
        let bar = ControlBar { [weak self] in self?.perform($0) }
        controlBar = bar
        content.bottomBar = bar
        if Theme.isXP {
            commandBar = nil
            content.topBar = nil
        } else {
            let top = CommandBar { [weak self] in self?.perform($0) }
            commandBar = top
            content.topBar = top
        }
        canvas.needsDisplay = true
        updateChrome()
    }

    @objc private func themeChanged() {
        rebuildBars()
    }

    func windowWillClose(_ notification: Notification) {
        zoomPopover?.close()
        Self.controllers.removeAll { $0 === self }
    }

    // MARK: - Открытие и показ

    func open(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        let newList = ImageList(opening: urls)
        newList.onExternalChange = { [weak self] in self?.listChanged() }
        list = newList
        unsavedRotation = [:]
        for url in urls { NSDocumentController.shared.noteNewRecentDocumentURL(url) }
        showCurrent()
    }

    /// Размер экрана в пикселях — под него декодируются рисунки.
    private var screenTarget: CGSize {
        let screen = window?.screen ?? NSScreen.main
        let size = screen?.frame.size ?? CGSize(width: 2560, height: 1600)
        let scale = screen?.backingScaleFactor ?? 2
        return CGSize(width: size.width * scale, height: size.height * scale)
    }

    private func showCurrent() {
        token += 1
        let current = token
        fullRequestKey = nil
        guard let url = list?.current else {
            shownURL = nil
            canvas.show(nil, rotation: 0)
            canvas.message = list == nil
                ? L.t("Откройте рисунок (⌘O) или перетащите его сюда", "Open a picture (⌘O) or drop one here")
                : L.t("В этой папке нет рисунков", "There are no pictures in this folder")
            updateChrome()
            return
        }
        shownURL = url
        let rotation = unsavedRotation[url] ?? 0
        let target = screenTarget
        if let image = ImageLoader.shared.cached(url, fit: target) {
            canvas.show(image, rotation: rotation)
        } else {
            canvas.message = nil
            canvas.show(ImageLoader.quickPreview(url), rotation: rotation)
            ImageLoader.shared.load(url, fit: target) { [weak self] image in
                guard let self, current == self.token else { return }
                if let image {
                    if let shown = self.canvas.image, shown.isPreview {
                        self.canvas.replace(image)
                    } else {
                        self.canvas.show(image, rotation: rotation)
                    }
                } else {
                    self.canvas.show(nil, rotation: 0)
                    self.canvas.message = L.t("Не удаётся показать этот рисунок", "This picture can't be displayed")
                }
                self.updateChrome()
            }
        }
        updateChrome()
        ImageLoader.shared.prefetch(list?.neighbors() ?? [], fit: target)
    }

    private func listChanged() {
        if list?.current?.path != shownURL?.path {
            showCurrent()
        } else {
            updateChrome()
        }
    }

    private func updateChrome() {
        guard let window else { return }
        if let url = shownURL {
            window.title = url.lastPathComponent
            window.representedURL = url
        } else {
            window.title = L10nApp.name
            window.representedURL = nil
        }
        let hasImage = shownURL != nil && canvas.image != nil
        controlBar?.update(hasImage: hasImage, canNavigate: (list?.count ?? 0) > 1,
                           isFit: canvas.isFit, fitIsActual: canvas.fitIsActualSize)
        commandBar?.update(hasImage: shownURL != nil)
    }

    // MARK: - ImageCanvasDelegate

    func canvasNeedsFullResolution(_ canvas: ImageCanvas) {
        guard let url = shownURL, let image = canvas.image, !image.isFull, !image.isPreview else { return }
        let key = "\(url.path)|\(image.stamp.timeIntervalSinceReferenceDate)"
        guard fullRequestKey != key else { return }
        fullRequestKey = key
        let current = token
        ImageLoader.shared.loadFull(url) { [weak self] full in
            guard let self, current == self.token, let full,
                  full.stamp == self.canvas.image?.stamp else { return }
            self.canvas.replace(full)
        }
    }

    func canvasZoomChanged(_ canvas: ImageCanvas) {
        zoomSlider?.doubleValue = sliderValue
        updateChrome()
    }

    func canvasMenu(_ canvas: ImageCanvas) -> NSMenu? {
        guard shownURL != nil else { return nil }
        let menu = NSMenu()
        let openWith = NSMenuItem(title: L.t("Открыть в программе", "Open With"), action: nil, keyEquivalent: "")
        openWith.submenu = openWithMenu()
        menu.addItem(openWith)
        menu.addItem(withTitle: L.t("Сделать фоном рабочего стола", "Set as Desktop Picture"),
                     action: #selector(setDesktopPicture(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: L.t("Повернуть по часовой стрелке", "Rotate Clockwise"), action: #selector(rotateRight(_:)), keyEquivalent: "")
        menu.addItem(withTitle: L.t("Повернуть против часовой стрелки", "Rotate Counterclockwise"), action: #selector(rotateLeft(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: L.t("Копировать", "Copy"), action: #selector(copy(_:)), keyEquivalent: "")
        menu.addItem(withTitle: L.t("Переместить в Корзину", "Move to Trash"), action: #selector(moveToTrash(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: L.t("Показать в Finder", "Show in Finder"), action: #selector(showInFinder(_:)), keyEquivalent: "")
        menu.addItem(withTitle: L.t("Свойства", "Properties"), action: #selector(showProperties(_:)), keyEquivalent: "")
        for item in menu.items where item.action != nil { item.target = self }
        return menu
    }

    func canvasDropped(_ urls: [URL]) {
        open(urls)
    }

    func canvasStep(_ delta: Int) {
        step(delta)
    }

    func canvasKeyDown(_ event: NSEvent) -> Bool {
        let mods = event.modifierFlags.intersection([.command, .option, .control, .shift])
        let key = event.charactersIgnoringModifiers ?? ""
        let code = key.unicodeScalars.first.map { Int($0.value) } ?? 0
        if mods.contains(.control) {
            // Сочетания Windows: Ctrl+. и Ctrl+, — повороты.
            if key == "." { rotate(1); return true }
            if key == "," { rotate(-1); return true }
            return false
        }
        guard mods.subtracting(.shift).isEmpty else { return false }
        let panStep: CGFloat = 60
        switch code {
        case NSLeftArrowFunctionKey, NSPageUpFunctionKey: step(-1)
        case NSRightArrowFunctionKey, NSPageDownFunctionKey: step(1)
        case NSUpArrowFunctionKey:
            if canvas.canPan { canvas.pan(dx: 0, dy: -panStep) } else { step(-1) }
        case NSDownArrowFunctionKey:
            if canvas.canPan { canvas.pan(dx: 0, dy: panStep) } else { step(1) }
        case NSHomeFunctionKey: list?.select(0); showCurrent()
        case NSEndFunctionKey: list.map { $0.select($0.count - 1) }; showCurrent()
        case NSF5FunctionKey, NSF11FunctionKey: startSlideshow(nil)
        case 0x7F, NSDeleteFunctionKey: moveToTrash(nil)
        case 0x20: step(mods.contains(.shift) ? -1 : 1)
        case 0x1B:
            if window?.styleMask.contains(.fullScreen) == true { window?.toggleFullScreen(nil) } else { return false }
        default:
            switch key {
            case "+", "=": canvas.zoomIn()
            case "-", "_": canvas.zoomOut()
            case "0": canvas.fitToWindow()
            case "1": canvas.actualSize()
            default: return false
            }
        }
        return true
    }

    // MARK: - Кнопки панелей

    private func perform(_ command: BarCommand) {
        switch command {
        case .zoom(let view): toggleZoomPopover(from: view)
        case .zoomIn: canvas.zoomIn()
        case .zoomOut: canvas.zoomOut()
        case .toggleFit: canvas.toggleFit()
        case .fit: canvas.fitToWindow()
        case .actualSize: canvas.actualSize()
        case .previous: step(-1)
        case .next: step(1)
        case .slideshow: startSlideshow(nil)
        case .rotateLeft: rotate(-1)
        case .rotateRight: rotate(1)
        case .delete: moveToTrash(nil)
        case .print: printDocument(nil)
        case .copyTo: makeCopy(nil)
        case .edit(let view): popUp(openWithMenu(), under: view)
        }
        window?.makeFirstResponder(canvas)
    }

    private func perform(_ command: TopCommand) {
        switch command {
        case .file(let view): popUp(fileMenu(), under: view)
        case .print: printDocument(nil)
        case .share(let view):
            guard let url = shownURL else { return }
            NSSharingServicePicker(items: [url]).show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
        case .open(let view): popUp(openWithMenu(), under: view)
        }
    }

    private func popUp(_ menu: NSMenu, under view: NSView) {
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: view.isFlipped ? view.bounds.height + 2 : -2), in: view)
    }

    private func fileMenu() -> NSMenu {
        let menu = NSMenu()
        func add(_ title: String, _ action: Selector) {
            let item = menu.addItem(withTitle: title, action: action, keyEquivalent: "")
            item.target = self
        }
        add(L.t("Открыть…", "Open…"), #selector(openDocumentHere(_:)))
        menu.addItem(.separator())
        add(L.t("Сохранить копию…", "Make a Copy…"), #selector(makeCopy(_:)))
        add(L.t("Копировать", "Copy"), #selector(copy(_:)))
        add(L.t("Переместить в Корзину", "Move to Trash"), #selector(moveToTrash(_:)))
        menu.addItem(.separator())
        add(L.t("Сделать фоном рабочего стола", "Set as Desktop Picture"), #selector(setDesktopPicture(_:)))
        add(L.t("Показать в Finder", "Show in Finder"), #selector(showInFinder(_:)))
        add(L.t("Свойства", "Properties"), #selector(showProperties(_:)))
        menu.addItem(.separator())
        add(L.t("Закрыть", "Close"), #selector(closeWindow(_:)))
        return menu
    }

    private func openWithMenu() -> NSMenu {
        let menu = NSMenu()
        guard let url = shownURL else { return menu }
        let workspace = NSWorkspace.shared
        let preferred = workspace.urlForApplication(toOpen: url)
        var apps = workspace.urlsForApplications(toOpen: url)
            .filter { $0.standardizedFileURL != Bundle.main.bundleURL.standardizedFileURL }
        var seen = Set<String>()
        apps = apps.filter { seen.insert(Bundle(url: $0)?.bundleIdentifier ?? $0.path).inserted }
        apps.sort { name(ofApp: $0).localizedStandardCompare(name(ofApp: $1)) == .orderedAscending }
        if let preferred, let i = apps.firstIndex(of: preferred) {
            apps.insert(apps.remove(at: i), at: 0)
        }
        for app in apps {
            let item = menu.addItem(withTitle: name(ofApp: app), action: #selector(openWithApp(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = app
            let icon = workspace.icon(forFile: app.path)
            icon.size = NSSize(width: 16, height: 16)
            item.image = icon
        }
        if !apps.isEmpty { menu.addItem(.separator()) }
        let choose = menu.addItem(withTitle: L.t("Выбрать программу…", "Choose Application…"),
                                  action: #selector(chooseApp(_:)), keyEquivalent: "")
        choose.target = self
        return menu
    }

    private func name(ofApp url: URL) -> String {
        FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }

    @objc private func openWithApp(_ sender: NSMenuItem) {
        guard let url = shownURL, let app = sender.representedObject as? URL else { return }
        NSWorkspace.shared.open([url], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
    }

    @objc private func chooseApp(_ sender: Any?) {
        guard let url = shownURL, let window else { return }
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.application]
        panel.prompt = L.t("Открыть", "Open")
        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let app = panel.url else { return }
            NSWorkspace.shared.open([url], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
        }
    }

    // MARK: - Ползунок масштаба

    private var sliderValue: Double {
        let lo = canvas.fitZoom, hi = max(lo * 1.01, canvas.maxZoom)
        return Double(log(canvas.currentZoom / lo) / log(hi / lo))
    }

    private func toggleZoomPopover(from view: NSView) {
        if let popover = zoomPopover, popover.isShown {
            popover.close()
            return
        }
        let slider = NSSlider(value: sliderValue, minValue: 0, maxValue: 1, target: self, action: #selector(zoomSliderMoved(_:)))
        slider.isVertical = true
        slider.isContinuous = true
        slider.frame = NSRect(x: 12, y: 10, width: 24, height: 150)
        let host = NSView(frame: NSRect(x: 0, y: 0, width: 48, height: 170))
        host.addSubview(slider)
        let controller = NSViewController()
        controller.view = host
        let popover = NSPopover()
        popover.contentViewController = controller
        popover.behavior = .transient
        popover.appearance = NSAppearance(named: .aqua)
        popover.show(relativeTo: view.bounds, of: view, preferredEdge: .maxY)
        zoomPopover = popover
        zoomSlider = slider
    }

    @objc private func zoomSliderMoved(_ slider: NSSlider) {
        let lo = canvas.fitZoom, hi = max(lo * 1.01, canvas.maxZoom)
        canvas.setZoom(lo * pow(hi / lo, CGFloat(slider.doubleValue)))
    }

    // MARK: - Действия

    private func step(_ delta: Int) {
        guard let list, list.count > 1 else { return }
        list.step(delta)
        showCurrent()
    }

    @objc func nextImage(_ sender: Any?) { step(1) }
    @objc func previousImage(_ sender: Any?) { step(-1) }
    @objc func firstImage(_ sender: Any?) { list?.select(0); showCurrent() }
    @objc func lastImage(_ sender: Any?) { list.map { $0.select($0.count - 1) }; showCurrent() }
    @objc func zoomIn(_ sender: Any?) { canvas.zoomIn() }
    @objc func zoomOut(_ sender: Any?) { canvas.zoomOut() }
    @objc func fitToWindow(_ sender: Any?) { canvas.fitToWindow() }
    @objc func actualSize(_ sender: Any?) { canvas.actualSize() }
    @objc func rotateRight(_ sender: Any?) { rotate(1) }
    @objc func rotateLeft(_ sender: Any?) { rotate(-1) }
    @objc func closeWindow(_ sender: Any?) { window?.performClose(sender) }

    @objc func openDocumentHere(_ sender: Any?) {
        guard let window else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.image, .folder]
        panel.directoryURL = list?.folder
        panel.beginSheetModal(for: window) { [weak self] response in
            if response == .OK { self?.open(panel.urls) }
        }
    }

    /// Поворот как в Windows: сразу на экране и тут же в файл (без пережатия). Если формат
    /// не позволяет, поворот остаётся только на экране, пока окно открыто.
    private func rotate(_ delta: Int) {
        guard let url = shownURL, canvas.image != nil else { return }
        canvas.setRotation(canvas.rotation + delta)
        if unsavedRotation[url] != nil {
            unsavedRotation[url] = canvas.rotation
            return
        }
        savingTurns[url, default: 0] += delta
        ImageSaver.rotate(url, quarterTurns: delta) { [weak self] ok in
            guard let self else { return }
            self.savingTurns[url, default: 0] -= delta
            if !ok {
                self.unsavedRotation[url] = ((self.unsavedRotation[url] ?? 0) + delta + 4) % 4
                return
            }
            // Все повороты записаны — берём рисунок из файла, поворот на экране обнуляется.
            guard self.savingTurns[url] == 0, self.shownURL == url else { return }
            let current = self.token
            ImageLoader.shared.load(url, fit: self.screenTarget) { [weak self] image in
                guard let self, current == self.token, self.savingTurns[url] == 0, let image else { return }
                self.canvas.show(image, rotation: 0)
                self.updateChrome()
            }
        }
    }

    @objc func moveToTrash(_ sender: Any?) {
        guard let url = shownURL, let window else { return }
        guard Settings.confirmDelete else {
            trash(url)
            return
        }
        let alert = NSAlert()
        alert.messageText = L.t("Переместить этот файл в Корзину?", "Are you sure you want to move this file to the Trash?")
        alert.informativeText = url.lastPathComponent
        alert.addButton(withTitle: L.t("Да", "Yes"))
        alert.addButton(withTitle: L.t("Нет", "No"))
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = L.t("Больше не спрашивать", "Don't ask me again")
        if let image = canvas.image?.cgImage {
            alert.icon = NSImage(cgImage: image, size: NSSize(width: 64, height: 64 * CGFloat(image.height) / CGFloat(max(1, image.width))))
        }
        alert.beginSheetModal(for: window) { [weak self] response in
            if alert.suppressionButton?.state == .on { Settings.confirmDelete = false }
            if response == .alertFirstButtonReturn { self?.trash(url) }
        }
    }

    private func trash(_ url: URL) {
        var result: NSURL?
        do {
            try FileManager.default.trashItem(at: url, resultingItemURL: &result)
        } catch {
            if let window { NSAlert(error: error).beginSheetModal(for: window) }
            return
        }
        list?.remove(url)
        if let trashed = result as URL? {
            window?.undoManager?.registerUndo(withTarget: self) { $0.restore(trashed, to: url) }
            window?.undoManager?.setActionName(L.t("перемещение в Корзину", "Move to Trash"))
        }
        showCurrent()
    }

    private func restore(_ trashed: URL, to original: URL) {
        do {
            try FileManager.default.moveItem(at: trashed, to: original)
        } catch {
            if let window { NSAlert(error: error).beginSheetModal(for: window) }
            return
        }
        list?.insert(original)
        window?.undoManager?.registerUndo(withTarget: self) { $0.trash(original) }
        window?.undoManager?.setActionName(L.t("перемещение в Корзину", "Move to Trash"))
        showCurrent()
    }

    /// Полный рисунок с поворотом, сделанным на экране, — для печати и буфера обмена.
    private func fullImage() -> CGImage? {
        guard let url = shownURL else { return nil }
        let image = ImageLoader.shared.cachedFull(url) ?? ImageLoader.decode(url, fit: nil) ?? canvas.image
        return image?.cgImage.rotated(quarterTurns: canvas.rotation)
    }

    @objc func copy(_ sender: Any?) {
        guard let url = shownURL else { return }
        let item = NSPasteboardItem()
        item.setString(url.absoluteString, forType: .fileURL)
        if let image = fullImage(),
           let tiff = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height)).tiffRepresentation {
            item.setData(tiff, forType: .tiff)
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([item])
    }

    @objc func makeCopy(_ sender: Any?) {
        guard let url = shownURL, let window else { return }
        let panel = NSSavePanel()
        let base = url.deletingPathExtension().lastPathComponent
        panel.nameFieldStringValue = "\(base) \(L.t("копия", "copy")).\(url.pathExtension)"
        panel.directoryURL = url.deletingLastPathComponent()
        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let target = panel.url else { return }
            do {
                if FileManager.default.fileExists(atPath: target.path) {
                    try FileManager.default.removeItem(at: target)
                }
                try FileManager.default.copyItem(at: url, to: target)
            } catch {
                NSAlert(error: error).beginSheetModal(for: window)
            }
        }
    }

    @objc func showInFinder(_ sender: Any?) {
        guard let url = shownURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    @objc func setDesktopPicture(_ sender: Any?) {
        guard let url = shownURL else { return }
        for screen in NSScreen.screens {
            try? NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: [:])
        }
    }

    @objc func showProperties(_ sender: Any?) {
        guard let url = shownURL else { return }
        let panel = properties ?? PropertiesPanel()
        properties = panel
        panel.show(url, near: window)
    }

    @objc func printDocument(_ sender: Any?) {
        guard let window, let image = fullImage() else { return }
        let info = (NSPrintInfo.shared.copy() as? NSPrintInfo) ?? NSPrintInfo()
        info.orientation = image.width > image.height ? .landscape : .portrait
        info.horizontalPagination = .fit
        info.verticalPagination = .fit
        info.isHorizontallyCentered = true
        info.isVerticallyCentered = true
        let paper = info.paperSize
        let size = NSSize(width: paper.width - info.leftMargin - info.rightMargin,
                          height: paper.height - info.topMargin - info.bottomMargin)
        let view = NSImageView(frame: NSRect(origin: .zero, size: size))
        view.imageScaling = .scaleProportionallyUpOrDown
        view.image = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
        let operation = NSPrintOperation(view: view, printInfo: info)
        operation.jobTitle = shownURL?.lastPathComponent ?? L10nApp.name
        operation.runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)
    }

    // MARK: - Слайд-шоу

    @objc func startSlideshow(_ sender: Any?) {
        guard slideshow == nil, let list, list.count > 0, shownURL != nil else { return }
        let show = SlideshowController(urls: list.urls, start: list.index,
                                       screen: window?.screen ?? NSScreen.main ?? NSScreen.screens[0]) { [weak self] last in
            self?.slideshowEnded(last)
        }
        slideshow = show
        show.start()
    }

    private func slideshowEnded(_ last: URL?) {
        slideshow = nil
        if let last, last != shownURL {
            list?.select(last)
            showCurrent()
        }
        window?.makeKeyAndOrderFront(nil)
    }

    // MARK: - Меню

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        let hasImage = shownURL != nil && canvas.image != nil
        switch item.action {
        case #selector(nextImage(_:)), #selector(previousImage(_:)), #selector(firstImage(_:)), #selector(lastImage(_:)):
            return (list?.count ?? 0) > 1
        case #selector(zoomIn(_:)), #selector(zoomOut(_:)), #selector(rotateLeft(_:)), #selector(rotateRight(_:)),
             #selector(copy(_:)), #selector(printDocument(_:)), #selector(startSlideshow(_:)):
            return hasImage
        case #selector(fitToWindow(_:)):
            return hasImage && !canvas.isFit
        case #selector(actualSize(_:)):
            return hasImage && canvas.currentZoom != 1
        case #selector(moveToTrash(_:)), #selector(makeCopy(_:)), #selector(showInFinder(_:)),
             #selector(showProperties(_:)), #selector(setDesktopPicture(_:)):
            return shownURL != nil
        default:
            return true
        }
    }
}

enum L10nApp {
    static let name = "WPhoto"
}
