import AppKit

enum EditTool: String, CaseIterable {
    case crop, pen, brush, highlighter, rectangle, ellipse, line, arrow, text, blur, pixelate

    var title: String {
        switch self {
        case .crop: return L.t("Обрезка", "Crop")
        case .pen: return L.t("Карандаш", "Pencil")
        case .brush: return L.t("Кисть", "Brush")
        case .highlighter: return L.t("Маркер", "Highlighter")
        case .rectangle: return L.t("Прямоугольник", "Rectangle")
        case .ellipse: return L.t("Эллипс", "Ellipse")
        case .line: return L.t("Линия", "Line")
        case .arrow: return L.t("Стрелка", "Arrow")
        case .text: return L.t("Текст", "Text")
        case .blur: return L.t("Размыть область", "Blur Area")
        case .pixelate: return L.t("Пикселизация области", "Pixelate Area")
        }
    }

    /// Клавиша выбора инструмента в окне правки.
    var key: String {
        switch self {
        case .crop: return "c"
        case .pen: return "p"
        case .brush: return "b"
        case .highlighter: return "h"
        case .rectangle: return "r"
        case .ellipse: return "e"
        case .line: return "l"
        case .arrow: return "a"
        case .text: return "t"
        case .blur: return "u"
        case .pixelate: return "x"
        }
    }

    var symbols: [String] {
        switch self {
        case .crop: return ["crop"]
        case .pen: return ["pencil"]
        case .brush: return ["paintbrush.pointed", "paintbrush"]
        case .highlighter: return ["highlighter", "pencil.tip"]
        case .rectangle: return ["rectangle"]
        case .ellipse: return ["circle"]
        case .line: return ["line.diagonal", "minus"]
        case .arrow: return ["arrow.up.right"]
        case .text: return ["textformat"]
        case .blur: return ["drop.halffull", "drop"]
        case .pixelate: return ["squareshape.split.3x3", "square.grid.3x3"]
        }
    }

    var isStroke: Bool { [.pen, .brush, .highlighter].contains(self) }
    var isShape: Bool { [.rectangle, .ellipse, .line, .arrow].contains(self) }
    var canFill: Bool { [.rectangle, .ellipse].contains(self) }
    var usesColor: Bool { isStroke || isShape || self == .text }
}

/// Нарисованное: штрих, фигура или надпись. Рисуется в координатах рисунка; та же отрисовка
/// служит и предпросмотром поверх экрана, и окончательной — в пиксели.
struct Annotation {
    var tool: EditTool
    var points: [CGPoint]
    var color: NSColor
    /// Толщина в пикселях рисунка.
    var width: CGFloat
    var fill = false
    var text = ""

    func draw(in ctx: CGContext) {
        ctx.saveGState()
        defer { ctx.restoreGState() }
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        let cg = color.cgColor
        ctx.setStrokeColor(cg)
        ctx.setFillColor(cg)
        guard let first = points.first else { return }
        let last = points.last ?? first
        switch tool {
        case .pen, .brush, .highlighter:
            var lineWidth = width
            if tool == .brush {
                lineWidth = width * 2.5
                ctx.setShadow(offset: .zero, blur: lineWidth * 0.5, color: cg)
            } else if tool == .highlighter {
                lineWidth = width * 4
                ctx.setLineCap(.square)
                ctx.setAlpha(0.4)
                ctx.setBlendMode(.multiply)
            }
            ctx.setLineWidth(lineWidth)
            ctx.addPath(Self.smoothPath(points))
            ctx.strokePath()
        case .rectangle, .ellipse:
            let rect = CGRect(x: min(first.x, last.x), y: min(first.y, last.y),
                              width: abs(last.x - first.x), height: abs(last.y - first.y))
            ctx.setLineWidth(width)
            if tool == .rectangle {
                ctx.setLineJoin(.miter)
                if fill { ctx.fill(rect) } else { ctx.stroke(rect) }
            } else {
                if fill { ctx.fillEllipse(in: rect) } else { ctx.strokeEllipse(in: rect) }
            }
        case .line, .arrow:
            ctx.setLineWidth(width)
            var end = last
            if tool == .arrow {
                let angle = atan2(last.y - first.y, last.x - first.x)
                let head = max(width * 4, 10)
                // Линия кончается у основания наконечника, чтобы не торчала из острия.
                end = CGPoint(x: last.x - cos(angle) * head * 0.8, y: last.y - sin(angle) * head * 0.8)
                ctx.beginPath()
                ctx.move(to: last)
                ctx.addLine(to: CGPoint(x: last.x - head * cos(angle - .pi / 7), y: last.y - head * sin(angle - .pi / 7)))
                ctx.addLine(to: CGPoint(x: last.x - head * cos(angle + .pi / 7), y: last.y - head * sin(angle + .pi / 7)))
                ctx.closePath()
                ctx.fillPath()
            }
            ctx.beginPath()
            ctx.move(to: first)
            ctx.addLine(to: end)
            ctx.strokePath()
        case .text:
            let font = NSFont.boldSystemFont(ofSize: width)
            let string = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color])
            let size = string.size()
            let previous = NSGraphicsContext.current
            NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
            // Точка щелчка — левый верхний угол надписи.
            string.draw(at: NSPoint(x: first.x, y: first.y - size.height))
            NSGraphicsContext.current = previous
        case .crop, .blur, .pixelate:
            break
        }
    }

    /// Сглаженная кривая через середины отрезков — штрих без «ступенек».
    static func smoothPath(_ points: [CGPoint]) -> CGPath {
        let path = CGMutablePath()
        guard let first = points.first else { return path }
        path.move(to: first)
        if points.count == 1 {
            path.addLine(to: first)
            return path
        }
        for i in 1..<points.count {
            let mid = CGPoint(x: (points[i - 1].x + points[i].x) / 2, y: (points[i - 1].y + points[i].y) / 2)
            path.addQuadCurve(to: mid, control: points[i - 1])
        }
        path.addLine(to: points[points.count - 1])
        return path
    }
}
