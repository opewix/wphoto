import AppKit

// Вся графика рисуется кодом: ни значков, ни шрифтов Microsoft в программе нет.
// Файл самодостаточен — его же собирает scripts/appicon для иконки программы.

extension NSColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: alpha)
    }
}

enum Glyph {
    case zoom, zoomIn, zoomOut, fit, actualSize
    case previous, next, slideshow
    case rotateLeft, rotateRight, delete
    case print, copyTo, edit
}

enum Glyphs {
    /// `xp` — палитра XP, иначе Vista/7. `hover` нужен только «шару» слайд-шоу.
    static func draw(_ glyph: Glyph, in r: NSRect, xp: Bool, enabled: Bool = true, hover: Bool = false) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.saveGState()
        if !enabled { ctx.setAlpha(0.35) }
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        switch glyph {
        case .zoom: magnifier(r, sign: 0, xp: xp)
        case .zoomIn: magnifier(r, sign: 1, xp: xp)
        case .zoomOut: magnifier(r, sign: -1, xp: xp)
        case .fit: frame(r, actual: false, xp: xp)
        case .actualSize: frame(r, actual: true, xp: xp)
        case .previous: arrow(r, right: false, xp: xp)
        case .next: arrow(r, right: true, xp: xp)
        case .slideshow: xp ? screen(r) : orb(r, hover: hover && enabled)
        case .rotateLeft: rotate(r, clockwise: false, xp: xp)
        case .rotateRight: rotate(r, clockwise: true, xp: xp)
        case .delete: cross(r)
        case .print: printer(r)
        case .copyTo: floppy(r)
        case .edit: pencil(r)
        }
        ctx.endTransparencyLayer()
        ctx.restoreGState()
    }

    // MARK: - Помощники

    private static func fill(_ path: NSBezierPath, _ top: NSColor, _ bottom: NSColor) {
        NSGradient(starting: bottom, ending: top)?.draw(in: path, angle: 90)
    }

    private static func stroke(_ path: NSBezierPath, _ color: NSColor, _ width: CGFloat) {
        color.setStroke()
        path.lineWidth = width
        path.stroke()
    }

    private static func p(_ r: NSRect, _ x: CGFloat, _ y: CGFloat) -> NSPoint {
        NSPoint(x: r.minX + x * r.width, y: r.minY + y * r.height)
    }

    private static func polygon(_ r: NSRect, _ points: [(CGFloat, CGFloat)]) -> NSBezierPath {
        let path = NSBezierPath()
        for (i, point) in points.enumerated() {
            let pt = p(r, point.0, point.1)
            if i == 0 { path.move(to: pt) } else { path.line(to: pt) }
        }
        path.close()
        path.lineJoinStyle = .round
        return path
    }

    private static func gloss(_ r: NSRect) {
        let shine = NSBezierPath(ovalIn: NSRect(x: r.minX + r.width * 0.18, y: r.midY,
                                                width: r.width * 0.64, height: r.height * 0.42))
        fill(shine, NSColor(white: 1, alpha: 0.7), NSColor(white: 1, alpha: 0.05))
    }

    // MARK: - Значки

    private static func arrow(_ r: NSRect, right: Bool, xp: Bool) {
        if xp {
            let disc = r.insetBy(dx: r.width * 0.06, dy: r.height * 0.06)
            let circle = NSBezierPath(ovalIn: disc)
            fill(circle, NSColor(hex: 0x86D872), NSColor(hex: 0x2A8A1C))
            stroke(circle, NSColor(hex: 0x1E6614), 1)
            gloss(disc)
            NSColor.white.setFill()
            arrowPath(r.insetBy(dx: r.width * 0.26, dy: r.height * 0.28), right: right).fill()
        } else {
            let path = arrowPath(r.insetBy(dx: r.width * 0.04, dy: r.height * 0.1), right: right)
            fill(path, NSColor(hex: 0x74BCF7), NSColor(hex: 0x1A5CB6))
            stroke(path, NSColor(hex: 0x123F80), max(1, r.width / 22))
            let shine = arrowPath(r.insetBy(dx: r.width * 0.04, dy: r.height * 0.1), right: right)
            NSGraphicsContext.saveGraphicsState()
            shine.addClip()
            NSColor(white: 1, alpha: 0.28).setFill()
            NSRect(x: r.minX, y: r.midY, width: r.width, height: r.height / 2).fill()
            NSGraphicsContext.restoreGraphicsState()
        }
    }

    private static func arrowPath(_ r: NSRect, right: Bool) -> NSBezierPath {
        let points: [(CGFloat, CGFloat)] = [(0.06, 0.34), (0.5, 0.34), (0.5, 0.06), (0.96, 0.5),
                                            (0.5, 0.94), (0.5, 0.66), (0.06, 0.66)]
        return polygon(r, points.map { (right ? $0.0 : 1 - $0.0, $0.1) })
    }

    /// Круглая синяя кнопка слайд-шоу с треугольником «Пуск».
    private static func orb(_ r: NSRect, hover: Bool) {
        let disc = r.insetBy(dx: 1, dy: 1)
        let circle = NSBezierPath(ovalIn: disc)
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor(white: 0, alpha: 0.3)
        shadow.shadowBlurRadius = 2
        shadow.shadowOffset = NSSize(width: 0, height: -1)
        shadow.set()
        NSColor(hex: 0x0B3D8C).setFill()
        circle.fill()
        NSGraphicsContext.restoreGraphicsState()
        fill(circle, NSColor(hex: hover ? 0x62B4FA : 0x4C9FEE), NSColor(hex: hover ? 0x1452B0 : 0x0B3D8C))
        // Свечение снизу, как у стекла.
        let glow = NSBezierPath(ovalIn: NSRect(x: disc.minX + disc.width * 0.2, y: disc.minY + disc.height * 0.04,
                                               width: disc.width * 0.6, height: disc.height * 0.4))
        fill(glow, NSColor(hex: 0x5FD0FF, alpha: 0), NSColor(hex: 0x5FD0FF, alpha: 0.55))
        stroke(circle, NSColor(hex: 0x09306A), 1)
        gloss(disc)
        let triangle = polygon(r, [(0.4, 0.29), (0.4, 0.71), (0.73, 0.5)])
        NSGraphicsContext.saveGraphicsState()
        let tshadow = NSShadow()
        tshadow.shadowColor = NSColor(hex: 0x05224F, alpha: 0.6)
        tshadow.shadowBlurRadius = 1.5
        tshadow.shadowOffset = NSSize(width: 0, height: -1)
        tshadow.set()
        NSColor.white.setFill()
        triangle.fill()
        NSGraphicsContext.restoreGraphicsState()
    }

    /// XP: экран с треугольником.
    private static func screen(_ r: NSRect) {
        let body = NSBezierPath(roundedRect: NSRect(x: r.minX + r.width * 0.06, y: r.minY + r.height * 0.24,
                                                    width: r.width * 0.88, height: r.height * 0.66),
                                xRadius: r.width * 0.06, yRadius: r.width * 0.06)
        fill(body, NSColor(hex: 0xD8D8D8), NSColor(hex: 0x8C8C8C))
        stroke(body, NSColor(hex: 0x555555), 1)
        let glass = NSBezierPath(rect: NSRect(x: r.minX + r.width * 0.14, y: r.minY + r.height * 0.32,
                                              width: r.width * 0.72, height: r.height * 0.5))
        fill(glass, NSColor(hex: 0x6FB2F2), NSColor(hex: 0x1C4FA8))
        let stand = polygon(r, [(0.36, 0.08), (0.64, 0.08), (0.58, 0.24), (0.42, 0.24)])
        fill(stand, NSColor(hex: 0xA8A8A8), NSColor(hex: 0x707070))
        NSColor.white.setFill()
        polygon(r, [(0.43, 0.42), (0.43, 0.72), (0.65, 0.57)]).fill()
    }

    private static func magnifier(_ r: NSRect, sign: Int, xp: Bool) {
        let center = p(r, 0.42, 0.58)
        let radius = r.width * 0.28
        let handle = NSBezierPath()
        handle.move(to: NSPoint(x: center.x + radius * 0.7, y: center.y - radius * 0.7))
        handle.line(to: p(r, 0.88, 0.12))
        handle.lineCapStyle = .round
        stroke(handle, NSColor(hex: xp ? 0x7A5320 : 0x2B3A4E), r.width * 0.15)
        let lensRect = NSRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
        let lens = NSBezierPath(ovalIn: lensRect)
        fill(lens, NSColor(hex: 0xFFFFFF), NSColor(hex: 0xBFDDF7))
        stroke(lens, NSColor(hex: xp ? 0x6C6C6C : 0x2F5C93), r.width * 0.08)
        if sign != 0 {
            let mark = NSBezierPath()
            let a = radius * 0.5
            mark.move(to: NSPoint(x: center.x - a, y: center.y))
            mark.line(to: NSPoint(x: center.x + a, y: center.y))
            if sign > 0 {
                mark.move(to: NSPoint(x: center.x, y: center.y - a))
                mark.line(to: NSPoint(x: center.x, y: center.y + a))
            }
            stroke(mark, NSColor(hex: 0x1F3F6B), r.width * 0.09)
        }
    }

    /// «По размеру окна» — рамка с уголками; «Реальный размер» — рамка с «1:1».
    private static func frame(_ r: NSRect, actual: Bool, xp: Bool) {
        let box = NSRect(x: r.minX + r.width * 0.1, y: r.minY + r.height * 0.18,
                         width: r.width * 0.8, height: r.height * 0.64)
        let outline = NSBezierPath(roundedRect: box, xRadius: 1.5, yRadius: 1.5)
        fill(outline, NSColor(hex: 0xFFFFFF), NSColor(hex: xp ? 0xE8E6DC : 0xDCEAF8))
        let ink = NSColor(hex: xp ? 0x3A5FA8 : 0x2F5C93)
        stroke(outline, ink, max(1, r.width * 0.07))
        if actual {
            let font = NSFont.boldSystemFont(ofSize: box.height * 0.62)
            let text = NSAttributedString(string: "1:1", attributes: [.font: font, .foregroundColor: ink])
            let size = text.size()
            text.draw(at: NSPoint(x: box.midX - size.width / 2, y: box.midY - size.height / 2))
        } else {
            let corners = NSBezierPath()
            let inner = box.insetBy(dx: box.width * 0.18, dy: box.height * 0.2)
            let len = inner.width * 0.3
            for (x, y, dx, dy) in [(inner.minX, inner.minY, 1.0, 1.0), (inner.maxX, inner.minY, -1.0, 1.0),
                                   (inner.minX, inner.maxY, 1.0, -1.0), (inner.maxX, inner.maxY, -1.0, -1.0)] {
                corners.move(to: NSPoint(x: x + dx * len, y: y))
                corners.line(to: NSPoint(x: x, y: y))
                corners.line(to: NSPoint(x: x, y: y + dy * len))
            }
            corners.lineCapStyle = .round
            corners.lineJoinStyle = .round
            stroke(corners, ink, max(1, r.width * 0.08))
        }
    }

    private static func rotate(_ r: NSRect, clockwise: Bool, xp: Bool) {
        NSGraphicsContext.saveGraphicsState()
        if !clockwise {
            let flip = NSAffineTransform()
            flip.translateX(by: r.midX, yBy: 0)
            flip.scaleX(by: -1, yBy: 1)
            flip.translateX(by: -r.midX, yBy: 0)
            flip.concat()
        }
        let center = p(r, 0.5, 0.42)
        let radius = r.width * 0.3
        let width = r.width * 0.15
        let endAngle: CGFloat = 15
        let arc = NSBezierPath()
        arc.appendArc(withCenter: center, radius: radius, startAngle: 215, endAngle: endAngle, clockwise: true)
        let color = NSColor(hex: xp ? 0x3A9A2A : 0x2D78D0)
        let dark = NSColor(hex: xp ? 0x1E5E14 : 0x174A8C)
        arc.lineCapStyle = .round
        stroke(arc, dark, width + 2)
        stroke(arc, color, width)
        let theta = endAngle * .pi / 180
        let end = NSPoint(x: center.x + radius * cos(theta), y: center.y + radius * sin(theta))
        let dir = NSPoint(x: sin(theta), y: -cos(theta))
        let normal = NSPoint(x: cos(theta), y: sin(theta))
        let head = NSBezierPath()
        head.move(to: NSPoint(x: end.x + dir.x * width * 1.5, y: end.y + dir.y * width * 1.5))
        head.line(to: NSPoint(x: end.x + normal.x * width * 1.25, y: end.y + normal.y * width * 1.25))
        head.line(to: NSPoint(x: end.x - normal.x * width * 1.25, y: end.y - normal.y * width * 1.25))
        head.close()
        head.lineJoinStyle = .round
        color.setFill()
        head.fill()
        stroke(head, dark, 1)
        NSGraphicsContext.restoreGraphicsState()
    }

    private static func cross(_ r: NSRect) {
        let a: CGFloat = 0.11, e: CGFloat = 0.42
        let plus: [(CGFloat, CGFloat)] = [(a, e), (-a, e), (-a, a), (-e, a), (-e, -a), (-a, -a),
                                          (-a, -e), (a, -e), (a, -a), (e, -a), (e, a), (a, a)]
        let c = CGFloat(cos(Double.pi / 4)), s = CGFloat(sin(Double.pi / 4))
        let points = plus.map { (0.5 + $0.0 * c - $0.1 * s, 0.5 + $0.0 * s + $0.1 * c) }
        let path = polygon(r, points)
        fill(path, NSColor(hex: 0xF4735C), NSColor(hex: 0xB11B0D))
        stroke(path, NSColor(hex: 0x7A1105), max(1, r.width / 22))
    }

    private static func printer(_ r: NSRect) {
        let paper = NSBezierPath(rect: NSRect(x: r.minX + r.width * 0.28, y: r.minY + r.height * 0.5,
                                              width: r.width * 0.44, height: r.height * 0.42))
        NSColor.white.setFill(); paper.fill(); stroke(paper, NSColor(hex: 0x7A7A7A), 1)
        let body = NSBezierPath(roundedRect: NSRect(x: r.minX + r.width * 0.06, y: r.minY + r.height * 0.24,
                                                    width: r.width * 0.88, height: r.height * 0.38),
                                xRadius: r.width * 0.06, yRadius: r.width * 0.06)
        fill(body, NSColor(hex: 0xE2E2E2), NSColor(hex: 0x8E8E8E))
        stroke(body, NSColor(hex: 0x505050), 1)
        let out = NSBezierPath(rect: NSRect(x: r.minX + r.width * 0.24, y: r.minY + r.height * 0.06,
                                            width: r.width * 0.52, height: r.height * 0.28))
        NSColor.white.setFill(); out.fill(); stroke(out, NSColor(hex: 0x7A7A7A), 1)
        NSColor(hex: 0x3BB33B).setFill()
        NSBezierPath(ovalIn: NSRect(x: r.minX + r.width * 0.76, y: r.minY + r.height * 0.46,
                                    width: r.width * 0.08, height: r.width * 0.08)).fill()
    }

    private static func floppy(_ r: NSRect) {
        let body = NSBezierPath(roundedRect: r.insetBy(dx: r.width * 0.1, dy: r.height * 0.1),
                                xRadius: r.width * 0.06, yRadius: r.width * 0.06)
        fill(body, NSColor(hex: 0x4F84D8), NSColor(hex: 0x1C3E88))
        stroke(body, NSColor(hex: 0x142C60), 1)
        let label = NSBezierPath(rect: NSRect(x: r.minX + r.width * 0.24, y: r.minY + r.height * 0.5,
                                              width: r.width * 0.52, height: r.height * 0.34))
        NSColor.white.setFill(); label.fill()
        let shutter = NSBezierPath(rect: NSRect(x: r.minX + r.width * 0.3, y: r.minY + r.height * 0.1,
                                                width: r.width * 0.4, height: r.height * 0.26))
        fill(shutter, NSColor(hex: 0xE6E6E6), NSColor(hex: 0x9A9A9A))
        NSColor(hex: 0x2A2A2A).setFill()
        NSRect(x: r.minX + r.width * 0.54, y: r.minY + r.height * 0.14, width: r.width * 0.09, height: r.height * 0.18).fill()
    }

    private static func pencil(_ r: NSRect) {
        NSGraphicsContext.saveGraphicsState()
        let t = NSAffineTransform()
        t.translateX(by: r.midX, yBy: r.midY)
        t.rotate(byDegrees: 45)
        t.translateX(by: -r.midX, yBy: -r.midY)
        t.concat()
        let w = r.width * 0.2, x0 = r.midX - w / 2
        let body = NSBezierPath(rect: NSRect(x: x0, y: r.minY + r.height * 0.3, width: w, height: r.height * 0.48))
        fill(body, NSColor(hex: 0xFFD966), NSColor(hex: 0xE09B12))
        stroke(body, NSColor(hex: 0x8A5A00), 1)
        let eraser = NSBezierPath(rect: NSRect(x: x0, y: r.minY + r.height * 0.78, width: w, height: r.height * 0.14))
        fill(eraser, NSColor(hex: 0xF7A1B0), NSColor(hex: 0xD45C72))
        stroke(eraser, NSColor(hex: 0x8A3446), 1)
        let tip = NSBezierPath()
        tip.move(to: NSPoint(x: x0, y: r.minY + r.height * 0.3))
        tip.line(to: NSPoint(x: x0 + w, y: r.minY + r.height * 0.3))
        tip.line(to: NSPoint(x: r.midX, y: r.minY + r.height * 0.06))
        tip.close()
        NSColor(hex: 0xF3D9B1).setFill(); tip.fill(); stroke(tip, NSColor(hex: 0x8A5A00), 1)
        NSColor(hex: 0x333333).setFill()
        let lead = NSBezierPath()
        lead.move(to: NSPoint(x: r.midX - w * 0.18, y: r.minY + r.height * 0.11))
        lead.line(to: NSPoint(x: r.midX + w * 0.18, y: r.minY + r.height * 0.11))
        lead.line(to: NSPoint(x: r.midX, y: r.minY + r.height * 0.06))
        lead.close(); lead.fill()
        NSGraphicsContext.restoreGraphicsState()
    }

    // MARK: - Иконка программы

    /// Две фотографии внахлёст: закат позади, день с холмами впереди.
    static func appIcon(in r: NSRect) {
        let side = r.width * 0.7
        let frame = NSRect(x: r.midX - side / 2, y: r.midY - side * 0.4, width: side, height: side * 0.8)
        photo(frame.offsetBy(dx: r.width * 0.04, dy: r.height * 0.05), angle: 9, sunset: true, unit: r.width)
        photo(frame.offsetBy(dx: -r.width * 0.02, dy: -r.height * 0.03), angle: -5, sunset: false, unit: r.width)
    }

    private static func photo(_ frame: NSRect, angle: CGFloat, sunset: Bool, unit: CGFloat) {
        NSGraphicsContext.saveGraphicsState()
        let t = NSAffineTransform()
        t.translateX(by: frame.midX, yBy: frame.midY)
        t.rotate(byDegrees: angle)
        t.translateX(by: -frame.midX, yBy: -frame.midY)
        t.concat()
        let card = NSBezierPath(roundedRect: frame, xRadius: unit * 0.02, yRadius: unit * 0.02)
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor(white: 0, alpha: 0.4)
        shadow.shadowBlurRadius = unit * 0.035
        shadow.shadowOffset = NSSize(width: 0, height: -unit * 0.015)
        shadow.set()
        NSColor.white.setFill()
        card.fill()
        NSGraphicsContext.restoreGraphicsState()
        let pic = frame.insetBy(dx: frame.width * 0.06, dy: frame.width * 0.06)
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: pic).addClip()
        fill(NSBezierPath(rect: pic),
             NSColor(hex: sunset ? 0x5A3F9E : 0x2E7BD6),
             NSColor(hex: sunset ? 0xFFB15C : 0xB4DDFB))
        NSColor(hex: sunset ? 0xFFE08A : 0xFFD54A).setFill()
        let sun = pic.width * 0.16
        NSBezierPath(ovalIn: NSRect(x: pic.minX + pic.width * 0.66, y: pic.minY + pic.height * 0.58,
                                    width: sun, height: sun)).fill()
        let back = NSBezierPath()
        back.move(to: NSPoint(x: pic.minX, y: pic.minY + pic.height * 0.4))
        back.curve(to: NSPoint(x: pic.maxX, y: pic.minY + pic.height * 0.3),
                   controlPoint1: NSPoint(x: pic.minX + pic.width * 0.35, y: pic.minY + pic.height * 0.75),
                   controlPoint2: NSPoint(x: pic.minX + pic.width * 0.6, y: pic.minY + pic.height * 0.2))
        back.line(to: NSPoint(x: pic.maxX, y: pic.minY))
        back.line(to: NSPoint(x: pic.minX, y: pic.minY))
        back.close()
        NSColor(hex: sunset ? 0x6B3B5E : 0x5DB548).setFill()
        back.fill()
        let front = NSBezierPath()
        front.move(to: NSPoint(x: pic.minX, y: pic.minY + pic.height * 0.12))
        front.curve(to: NSPoint(x: pic.maxX, y: pic.minY + pic.height * 0.34),
                    controlPoint1: NSPoint(x: pic.minX + pic.width * 0.4, y: pic.minY + pic.height * 0.05),
                    controlPoint2: NSPoint(x: pic.minX + pic.width * 0.7, y: pic.minY + pic.height * 0.5))
        front.line(to: NSPoint(x: pic.maxX, y: pic.minY))
        front.line(to: NSPoint(x: pic.minX, y: pic.minY))
        front.close()
        NSColor(hex: sunset ? 0x3E2240 : 0x2F8A2C).setFill()
        front.fill()
        NSGraphicsContext.restoreGraphicsState()
        NSGraphicsContext.restoreGraphicsState()
    }
}
