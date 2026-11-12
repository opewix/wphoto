import AppKit

/// Кнопка со значком SF Symbols в духе панелей программы: подсветка, «нажатое» состояние у выбранного.
final class SymbolButton: NSView {
    var isSelected = false { didSet { needsDisplay = true } }
    var isEnabled = true { didSet { needsDisplay = true } }
    var onClick: (() -> Void)?
    private let image: NSImage?
    private var hover = false
    private var pressed = false

    init(symbols: [String], tooltip: String, size: CGFloat = 30) {
        let config = NSImage.SymbolConfiguration(pointSize: 15, weight: .regular)
            .applying(.init(paletteColors: [NSColor(hex: 0x1E395B)]))
        image = symbols.lazy.compactMap { NSImage(systemSymbolName: $0, accessibilityDescription: tooltip) }.first?
            .withSymbolConfiguration(config)
        super.init(frame: NSRect(x: 0, y: 0, width: size, height: size))
        toolTip = tooltip
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: size).isActive = true
        heightAnchor.constraint(equalToConstant: size).isActive = true
    }

    required init?(coder: NSCoder) { fatalError() }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self))
    }

    override func mouseEntered(with event: NSEvent) { hover = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hover = false; needsDisplay = true }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        pressed = true
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        let inside = bounds.contains(convert(event.locationInWindow, from: nil))
        if isEnabled, inside != pressed { pressed = inside; needsDisplay = true }
    }

    override func mouseUp(with event: NSEvent) {
        let fire = pressed
        pressed = false
        needsDisplay = true
        if fire { onClick?() }
    }

    override func draw(_ dirtyRect: NSRect) {
        if isEnabled, isSelected || hover || pressed {
            Theme.drawButtonBackground(bounds, pressed: isSelected || pressed)
        }
        guard let image else { return }
        let size = image.size
        let rect = NSRect(x: ((bounds.width - size.width) / 2).rounded(), y: ((bounds.height - size.height) / 2).rounded(),
                          width: size.width, height: size.height)
        image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: isEnabled ? 1 : 0.35)
    }
}

/// Полоса с фоном панелей текущей темы.
class BarBackground: NSView {
    enum Edge { case top, bottom, left, right }
    let edge: Edge

    init(edge: Edge) {
        self.edge = edge
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        let top = Theme.isXP ? NSColor(hex: 0xF9F8F3) : NSColor(hex: 0xF7FAFE)
        let bottom = Theme.isXP ? NSColor(hex: 0xECE9D8) : NSColor(hex: 0xDCE6F4)
        let angle: CGFloat = (edge == .left || edge == .right) ? 0 : 90
        NSGradient(starting: bottom, ending: top)?.draw(in: bounds, angle: angle)
        (Theme.isXP ? NSColor(hex: 0xC5C2B2) : NSColor(hex: 0xA0AFC3)).setFill()
        switch edge {
        case .top: NSRect(x: 0, y: 0, width: bounds.width, height: 1).fill()
        case .bottom: NSRect(x: 0, y: bounds.height - 1, width: bounds.width, height: 1).fill()
        case .left: NSRect(x: bounds.width - 1, y: 0, width: 1, height: bounds.height).fill()
        case .right: NSRect(x: 0, y: 0, width: 1, height: bounds.height).fill()
        }
    }
}

/// Правая панель «Коррекция»: ползунки с живым предпросмотром, «Сбросить», «Отмена», «Применить».
final class AdjustPanel: BarBackground {
    var onChange: ((Adjustments) -> Void)?
    var onFinish: ((Adjustments?) -> Void)?
    private(set) var values = Adjustments()
    private var sliders: [(WritableKeyPath<Adjustments, Double>, NSSlider, NSTextField)] = []

