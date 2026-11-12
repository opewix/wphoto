import AppKit

/// Раскладка окна правки: действия сверху, инструменты слева, настройки снизу, коррекция справа.
private final class EditorContentView: NSView {
    let top: NSView, left: NSView, bottom: NSView, canvas: NSView
    var right: NSView? {
        didSet {
            oldValue?.removeFromSuperview()
            if let right { addSubview(right) }
            needsLayout = true
        }
    }

    init(top: NSView, left: NSView, bottom: NSView, canvas: NSView) {
        self.top = top
        self.left = left
        self.bottom = bottom
        self.canvas = canvas
        super.init(frame: NSRect(x: 0, y: 0, width: 1100, height: 760))
        [canvas, top, left, bottom].forEach(addSubview)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        let topH: CGFloat = 40, bottomH: CGFloat = 38, leftW: CGFloat = 78
        let rightW: CGFloat = right == nil ? 0 : 248
        top.frame = NSRect(x: 0, y: bounds.height - topH, width: bounds.width, height: topH)
        bottom.frame = NSRect(x: 0, y: 0, width: bounds.width, height: bottomH)
        left.frame = NSRect(x: 0, y: bottomH, width: leftW, height: bounds.height - topH - bottomH)
        right?.frame = NSRect(x: bounds.width - rightW, y: bottomH, width: rightW, height: bounds.height - topH - bottomH)
        canvas.frame = NSRect(x: leftW, y: bottomH, width: max(0, bounds.width - leftW - rightW),
                              height: max(0, bounds.height - topH - bottomH))
    }
}

/// Окно «Правка»: обрезка, размер, поворот, рисование, фигуры, размытие, цвет, фильтры.
/// Сохраняется только копия — оригинал не трогается.
final class EditorController: NSWindowController, NSWindowDelegate, EditorCanvasDelegate, NSMenuItemValidation {
    private static var editors: [EditorController] = []

    /// Окно правки для файла: уже открытое или новое.
    static func open(_ url: URL, quarterTurns: Int, onSaved: @escaping (URL) -> Void) -> EditorController? {
        if let existing = editors.first(where: { $0.doc.source.path == url.path }) {
            existing.showWindow(nil)
            return existing
        }
        NSCursor.operationNotAllowed.push()
        defer { NSCursor.pop() }
        guard let doc = EditDocument(url: url, quarterTurns: quarterTurns) else {
            let alert = NSAlert()
            alert.messageText = L.t("Не удаётся открыть рисунок для правки", "This picture can't be opened for editing")
            alert.runModal()
            return nil
        }
        let editor = EditorController(doc: doc, onSaved: onSaved)
        editors.append(editor)
        editor.showWindow(nil)
        return editor
    }

    let doc: EditDocument
    private let onSaved: (URL) -> Void
    private let canvas = EditorCanvas(frame: .zero)
    private let content: EditorContentView
    private var toolButtons: [EditTool: SymbolButton] = [:]
    private var undoButton: SymbolButton!
    private var redoButton: SymbolButton!
    private let colorWell = NSColorWell()
    private let sizeSlider = NSSlider(value: 4, minValue: 1, maxValue: 40, target: nil, action: nil)
    private let sizeValue = NSTextField(labelWithString: "4")
    private let fillBox = NSButton(checkboxWithTitle: L.t("Заливка", "Fill"), target: nil, action: nil)
    private let ratioPopup = NSPopUpButton()
    private let cropInfo = NSTextField(labelWithString: "")
    private let hint = NSTextField(labelWithString: "")
    private var drawingOptions: [NSView] = []
    private var cropOptions: [NSView] = []
    private var adjustPanel: AdjustPanel?
    private var adjustBase: CIImage?
    private var resizeSheet: ResizeSheet?
    private var closeAfterSave = false
    private var saving = false

