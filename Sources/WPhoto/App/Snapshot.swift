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
