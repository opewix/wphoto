import AppKit

/// Кнопка со значком: подсветка под мышью, нажатие, недоступность.
final class GlyphButton: NSView {
    var glyph: Glyph { didSet { needsDisplay = true } }
    var glyphSize: CGFloat
    var isOrb = false
    var isEnabled = true { didSet { needsDisplay = true } }
    var onClick: ((GlyphButton) -> Void)?

    private var hover = false
    private var pressed = false

    init(glyph: Glyph, size: CGFloat, glyphSize: CGFloat, tooltip: String) {
        self.glyph = glyph
        self.glyphSize = glyphSize
        super.init(frame: NSRect(x: 0, y: 0, width: size, height: size))
        toolTip = tooltip
    }

    required init?(coder: NSCoder) { fatalError() }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                       owner: self))
    }

    override func mouseEntered(with event: NSEvent) { hover = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hover = false; needsDisplay = true }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        pressed = true
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard isEnabled else { return }
        let inside = bounds.contains(convert(event.locationInWindow, from: nil))
        if inside != pressed { pressed = inside; needsDisplay = true }
    }

    override func mouseUp(with event: NSEvent) {
        let fire = pressed
        pressed = false
        needsDisplay = true
        if fire { onClick?(self) }
    }

    override func draw(_ dirtyRect: NSRect) {
        if !isOrb, isEnabled, hover || pressed {
            Theme.drawButtonBackground(bounds, pressed: pressed)
        }
        var rect = NSRect(x: (bounds.width - glyphSize) / 2, y: (bounds.height - glyphSize) / 2,
                          width: glyphSize, height: glyphSize)
        if pressed { rect = rect.offsetBy(dx: 0, dy: -1) }
        Glyphs.draw(glyph, in: rect, xp: Theme.isXP, enabled: isEnabled, hover: hover || pressed)
    }
}

enum BarCommand {
    case zoom(NSView), zoomIn, zoomOut, toggleFit, fit, actualSize
    case previous, next, slideshow
    case rotateLeft, rotateRight, delete
    case print, copyTo, edit(NSView)
}

/// Нижняя панель кнопок. Vista/7: шар слайд-шоу ровно посередине, слева масштаб,
/// справа поворот и удаление. XP: строка кнопок группами через разделители, по центру.
final class ControlBar: NSView {
    private let handler: (BarCommand) -> Void
    private var groups: [[GlyphButton]] = []
    private var all: [GlyphButton] { groups.flatMap { $0 } }
    private var fitToggle: GlyphButton?
    private var navigation: [GlyphButton] = []
    private var imageButtons: [GlyphButton] = []
    private var separators: [CGFloat] = []

    init(handler: @escaping (BarCommand) -> Void) {
        self.handler = handler
        super.init(frame: .zero)
        Theme.isXP ? buildXP() : buildVista()
        all.forEach(addSubview)
    }

    required init?(coder: NSCoder) { fatalError() }

    private func button(_ glyph: Glyph, _ size: CGFloat, _ glyphSize: CGFloat, _ tip: String,
                        _ command: @escaping (GlyphButton) -> BarCommand) -> GlyphButton {
        let b = GlyphButton(glyph: glyph, size: size, glyphSize: glyphSize, tooltip: tip)
        b.onClick = { [weak self] sender in self?.handler(command(sender)) }
        return b
    }

    private func buildVista() {
        let zoom = button(.zoom, 32, 22, L.t("Изменить масштаб (колесо мыши)", "Change the display size (mouse wheel)")) { .zoom($0) }
        let fit = button(.actualSize, 32, 22, L.t("Реальный размер (⌥⌘0)", "Actual size (⌥⌘0)")) { _ in .toggleFit }
        let prev = button(.previous, 34, 26, L.t("Предыдущий (←)", "Previous (←)")) { _ in .previous }
        let orb = button(.slideshow, 44, 42, L.t("Показ слайдов (⇧⌘F)", "Play slide show (⇧⌘F)")) { _ in .slideshow }
        orb.isOrb = true
        let next = button(.next, 34, 26, L.t("Следующий (→)", "Next (→)")) { _ in .next }
        let left = button(.rotateLeft, 32, 22, L.t("Повернуть против часовой стрелки (⌘L)", "Rotate counterclockwise (⌘L)")) { _ in .rotateLeft }
        let right = button(.rotateRight, 32, 22, L.t("Повернуть по часовой стрелке (⌘R)", "Rotate clockwise (⌘R)")) { _ in .rotateRight }
        let delete = button(.delete, 32, 20, L.t("Удалить (Delete)", "Delete (Delete)")) { _ in .delete }
        groups = [[zoom, fit], [prev, orb, next], [left, right], [delete]]
        fitToggle = fit
        navigation = [prev, next, orb]
        imageButtons = [zoom, fit, left, right, delete]
    }

