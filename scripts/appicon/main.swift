// Рисует значок программы в .iconset для iconutil: вся плитка — снимок с небом, солнцем и холмами.
// См. scripts/bundle.sh.
import AppKit

// Плитка по сетке значков macOS: холст 1024, отступ 100, сторона 824, радиус 185,4. Только такую форму
// macOS 26 показывает во весь скруглённый квадрат; иную сажает на серую подложку и уменьшает.
let tileRect = NSRect(x: 100, y: 100, width: 824, height: 824)
let tile = NSBezierPath(roundedRect: tileRect, xRadius: 185.4, yRadius: 185.4)

func rgb(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> NSColor {
    NSColor(calibratedRed: r / 255, green: g / 255, blue: b / 255, alpha: a)
}
func gradient(_ path: NSBezierPath, _ top: NSColor, _ bottom: NSColor) {
    NSGradient(starting: top, ending: bottom)!.draw(in: path, angle: -90)
}
func rounded(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ r: CGFloat) -> NSBezierPath {
    NSBezierPath(roundedRect: NSRect(x: x, y: y, width: w, height: h), xRadius: r, yRadius: r)
}
func withShadow(blur: CGFloat, dy: CGFloat, alpha: CGFloat, _ body: () -> Void) {
    NSGraphicsContext.saveGraphicsState()
    let s = NSShadow()
    s.shadowBlurRadius = blur
    s.shadowOffset = NSSize(width: 0, height: -dy)
    s.shadowColor = NSColor(white: 0, alpha: alpha)
    s.set()
    body()
    NSGraphicsContext.restoreGraphicsState()
}

func drawIcon() {
    let r = tileRect
    gradient(NSBezierPath(rect: r), rgb(64, 150, 236), rgb(170, 215, 250))
    rgb(255, 214, 70).setFill()
    NSBezierPath(ovalIn: NSRect(x: r.maxX - r.width * 0.32, y: r.maxY - r.height * 0.36,
                                width: r.width * 0.17, height: r.width * 0.17)).fill()
    let back = NSBezierPath()
    back.move(to: NSPoint(x: r.minX, y: r.minY + r.height * 0.45))
    back.curve(to: NSPoint(x: r.maxX, y: r.minY + r.height * 0.38),
               controlPoint1: NSPoint(x: r.minX + r.width * 0.35, y: r.minY + r.height * 0.7),
               controlPoint2: NSPoint(x: r.minX + r.width * 0.6, y: r.minY + r.height * 0.25))
    back.line(to: NSPoint(x: r.maxX, y: r.minY))
    back.line(to: NSPoint(x: r.minX, y: r.minY))
    back.close()
    gradient(back, rgb(130, 205, 100), rgb(80, 165, 70))
    let front = NSBezierPath()
    front.move(to: NSPoint(x: r.minX, y: r.minY + r.height * 0.18))
    front.curve(to: NSPoint(x: r.maxX, y: r.minY + r.height * 0.32),
                controlPoint1: NSPoint(x: r.minX + r.width * 0.4, y: r.minY + r.height * 0.1),
                controlPoint2: NSPoint(x: r.minX + r.width * 0.7, y: r.minY + r.height * 0.45))
    front.line(to: NSPoint(x: r.maxX, y: r.minY))
    front.line(to: NSPoint(x: r.minX, y: r.minY))
    front.close()
    gradient(front, rgb(70, 160, 60), rgb(40, 120, 40))
}

let out = URL(fileURLWithPath: CommandLine.arguments[1])
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = base * scale
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        let scaleTo = NSAffineTransform()
        scaleTo.scale(by: CGFloat(pixels) / 1024)
        scaleTo.concat()
        NSGraphicsContext.saveGraphicsState()
        tile.addClip()
        drawIcon()
        NSGraphicsContext.restoreGraphicsState()
        NSGraphicsContext.restoreGraphicsState()
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        try! rep.representation(using: .png, properties: [:])!.write(to: out.appendingPathComponent(name))
    }
}