    init() {
        super.init(edge: .right)
        let rows: [(String, WritableKeyPath<Adjustments, Double>, Double, Double)] = [
            (L.t("Яркость", "Brightness"), \.brightness, -100, 100),
            (L.t("Контраст", "Contrast"), \.contrast, -100, 100),
            (L.t("Насыщенность", "Saturation"), \.saturation, -100, 100),
            (L.t("Оттенок", "Hue"), \.hue, -180, 180),
            (L.t("Экспозиция", "Exposure"), \.exposure, -100, 100),
            (L.t("Теплота", "Warmth"), \.warmth, -100, 100),
            (L.t("Сочность", "Vibrance"), \.vibrance, -100, 100),
            (L.t("Резкость", "Sharpness"), \.sharpness, 0, 100),
        ]
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 4
        let title = NSTextField(labelWithString: L.t("Коррекция цвета", "Adjust Colors"))
        title.font = .boldSystemFont(ofSize: 13)
        stack.addArrangedSubview(title)
        stack.setCustomSpacing(12, after: title)
        for (name, key, lo, hi) in rows {
            let label = NSTextField(labelWithString: name)
            let value = NSTextField(labelWithString: "0")
            value.alignment = .right
            value.textColor = .secondaryLabelColor
            value.widthAnchor.constraint(equalToConstant: 40).isActive = true
            let header = NSStackView(views: [label, NSView(), value])
            header.widthAnchor.constraint(equalToConstant: 210).isActive = true
            let slider = NSSlider(value: 0, minValue: lo, maxValue: hi, target: self, action: #selector(changed(_:)))
            slider.isContinuous = true
            slider.widthAnchor.constraint(equalToConstant: 210).isActive = true
            stack.addArrangedSubview(header)
            stack.addArrangedSubview(slider)
            stack.setCustomSpacing(10, after: slider)
            sliders.append((key, slider, value))
        }
        let reset = NSButton(title: L.t("Сбросить", "Reset"), target: self, action: #selector(reset))
        let cancel = NSButton(title: L.t("Отмена", "Cancel"), target: self, action: #selector(cancel))
        cancel.keyEquivalent = "\u{1b}"
        let apply = NSButton(title: L.t("Применить", "Apply"), target: self, action: #selector(apply))
        apply.keyEquivalent = "\r"
        let buttons = NSStackView(views: [reset, NSView(), cancel, apply])
        buttons.widthAnchor.constraint(equalToConstant: 210).isActive = true
        stack.setCustomSpacing(16, after: stack.arrangedSubviews.last!)
        stack.addArrangedSubview(buttons)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 16),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func reset(to newValues: Adjustments = Adjustments()) {
        values = newValues
        for (key, slider, label) in sliders {
            slider.doubleValue = values[keyPath: key]
            label.stringValue = "\(Int(values[keyPath: key].rounded()))"
        }
    }

    @objc private func changed(_ sender: NSSlider) {
        guard let row = sliders.first(where: { $0.1 === sender }) else { return }
        values[keyPath: row.0] = sender.doubleValue.rounded()
        row.2.stringValue = "\(Int(sender.doubleValue.rounded()))"
        onChange?(values)
    }

    @objc private func reset() {
        reset(to: Adjustments())
        onChange?(values)
    }

    @objc private func cancel() { onFinish?(nil) }
    @objc private func apply() { onFinish?(values) }
}

/// Окно «Изменить размер»: пиксели или проценты, с пропорциями или без.
final class ResizeSheet: NSWindowController {
    private let original: CGSize
    private let widthField = NSTextField()
    private let heightField = NSTextField()
    private let unit = NSPopUpButton()
    private let keep = NSButton(checkboxWithTitle: L.t("Сохранять пропорции", "Keep proportions"), target: nil, action: nil)
    private let result = NSTextField(labelWithString: "")
    private var completion: ((CGSize?) -> Void)?

    init(size: CGSize) {
        original = size
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 340, height: 200), styleMask: [.titled], backing: .buffered, defer: false)
        super.init(window: panel)
        build()
    }

    required init?(coder: NSCoder) { fatalError() }

    private var percent: Bool { unit.indexOfSelectedItem == 1 }

    /// Значение поля прямо во время ввода (doubleValue сбил бы курсор).
    private func number(_ field: NSTextField) -> Double {
        Double(field.stringValue.replacingOccurrences(of: ",", with: ".")
            .components(separatedBy: .whitespaces).joined()) ?? 0
    }

    private func build() {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 1
        formatter.minimum = 0.1
        formatter.usesGroupingSeparator = false
        for field in [widthField, heightField] {
            field.formatter = formatter
            field.alignment = .right
            field.widthAnchor.constraint(equalToConstant: 90).isActive = true
            field.target = self
            field.action = #selector(fieldChanged(_:))
            field.delegate = self
        }
        unit.addItems(withTitles: [L.t("пиксели", "pixels"), L.t("проценты", "percent")])
        unit.target = self
        unit.action = #selector(unitChanged)
        keep.state = .on
        result.textColor = .secondaryLabelColor
        let grid = NSGridView(views: [
            [NSTextField(labelWithString: L.t("Ширина:", "Width:")), widthField, unit],
            [NSTextField(labelWithString: L.t("Высота:", "Height:")), heightField, NSView()],
            [NSView(), keep, NSView()],
            [NSView(), result, NSView()],
        ])
        grid.column(at: 0).xPlacement = .trailing
        grid.rowSpacing = 8
        grid.cell(atColumnIndex: 1, rowIndex: 2).row?.mergeCells(in: NSRange(location: 1, length: 2))
        grid.cell(atColumnIndex: 1, rowIndex: 3).row?.mergeCells(in: NSRange(location: 1, length: 2))
        let title = NSTextField(labelWithString: L.t("Изменить размер", "Resize Image"))
        title.font = .boldSystemFont(ofSize: 13)
        let cancel = NSButton(title: L.t("Отмена", "Cancel"), target: self, action: #selector(cancel))
        cancel.keyEquivalent = "\u{1b}"
        let ok = NSButton(title: L.t("Изменить", "Resize"), target: self, action: #selector(confirm))
        ok.keyEquivalent = "\r"
        let buttons = NSStackView(views: [NSView(), cancel, ok])
        let stack = NSStackView(views: [title, grid, buttons])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.edgeInsets = NSEdgeInsets(top: 18, left: 20, bottom: 18, right: 20)
        buttons.widthAnchor.constraint(equalTo: grid.widthAnchor).isActive = true
        window?.contentView = stack
        fill()
    }

    private func fill() {
        if percent {
            widthField.doubleValue = 100
            heightField.doubleValue = 100
        } else {
            widthField.doubleValue = original.width
            heightField.doubleValue = original.height
        }
        updateResult()
    }

    private var target: CGSize {
        if percent {
            return CGSize(width: (original.width * number(widthField) / 100).rounded(),
                          height: (original.height * number(heightField) / 100).rounded())
        }
        return CGSize(width: number(widthField).rounded(), height: number(heightField).rounded())
    }

    private func updateResult() {
        let t = target
        result.stringValue = L.t("Было ", "From ") + "\(Int(original.width)) × \(Int(original.height))"
            + L.t(", станет ", " to ") + "\(Int(t.width)) × \(Int(t.height))"
    }

    @objc private func fieldChanged(_ sender: NSTextField) {
        syncProportions(from: sender)
    }

    fileprivate func syncProportions(from sender: NSTextField) {
        if keep.state == .on {
            if percent {
                (sender === widthField ? heightField : widthField).doubleValue = number(sender)
            } else if sender === widthField {
                heightField.doubleValue = (number(widthField) * original.height / original.width).rounded()
            } else {
                widthField.doubleValue = (number(heightField) * original.width / original.height).rounded()
            }
        }
        updateResult()
    }

    @objc private func unitChanged() { fill() }

    func begin(for parent: NSWindow, completion: @escaping (CGSize?) -> Void) {
        self.completion = completion
        guard let window else { return }
        parent.beginSheet(window)
    }

    private func finish(_ size: CGSize?) {
        guard let window else { return }
        window.sheetParent?.endSheet(window)
        completion?(size)
        completion = nil
    }

    @objc private func cancel() { finish(nil) }

    @objc private func confirm() {
        let t = target
        guard t.width >= 1, t.height >= 1, t.width <= 30000, t.height <= 30000 else {
            NSSound.beep()
            return
        }
        finish(t)
    }
}

extension ResizeSheet: NSTextFieldDelegate {
    func controlTextDidChange(_ obj: Notification) {
        if let field = obj.object as? NSTextField { syncProportions(from: field) }
    }
}