    private func buildXP() {
        let s: CGFloat = 28, g: CGFloat = 20
        let prev = button(.previous, s, g, L.t("Предыдущий рисунок (←)", "Previous Image (←)")) { _ in .previous }
        let next = button(.next, s, g, L.t("Следующий рисунок (→)", "Next Image (→)")) { _ in .next }
        let fit = button(.fit, s, g, L.t("По размеру окна (⌘0)", "Best Fit (⌘0)")) { _ in .fit }
        let actual = button(.actualSize, s, g, L.t("Реальный размер (⌥⌘0)", "Actual Size (⌥⌘0)")) { _ in .actualSize }
        let show = button(.slideshow, s, g, L.t("Показ слайдов (⇧⌘F)", "Start Slide Show (⇧⌘F)")) { _ in .slideshow }
        let zin = button(.zoomIn, s, g, L.t("Увеличить (+)", "Zoom In (+)")) { _ in .zoomIn }
        let zout = button(.zoomOut, s, g, L.t("Уменьшить (−)", "Zoom Out (−)")) { _ in .zoomOut }
        let right = button(.rotateRight, s, g, L.t("Повернуть по часовой стрелке (⌘R)", "Rotate Clockwise (⌘R)")) { _ in .rotateRight }
        let left = button(.rotateLeft, s, g, L.t("Повернуть против часовой стрелки (⌘L)", "Rotate Counterclockwise (⌘L)")) { _ in .rotateLeft }
        let delete = button(.delete, s, 18, L.t("Удалить (Delete)", "Delete (Delete)")) { _ in .delete }
        let print = button(.print, s, g, L.t("Печать (⌘P)", "Print (⌘P)")) { _ in .print }
        let copy = button(.copyTo, s, g, L.t("Сохранить копию (⇧⌘S)", "Copy To (⇧⌘S)")) { _ in .copyTo }
        let edit = button(.edit, s, g, L.t("Правка (⌘E)", "Edit (⌘E)")) { .edit($0) }
        groups = [[prev, next], [fit, actual], [show], [zin, zout], [right, left], [delete, print, copy, edit]]
        navigation = [prev, next, show]
        imageButtons = [fit, actual, zin, zout, right, left, delete, print, copy, edit]
    }

    func update(hasImage: Bool, canNavigate: Bool, isFit: Bool, fitIsActual: Bool) {
        for b in imageButtons { b.isEnabled = hasImage }
        for b in navigation { b.isEnabled = hasImage }
        navigation.filter { $0.glyph != .slideshow }.forEach { $0.isEnabled = canNavigate }
        if let fitToggle {
            fitToggle.glyph = isFit ? .actualSize : .fit
            fitToggle.toolTip = isFit ? L.t("Реальный размер (⌥⌘0)", "Actual size (⌥⌘0)")
                                      : L.t("По размеру окна (⌘0)", "Fit to window (⌘0)")
            fitToggle.isEnabled = hasImage && !(isFit && fitIsActual)
        }
    }

    override func layout() {
        super.layout()
        separators = []
        if Theme.isXP {
            let gap: CGFloat = 13
            let total = groups.map { $0.reduce(0) { $0 + $1.frame.width } }.reduce(0, +) + gap * CGFloat(groups.count - 1)
            var x = ((bounds.width - total) / 2).rounded()
            for (i, group) in groups.enumerated() {
                if i > 0 {
                    separators.append((x + gap / 2).rounded())
                    x += gap
                }
                for b in group {
                    b.setFrameOrigin(NSPoint(x: x, y: ((bounds.height - b.frame.height) / 2).rounded()))
                    x += b.frame.width
                }
            }
        } else {
            // Шар — по центру; остальные группы — от него в обе стороны.
            let center = groups[1]
            let mid = bounds.midX
            let orb = center[1]
            place(orb, x: mid - orb.frame.width / 2)
            place(center[0], x: orb.frame.minX - 4 - center[0].frame.width)
            place(center[2], x: orb.frame.maxX + 4)
            var x = center[0].frame.minX - 24
            for b in groups[0].reversed() {
                x -= b.frame.width
                place(b, x: x)
                x -= 2
            }
            x = center[2].frame.maxX + 24
            for b in groups[2] {
                place(b, x: x)
                x += b.frame.width + 2
            }
            x += 22
            separators.append(x - 12)
            place(groups[3][0], x: x)
        }
        needsDisplay = true
    }

    private func place(_ b: GlyphButton, x: CGFloat) {
        b.setFrameOrigin(NSPoint(x: x.rounded(), y: ((bounds.height - b.frame.height) / 2).rounded()))
    }

