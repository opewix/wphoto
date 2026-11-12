import AppKit

/// Цвета и размеры текущей темы. Vista/7 — светлое окно, панель команд сверху и голубая
/// стеклянная панель снизу с круглой кнопкой слайд-шоу; XP — белое окно и строка
/// маленьких кнопок внизу.
enum Theme {
    static let changed = Notification.Name("WPhotoThemeChanged")

    static var kind: ThemeKind { Settings.theme }
    static var isXP: Bool { kind == .xp }

    static var commandBarHeight: CGFloat { isXP ? 0 : 30 }
    static var controlBarHeight: CGFloat { isXP ? 38 : 52 }

    static var canvasTop: NSColor { isXP ? .white : NSColor(hex: 0xFFFFFF) }
    static var canvasBottom: NSColor { isXP ? .white : NSColor(hex: 0xEDF2F9) }
    static var messageColor: NSColor { NSColor(hex: 0x4A5A70) }

    static var font: NSFont { NSFont.systemFont(ofSize: 12) }

    // Кнопка под мышью и нажатая.
    static func drawButtonBackground(_ rect: NSRect, pressed: Bool) {
        let path = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 3, yRadius: 3)
        let top: NSColor, bottom: NSColor, border: NSColor
        if isXP {
            top = pressed ? NSColor(hex: 0xE2DFD3) : .white
            bottom = pressed ? NSColor(hex: 0xD8D4C6) : NSColor(hex: 0xEEEDE5)
            border = pressed ? NSColor(hex: 0x9D9886) : NSColor(hex: 0xC3BFAE)
        } else {
            top = pressed ? NSColor(hex: 0xC4DAF3) : NSColor(hex: 0xFFFFFF, alpha: 0.9)
            bottom = pressed ? NSColor(hex: 0xA9C6EA) : NSColor(hex: 0xD6E7FA)
            border = pressed ? NSColor(hex: 0x5A84B8) : NSColor(hex: 0x7DA2CE)
        }
        NSGradient(starting: bottom, ending: top)?.draw(in: path, angle: 90)
        border.setStroke()
        path.lineWidth = 1
        path.stroke()
    }
}
