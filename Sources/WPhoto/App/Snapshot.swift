import AppKit

/// `WPhoto -snapshot <папка> [-theme xp] <рисунок>`: рисует окно с рисунком в PNG и выходит.
/// Для README и проверки вида без разрешения на запись экрана.
enum Snapshot {
    static var directory: String? {
        let args = CommandLine.arguments
        guard let index = args.firstIndex(of: "-snapshot"), index + 1 < args.count else { return nil }
        return args[index + 1]
    }

    static func run(into directory: String, files: [URL]) {
        if CommandLine.arguments.contains("-editor"), let file = files.first {
            runEditor(into: directory, file: file)
            return
        }
        let controller = ViewerController.make()
        guard let window = controller.window else { exit(1) }
        window.setFrame(NSRect(x: -4000, y: 200, width: 900, height: 640), display: false)
        window.orderFront(nil)
        controller.open(files)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            let name = "window-\(Settings.theme.rawValue).png"
            save(window, to: URL(fileURLWithPath: directory).appendingPathComponent(name))
            exit(0)
        }
    }

    /// `-editor x`: окно правки после нескольких правок (стрелка, рамка, размытие, коррекция)
    /// и копии во всех форматах — проверка редактора и сохранения.
    private static func runEditor(into directory: String, file: URL) {
        guard let editor = EditorController.open(file, quarterTurns: 0, onSaved: { _ in }),
              let window = editor.window else { exit(1) }
        window.setFrame(NSRect(x: -4000, y: 200, width: 1100, height: 720), display: true)
        let doc = editor.doc
        let w = doc.size.width, h = doc.size.height
        doc.draw(Annotation(tool: .arrow, points: [CGPoint(x: w * 0.15, y: h * 0.2), CGPoint(x: w * 0.45, y: h * 0.55)],
                            color: NSColor(hex: 0xE02424), width: w / 120))
        doc.draw(Annotation(tool: .rectangle, points: [CGPoint(x: w * 0.55, y: h * 0.55), CGPoint(x: w * 0.85, y: h * 0.85)],
                            color: NSColor(hex: 0xFACC15), width: w / 150))
        doc.draw(Annotation(tool: .highlighter, points: [CGPoint(x: w * 0.1, y: h * 0.9), CGPoint(x: w * 0.4, y: h * 0.88)],
                            color: NSColor(hex: 0xFACC15), width: w / 150))
        var text = Annotation(tool: .text, points: [CGPoint(x: w * 0.55, y: h * 0.4)], color: .white, width: w / 20)
        text.text = "WPhoto"
        doc.draw(text)
        doc.obscure(CGRect(x: w * 0.6, y: h * 0.6, width: w * 0.2, height: h * 0.2), pixelate: true)
        var adjust = Adjustments()
        adjust.saturation = 30
        adjust.warmth = 40
        doc.apply(adjust)
        editor.select(.crop)
        editor.showAdjust(nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            save(window, to: URL(fileURLWithPath: directory).appendingPathComponent("editor-\(Settings.theme.rawValue).png"))
            for format in ExportFormat.all {
                let url = URL(fileURLWithPath: directory).appendingPathComponent("export.\(format.ext)")
                do {
                    try ImageExporter.write(doc.image, to: url, format: format, quality: 0.85, metadataFrom: file)
                    print("Wrote \(format.name)")
                } catch {
                    print("FAILED \(format.name): \(error)")
                }
            }
            doc.resize(to: CGSize(width: 640, height: 200))
            doc.crop(CGRect(x: 10, y: 20, width: 300, height: 100))
            doc.flip(horizontal: true)
            for filter in QuickFilter.allCases { doc.apply(filter) }
            print("After resize/crop/filters: \(Int(doc.size.width))x\(Int(doc.size.height))")
            exit(0)
        }
    }

    private static func save(_ window: NSWindow, to url: URL) {
        guard let view = window.contentView, let layer = view.layer else { return }
        view.layoutSubtreeIfNeeded()
        view.displayIfNeeded()
        let scale = window.backingScaleFactor
        let width = Int(view.bounds.width * scale), height = Int(view.bounds.height * scale)
        guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
        ctx.scaleBy(x: scale, y: scale)
        layer.render(in: ctx)
        guard let image = ctx.makeImage(),
              let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else { return }
        try? data.write(to: url)
        print("Saved \(url.path)")
    }
}