    override func draw(_ dirtyRect: NSRect) {
        if Theme.isXP {
            NSGradient(starting: NSColor(hex: 0xECE9D8), ending: NSColor(hex: 0xF9F8F3))?.draw(in: bounds, angle: 90)
            NSColor(hex: 0xD5D2C5).setFill()
            NSRect(x: 0, y: bounds.height - 1, width: bounds.width, height: 1).fill()
            for x in separators {
                NSColor(hex: 0xC5C2B2).setFill()
                NSRect(x: x, y: 8, width: 1, height: bounds.height - 16).fill()
                NSColor.white.setFill()
                NSRect(x: x + 1, y: 8, width: 1, height: bounds.height - 16).fill()
            }
        } else {
            NSGradient(colors: [NSColor(hex: 0xBACFE9), NSColor(hex: 0xD3E2F4), NSColor(hex: 0xE7F0FA)],
                       atLocations: [0, 0.55, 1], colorSpace: .sRGB)?.draw(in: bounds, angle: 90)
            NSColor(hex: 0x91A9C8).setFill()
            NSRect(x: 0, y: bounds.height - 1, width: bounds.width, height: 1).fill()
            NSColor(white: 1, alpha: 0.8).setFill()
            NSRect(x: 0, y: bounds.height - 2, width: bounds.width, height: 1).fill()
            for x in separators {
                NSColor(hex: 0x9DB4D2).setFill()
                NSRect(x: x, y: 12, width: 1, height: bounds.height - 24).fill()
                NSColor(white: 1, alpha: 0.7).setFill()
                NSRect(x: x + 1, y: 12, width: 1, height: bounds.height - 24).fill()
            }
        }
    }
}

/// Пункт верхней панели Vista/7: подпись, у меню — стрелка «▾».
final class CommandButton: NSView {
    let title: String
    let hasMenu: Bool
    var isEnabled = true { didSet { needsDisplay = true } }
    var onClick: ((CommandButton) -> Void)?
    private var hover = false
    private var pressed = false

    init(title: String, hasMenu: Bool) {
        self.title = title
        self.hasMenu = hasMenu
        super.init(frame: .zero)
        let width = (title as NSString).size(withAttributes: [.font: Theme.font]).width
        setFrameSize(NSSize(width: ceil(width) + (hasMenu ? 30 : 20), height: 24))
    }

    required init?(coder: NSCoder) { fatalError() }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                       owner: self))
    }

    override func mouseEntered(with event: NSEvent) { hover = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hover = false; needsDisplay = true }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        pressed = true
        display()
        onClick?(self)
        pressed = false
        hover = bounds.contains(convert(window?.mouseLocationOutsideOfEventStream ?? .zero, from: nil))
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        if isEnabled, hover || pressed {
            let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 3, yRadius: 3)
            let top = NSColor(hex: pressed ? 0xD4E6F8 : 0xF2F8FE)
            let bottom = NSColor(hex: pressed ? 0xB6D3F1 : 0xD5E8FB)
            NSGradient(starting: bottom, ending: top)?.draw(in: path, angle: 90)
            NSColor(hex: 0x8EB4DD).setStroke()
            path.stroke()
        }
        let color = isEnabled ? NSColor(hex: 0x1E395B) : NSColor(hex: 0x1E395B, alpha: 0.4)
        let text = NSAttributedString(string: title, attributes: [.font: Theme.font, .foregroundColor: color])
        let size = text.size()
        text.draw(at: NSPoint(x: 10, y: ((bounds.height - size.height) / 2).rounded()))
        if hasMenu {
            let x = 10 + ceil(size.width) + 6, y = bounds.midY - 1.5
            let arrow = NSBezierPath()
            arrow.move(to: NSPoint(x: x, y: y + 3))
            arrow.line(to: NSPoint(x: x + 7, y: y + 3))
            arrow.line(to: NSPoint(x: x + 3.5, y: y - 0.5))
            arrow.close()
            color.setFill()
            arrow.fill()
        }
    }
}

enum TopCommand {
    case file(NSView), print, share(NSView), open(NSView), tools(NSView)
}

/// Верхняя панель Vista/7: «Файл ▾», «Печать», «Поделиться», «Открыть ▾», «Инструменты ▾».
final class CommandBar: NSView {
    private var buttons: [CommandButton] = []

    init(handler: @escaping (TopCommand) -> Void) {
        super.init(frame: .zero)
        let items: [(String, Bool, (NSView) -> TopCommand)] = [
            (L.t("Файл", "File"), true, { .file($0) }),
            (L.t("Печать", "Print"), false, { _ in .print }),
            (L.t("Поделиться", "Share"), false, { .share($0) }),
            (L.t("Открыть", "Open"), true, { .open($0) }),
            (L.t("Инструменты", "Tools"), true, { .tools($0) }),
        ]
        for (title, hasMenu, command) in items {
            let b = CommandButton(title: title, hasMenu: hasMenu)
            b.onClick = { handler(command($0)) }
            buttons.append(b)
            addSubview(b)
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    func update(hasImage: Bool) {
        for b in buttons.dropFirst() { b.isEnabled = hasImage }
    }

    override func layout() {
        super.layout()
        var x: CGFloat = 6
        for b in buttons {
            b.setFrameOrigin(NSPoint(x: x, y: ((bounds.height - b.frame.height) / 2).rounded()))
            x += b.frame.width + 2
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        NSGradient(starting: NSColor(hex: 0xDCE6F4), ending: NSColor(hex: 0xF7FAFE))?.draw(in: bounds, angle: 90)
        NSColor(hex: 0xA0AFC3).setFill()
        NSRect(x: 0, y: 0, width: bounds.width, height: 1).fill()
        NSColor(white: 1, alpha: 0.9).setFill()
        NSRect(x: 0, y: bounds.height - 1, width: bounds.width, height: 1).fill()
    }
}