    private init(doc: EditDocument, onSaved: @escaping (URL) -> Void) {
        self.doc = doc
        self.onSaved = onSaved
        let top = BarBackground(edge: .top)
        let left = BarBackground(edge: .left)
        let bottom = BarBackground(edge: .bottom)
        content = EditorContentView(top: top, left: left, bottom: bottom, canvas: canvas)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 760),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.minSize = NSSize(width: 860, height: 520)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .aqua)
        window.tabbingMode = .disallowed
        window.collectionBehavior = [.fullScreenPrimary]
        super.init(window: window)
        window.delegate = self
        window.contentView = content
        window.title = L.t("Правка — ", "Edit — ") + doc.source.lastPathComponent
        window.representedURL = doc.source
        if !window.setFrameUsingName("WPhotoEditor") { window.center() }
        window.setFrameAutosaveName("WPhotoEditor")
        buildTop(top)
        buildLeft(left)
        buildBottom(bottom)
        canvas.delegate = self
        doc.onChange = { [weak self] in self?.documentChanged() }
        documentChanged()
        select(.pen)
        window.makeFirstResponder(canvas)
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Панели

    private func commandButton(_ title: String, menu: Bool = false, _ action: @escaping (NSView) -> Void) -> CommandButton {
        let b = CommandButton(title: title, hasMenu: menu)
        b.translatesAutoresizingMaskIntoConstraints = false
        b.widthAnchor.constraint(equalToConstant: b.frame.width).isActive = true
        b.heightAnchor.constraint(equalToConstant: b.frame.height).isActive = true
        b.onClick = { action($0) }
        return b
    }

    private func symbolButton(_ symbols: [String], _ tip: String, _ action: @escaping () -> Void) -> SymbolButton {
        let b = SymbolButton(symbols: symbols, tooltip: tip)
        b.onClick = action
        return b
    }

    private func separator() -> NSView {
        let line = NSBox()
        line.boxType = .separator
        line.translatesAutoresizingMaskIntoConstraints = false
        line.heightAnchor.constraint(equalToConstant: 22).isActive = true
        return line
    }

    private func buildTop(_ bar: NSView) {
        undoButton = symbolButton(["arrow.uturn.backward"], L.t("Отменить (⌘Z)", "Undo (⌘Z)")) { [weak self] in
            self?.window?.undoManager?.undo()
        }
        redoButton = symbolButton(["arrow.uturn.forward"], L.t("Повторить (⇧⌘Z)", "Redo (⇧⌘Z)")) { [weak self] in
            self?.window?.undoManager?.redo()
        }
        let views: [NSView] = [
            undoButton, redoButton, separator(),
            symbolButton(["rotate.left"], L.t("Повернуть против часовой (⌘L)", "Rotate counterclockwise (⌘L)")) { [weak self] in self?.rotateLeft(nil) },
            symbolButton(["rotate.right"], L.t("Повернуть по часовой (⌘R)", "Rotate clockwise (⌘R)")) { [weak self] in self?.rotateRight(nil) },
            symbolButton(["arrow.left.and.right.righttriangle.left.righttriangle.right", "arrow.left.and.right"],
                         L.t("Отразить по горизонтали", "Flip horizontal")) { [weak self] in self?.flipHorizontal(nil) },
            symbolButton(["arrow.up.and.down.righttriangle.up.righttriangle.down", "arrow.up.and.down"],
                         L.t("Отразить по вертикали", "Flip vertical")) { [weak self] in self?.flipVertical(nil) },
            separator(),
            commandButton(L.t("Размер…", "Resize…")) { [weak self] _ in self?.showResize(nil) },
            commandButton(L.t("Цвет…", "Adjust…")) { [weak self] _ in self?.showAdjust(nil) },
            commandButton(L.t("Фильтры", "Filters"), menu: true) { [weak self] view in
                guard let self else { return }
                Menus.filtersMenu().popUp(positioning: nil, at: NSPoint(x: 0, y: -2), in: view)
                _ = self
            },
            NSView(),
            commandButton(L.t("Сохранить копию…", "Save a Copy…")) { [weak self] _ in self?.saveAs(nil) },
            commandButton(L.t("Закрыть", "Close")) { [weak self] _ in self?.window?.performClose(nil) },
        ]
        let stack = NSStackView(views: views)
        stack.spacing = 4
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 8, bottom: 0, right: 8)
        place(stack, in: bar)
    }

    private func buildLeft(_ bar: NSView) {
        var rows: [[NSView]] = []
        var row: [NSView] = []
        for tool in EditTool.allCases {
            let b = symbolButton(tool.symbols, "\(tool.title) (\(tool.key.uppercased()))") { [weak self] in self?.select(tool) }
            toolButtons[tool] = b
            row.append(b)
            if row.count == 2 { rows.append(row); row = [] }
        }
        if !row.isEmpty { rows.append(row + [NSView()]) }
        let grid = NSGridView(views: rows)
        grid.rowSpacing = 4
        grid.columnSpacing = 4
        grid.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(grid)
        NSLayoutConstraint.activate([
            grid.centerXAnchor.constraint(equalTo: bar.centerXAnchor, constant: -1),
            grid.topAnchor.constraint(equalTo: bar.topAnchor, constant: 10),
        ])
    }

    private func buildBottom(_ bar: NSView) {
        colorWell.color = canvas.color
        colorWell.target = self
        colorWell.action = #selector(colorChanged)
        if #available(macOS 13.0, *) { colorWell.colorWellStyle = .minimal }
        colorWell.translatesAutoresizingMaskIntoConstraints = false
        colorWell.widthAnchor.constraint(equalToConstant: 44).isActive = true
        colorWell.heightAnchor.constraint(equalToConstant: 24).isActive = true
        sizeSlider.target = self
        sizeSlider.action = #selector(sizeChanged)
        sizeSlider.widthAnchor.constraint(equalToConstant: 140).isActive = true
        sizeValue.widthAnchor.constraint(equalToConstant: 24).isActive = true
        fillBox.target = self
        fillBox.action = #selector(fillChanged)
        let swatches = [0xE02424, 0xF59E0B, 0xFACC15, 0x22A34A, 0x2563EB, 0x7C3AED, 0x000000, 0xFFFFFF].map { hex -> NSView in
            let b = SwatchButton(color: NSColor(hex: UInt32(hex)))
            b.onClick = { [weak self] color in self?.setColor(color) }
            return b
        }
        let swatchStack = NSStackView(views: swatches)
        swatchStack.spacing = 3
        let colorLabel = NSTextField(labelWithString: L.t("Цвет:", "Color:"))
        let sizeLabel = NSTextField(labelWithString: L.t("Толщина:", "Size:"))
        drawingOptions = [colorLabel, colorWell, swatchStack, sizeLabel, sizeSlider, sizeValue, fillBox]

        let ratios: [(String, CGFloat?)] = [
            (L.t("Свободно", "Freeform"), nil),
            (L.t("Как у рисунка", "Original"), doc.size.width / doc.size.height),
            ("1:1", 1), ("4:3", 4.0 / 3), ("3:4", 3.0 / 4), ("3:2", 3.0 / 2), ("2:3", 2.0 / 3), ("16:9", 16.0 / 9), ("9:16", 9.0 / 16),
        ]
        for (title, ratio) in ratios {
            ratioPopup.addItem(withTitle: title)
            ratioPopup.lastItem?.representedObject = ratio.map { NSNumber(value: Double($0)) }
        }
        ratioPopup.target = self
        ratioPopup.action = #selector(ratioChanged)
        cropInfo.textColor = .secondaryLabelColor
        let all = NSButton(title: L.t("Всё", "Select All"), target: self, action: #selector(cropSelectAll))
        let apply = NSButton(title: L.t("Обрезать", "Crop"), target: self, action: #selector(applyCropButton))
        apply.bezelColor = .controlAccentColor
        let cancel = NSButton(title: L.t("Сбросить", "Clear"), target: self, action: #selector(cropClear))
        let ratioLabel = NSTextField(labelWithString: L.t("Пропорции:", "Aspect:"))
        cropOptions = [ratioLabel, ratioPopup, all, cancel, apply, cropInfo]
        hint.textColor = .secondaryLabelColor
        let stack = NSStackView(views: drawingOptions + cropOptions + [hint, NSView()])
        stack.spacing = 8
        stack.setCustomSpacing(16, after: swatchStack)
        stack.setCustomSpacing(16, after: sizeValue)
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 12, bottom: 0, right: 12)
        place(stack, in: bar)
    }

    private func place(_ stack: NSStackView, in bar: NSView) {
        stack.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: bar.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: bar.trailingAnchor),
            stack.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
        ])
    }

    // MARK: - Инструменты и настройки

    func select(_ tool: EditTool) {
        canvas.tool = tool
        for (t, b) in toolButtons { b.isSelected = t == tool }
        for v in drawingOptions { v.isHidden = !tool.usesColor }
        fillBox.isHidden = !tool.canFill
        for v in cropOptions { v.isHidden = tool != .crop }
        switch tool {
        case .crop: hint.stringValue = L.t("Растяните рамку; Enter — обрезать, Esc — сбросить", "Drag a frame; Return to crop, Esc to clear")
        case .blur, .pixelate: hint.stringValue = L.t("Выделите область, которую нужно скрыть", "Drag over the area to hide")
        case .text: hint.stringValue = L.t("Щёлкните, где начать надпись", "Click where the text should start")
        case .rectangle, .ellipse, .line, .arrow: hint.stringValue = L.t("Shift — ровно", "Shift — keep straight")
        default: hint.stringValue = ""
        }
        if tool == .crop { cropChangedInfo() }
        window?.makeFirstResponder(canvas)
    }

    private func setColor(_ color: NSColor) {
        canvas.color = color
        colorWell.color = color
    }

    @objc private func colorChanged() { canvas.color = colorWell.color }

    @objc private func sizeChanged() {
        canvas.size = sizeSlider.doubleValue.rounded()
        sizeValue.stringValue = "\(Int(canvas.size))"
    }

    @objc private func fillChanged() { canvas.fill = fillBox.state == .on }

    @objc private func ratioChanged() {
        canvas.cropRatio = (ratioPopup.selectedItem?.representedObject as? NSNumber).map { CGFloat($0.doubleValue) }
    }

    @objc private func cropSelectAll() { canvas.selectAllCrop() }
    @objc private func cropClear() { canvas.clearCrop() }
    @objc private func applyCropButton() { canvasApplyCrop() }

    private func cropChangedInfo() {
        if let r = canvas.cropRect {
            cropInfo.stringValue = "\(Int(r.width.rounded())) × \(Int(r.height.rounded()))"
        } else {
            cropInfo.stringValue = "\(Int(doc.size.width)) × \(Int(doc.size.height))"
        }
    }

    // MARK: - Правки и отмена

    private func documentChanged() {
        canvas.setImage(doc.image, size: doc.size)
        window?.isDocumentEdited = doc.isDirty
        undoButton?.isEnabled = window?.undoManager?.canUndo ?? false
        redoButton?.isEnabled = window?.undoManager?.canRedo ?? false
        cropChangedInfo()
    }

    /// Выполнить правку и записать шаг в отмену окна (меню «Правка» покажет её название).
    private func edit(_ name: String, _ change: () -> Void) {
        closeAdjust(apply: false)
        let before = doc.image
        change()
        guard doc.image !== before else { return }
        register(name, undo: true)
        refreshUndoButtons()
    }

    private func register(_ name: String, undo: Bool) {
        guard let manager = window?.undoManager else { return }
        manager.registerUndo(withTarget: self) { editor in
            if undo { editor.doc.undo() } else { editor.doc.redo() }
            editor.register(name, undo: !undo)
            editor.refreshUndoButtons()
        }
        manager.setActionName(name)
    }

    private func refreshUndoButtons() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.undoButton.isEnabled = self.window?.undoManager?.canUndo ?? false
            self.redoButton.isEnabled = self.window?.undoManager?.canRedo ?? false
            self.window?.isDocumentEdited = self.doc.isDirty
        }
    }

    // MARK: - EditorCanvasDelegate

    func canvasFinished(_ annotation: Annotation) {
        edit(annotation.tool.title) { doc.draw(annotation) }
    }

    func canvasObscure(_ rect: CGRect, pixelate: Bool) {
        edit(pixelate ? EditTool.pixelate.title : EditTool.blur.title) { doc.obscure(rect, pixelate: pixelate) }
    }

    func canvasRequestText(at point: CGPoint) {
        guard let window else { return }
        let alert = NSAlert()
        alert.messageText = L.t("Надпись", "Text")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        field.placeholderString = L.t("Текст надписи", "Your text")
        alert.accessoryView = field
        alert.addButton(withTitle: L.t("Добавить", "Add"))
        alert.addButton(withTitle: L.t("Отмена", "Cancel"))
        alert.window.initialFirstResponder = field
        let fontSize = max(14, canvas.size * 5) / canvas.viewScale
        let color = canvas.color
        alert.beginSheetModal(for: window) { [weak self] response in
            guard let self, response == .alertFirstButtonReturn, !field.stringValue.isEmpty else { return }
            var a = Annotation(tool: .text, points: [point], color: color, width: fontSize)
            a.text = field.stringValue
            self.edit(EditTool.text.title) { self.doc.draw(a) }
        }
    }

    func canvasCropChanged() { cropChangedInfo() }

    func canvasApplyCrop() {
        guard let r = canvas.cropRect else { return }
        edit(EditTool.crop.title) { doc.crop(r) }
    }

    func canvasKeyDown(_ event: NSEvent) -> Bool {
        let mods = event.modifierFlags.intersection([.command, .option, .control])
        guard mods.isEmpty, let key = event.charactersIgnoringModifiers?.lowercased() else { return false }
        if key == "\r" || key == "\u{3}" {
            canvasApplyCrop()
            return true
        }
        if key == "\u{1b}" {
            if canvas.tool == .crop { canvas.clearCrop() } else { closeAdjust(apply: false) }
            return true
        }
        if let tool = EditTool.allCases.first(where: { $0.key == key }) {
            select(tool)
            return true
        }
        return false
    }

    // MARK: - Команды (меню «Инструменты» и кнопки)

    @objc func editPicture(_ sender: Any?) { showWindow(nil) }

    @objc func selectEditTool(_ sender: Any?) {
        guard let raw = (sender as? NSMenuItem)?.representedObject as? String, let tool = EditTool(rawValue: raw) else { return }
        select(tool)
    }

    @objc func rotateRight(_ sender: Any?) {
        edit(L.t("поворот", "Rotate")) { doc.rotate(clockwise: true) }
    }

    @objc func rotateLeft(_ sender: Any?) {
        edit(L.t("поворот", "Rotate")) { doc.rotate(clockwise: false) }
    }

    @objc func flipHorizontal(_ sender: Any?) {
        edit(L.t("отражение", "Flip")) { doc.flip(horizontal: true) }
    }

    @objc func flipVertical(_ sender: Any?) {
        edit(L.t("отражение", "Flip")) { doc.flip(horizontal: false) }
    }

    @objc func applyFilter(_ sender: Any?) {
        guard let raw = (sender as? NSMenuItem)?.representedObject as? String, let filter = QuickFilter(rawValue: raw) else { return }
        edit(filter.title) { doc.apply(filter) }
    }

    @objc func showResize(_ sender: Any?) {
        guard let window, resizeSheet == nil else { return }
        closeAdjust(apply: false)
        let sheet = ResizeSheet(size: doc.size)
        resizeSheet = sheet
        sheet.begin(for: window) { [weak self] size in
            guard let self else { return }
            self.resizeSheet = nil
            if let size { self.edit(L.t("изменение размера", "Resize")) { self.doc.resize(to: size) } }
        }
    }

    @objc func showAdjust(_ sender: Any?) {
        guard adjustPanel == nil else { return }
        let panel = AdjustPanel()
        let scale = window?.backingScaleFactor ?? 2
        adjustBase = doc.preview(maxPixels: max(canvas.bounds.width, canvas.bounds.height) * scale)
        panel.onChange = { [weak self] values in
            guard let self, let base = self.adjustBase, let image = self.doc.renderPreview(values.apply(to: base)) else { return }
            self.canvas.setPreview(image)
        }
        panel.onFinish = { [weak self] values in
            self?.closeAdjust(apply: values != nil, values: values)
        }
        adjustPanel = panel
        content.right = panel
    }

    private func closeAdjust(apply: Bool, values: Adjustments? = nil) {
        guard adjustPanel != nil else { return }
        adjustPanel = nil
        adjustBase = nil
        content.right = nil
        if apply, let values, !values.isIdentity {
            edit(L.t("коррекция цвета", "Adjust Colors")) { doc.apply(values) }
        } else {
            canvas.setImage(doc.image, size: doc.size)
        }
        window?.makeFirstResponder(canvas)
    }

    // MARK: - Сохранение

    @objc func saveAs(_ sender: Any?) {
        guard let window, !saving else { return }
        closeAdjust(apply: false)
        let base = doc.source.deletingPathExtension().lastPathComponent
        ImageExporter.runSavePanel(for: window, original: doc.source, suggestedBase: base, edited: true) { [weak self] url, format, quality in
            self?.write(to: url, format: format, quality: quality)
        }
    }

    private func write(to url: URL, format: ExportFormat, quality: Double) {
        saving = true
        let image = doc.image
        let source = doc.source
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = Result { try ImageExporter.write(image, to: url, format: format, quality: quality, metadataFrom: source) }
            DispatchQueue.main.async {
                guard let self else { return }
                self.saving = false
                switch result {
                case .success:
                    self.doc.markSaved()
                    self.window?.isDocumentEdited = false
                    self.onSaved(url)
                    if self.closeAfterSave { self.window?.close() }
                case .failure(let error):
                    self.closeAfterSave = false
                    if let window = self.window { NSAlert(error: error).beginSheetModal(for: window) }
                }
            }
        }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard doc.isDirty else { return true }
        let alert = NSAlert()
        alert.messageText = L.t("Сохранить правки в копию?", "Save your changes to a copy?")
        alert.informativeText = L.t("Оригинал останется без изменений.", "The original stays unchanged.")
        alert.addButton(withTitle: L.t("Сохранить копию…", "Save a Copy…"))
        alert.addButton(withTitle: L.t("Отмена", "Cancel"))
        alert.addButton(withTitle: L.t("Не сохранять", "Don't Save"))
        alert.beginSheetModal(for: sender) { [weak self] response in
            guard let self else { return }
            switch response {
            case .alertFirstButtonReturn:
                self.closeAfterSave = true
                DispatchQueue.main.async { self.saveAs(nil) }
            case .alertThirdButtonReturn:
                self.doc.markSaved()
                sender.close()
            default:
                break
            }
        }
        return false
    }

    func windowWillClose(_ notification: Notification) {
        Self.editors.removeAll { $0 === self }
    }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        if item.action == #selector(selectEditTool(_:)) {
            item.state = (item.representedObject as? String) == canvas.tool.rawValue ? .on : .off
        }
        return !saving
    }
}

/// Кружок цвета на нижней панели.
private final class SwatchButton: NSView {
    let color: NSColor
    var onClick: ((NSColor) -> Void)?

    init(color: NSColor) {
        self.color = color
        super.init(frame: NSRect(x: 0, y: 0, width: 18, height: 18))
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: 18).isActive = true
        heightAnchor.constraint(equalToConstant: 18).isActive = true
    }

    required init?(coder: NSCoder) { fatalError() }

    override func mouseDown(with event: NSEvent) { onClick?(color) }

    override func draw(_ dirtyRect: NSRect) {
        let circle = NSBezierPath(ovalIn: bounds.insetBy(dx: 1.5, dy: 1.5))
        color.setFill()
        circle.fill()
        NSColor(white: 0, alpha: 0.35).setStroke()
        circle.lineWidth = 1
        circle.stroke()
    }
}
