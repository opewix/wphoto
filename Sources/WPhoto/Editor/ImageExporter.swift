import AppKit
import ImageIO
import UniformTypeIdentifiers

/// Формат сохранения: только те, что macOS умеет записывать на этой машине.
struct ExportFormat: Equatable {
    let name: String
    let identifier: String
    let ext: String
    /// Есть ползунок качества.
    let lossy: Bool
    /// Хранит прозрачность; иначе прозрачные места заливаются белым.
    let alpha: Bool

    var type: UTType { UTType(identifier) ?? .image }

    static let all: [ExportFormat] = {
        let candidates = [
            ExportFormat(name: "JPEG", identifier: "public.jpeg", ext: "jpg", lossy: true, alpha: false),
            ExportFormat(name: "PNG", identifier: "public.png", ext: "png", lossy: false, alpha: true),
            ExportFormat(name: "HEIC", identifier: "public.heic", ext: "heic", lossy: true, alpha: true),
            ExportFormat(name: "WebP", identifier: "org.webmproject.webp", ext: "webp", lossy: true, alpha: true),
            ExportFormat(name: "AVIF", identifier: "public.avif", ext: "avif", lossy: true, alpha: true),
            ExportFormat(name: "TIFF", identifier: "public.tiff", ext: "tiff", lossy: false, alpha: true),
            ExportFormat(name: "BMP", identifier: "com.microsoft.bmp", ext: "bmp", lossy: false, alpha: false),
            ExportFormat(name: "GIF", identifier: "com.compuserve.gif", ext: "gif", lossy: false, alpha: true),
            ExportFormat(name: "JPEG 2000", identifier: "public.jpeg-2000", ext: "jp2", lossy: true, alpha: true),
        ]
        let writable = Set(CGImageDestinationCopyTypeIdentifiers() as? [String] ?? [])
        return candidates.filter { writable.contains($0.identifier) }
    }()

    /// Формат исходного файла, если его можно записать, иначе JPEG.
    static func matching(_ url: URL?) -> ExportFormat {
        let ext = url?.pathExtension.lowercased() ?? ""
        if let type = UTType(filenameExtension: ext), let match = all.first(where: { type.conforms(to: $0.type) }) {
            return match
        }
        return all.first { $0.identifier == "public.jpeg" } ?? all[0]
    }
}

enum ImageExporter {
    /// Окно сохранения копии с выбором формата и качества. Оригинал перезаписать нельзя.
    /// `edited` — к имени добавляется «(правка)»; иначе предлагается то же имя с новым расширением.
    static func runSavePanel(for window: NSWindow, original: URL?, suggestedBase: String, edited: Bool,
                             completion: @escaping (URL, ExportFormat, Double) -> Void) {
        let panel = NSSavePanel()
        var format = ExportFormat.matching(original)
        let accessory = FormatAccessory(format: format)
        panel.accessoryView = accessory
        panel.allowedContentTypes = [format.type]
        panel.canSelectHiddenExtension = true
        panel.directoryURL = original?.deletingLastPathComponent()
        panel.nameFieldStringValue = uniqueName(base: suggestedBase, ext: format.ext, edited: edited,
                                                 in: original?.deletingLastPathComponent())
        panel.title = L.t("Сохранить копию", "Save a Copy")
        panel.prompt = L.t("Сохранить", "Save")
        accessory.onChange = { [weak panel] newFormat in
            guard let panel else { return }
            format = newFormat
            panel.allowedContentTypes = [newFormat.type]
            let base = (panel.nameFieldStringValue as NSString).deletingPathExtension
            panel.nameFieldStringValue = "\(base).\(newFormat.ext)"
        }
        panel.beginSheetModal(for: window) { response in
            guard response == .OK, var url = panel.url else { return }
            if url.pathExtension.lowercased() != format.ext,
               !(UTType(filenameExtension: url.pathExtension)?.conforms(to: format.type) ?? false) {
                url = url.deletingPathExtension().appendingPathExtension(format.ext)
            }
            if let original, url.standardizedFileURL.path == original.standardizedFileURL.path {
                let alert = NSAlert()
                alert.messageText = L.t("Оригинал не перезаписывается", "The original is never overwritten")
                alert.informativeText = L.t("Выберите другое имя — правки сохраняются только в копию.",
                                            "Choose another name — edits are saved to a copy only.")
                alert.beginSheetModal(for: window)
                return
            }
            completion(url, format, accessory.quality)
        }
    }

    /// «Фото (правка).jpg», «Фото (правка 2).jpg»… — первое свободное имя.
    static func uniqueName(base: String, ext: String, edited: Bool, in folder: URL?) -> String {
        let suffix = edited ? L.t("правка", "edited") : L.t("копия", "copy")
        var name = edited ? "\(base) (\(suffix)).\(ext)" : "\(base).\(ext)"
        guard let folder else { return name }
        if !edited, FileManager.default.fileExists(atPath: folder.appendingPathComponent(name).path) {
            name = "\(base) (\(suffix)).\(ext)"
        }
        var n = 2
        while FileManager.default.fileExists(atPath: folder.appendingPathComponent(name).path) {
            name = "\(base) (\(suffix) \(n)).\(ext)"
            n += 1
        }
        return name
    }

    /// Пишет рисунок; метаданные (камера, дата, GPS) берёт из исходника, ориентация — «как есть».
    static func write(_ image: CGImage, to url: URL, format: ExportFormat, quality: Double, metadataFrom source: URL?) throws {
        var output = image
        if !format.alpha, image.alphaInfo != .none, image.alphaInfo != .noneSkipLast, image.alphaInfo != .noneSkipFirst {
            output = flattened(image)
        }
        var props: [CFString: Any] = [:]
        if let source, let src = CGImageSourceCreateWithURL(source as CFURL, nil),
           let original = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] {
            for key in [kCGImagePropertyExifDictionary, kCGImagePropertyGPSDictionary, kCGImagePropertyIPTCDictionary,
                        kCGImagePropertyTIFFDictionary] {
                if var dict = original[key] as? [CFString: Any] {
                    dict.removeValue(forKey: kCGImagePropertyTIFFOrientation)
                    dict.removeValue(forKey: kCGImagePropertyExifPixelXDimension)
                    dict.removeValue(forKey: kCGImagePropertyExifPixelYDimension)
                    props[key] = dict
                }
            }
        }
        props[kCGImagePropertyOrientation] = 1
        if format.lossy {
            props[kCGImageDestinationLossyCompressionQuality] = quality
        }
        let temp = url.deletingLastPathComponent().appendingPathComponent(".\(UUID().uuidString).\(format.ext)")
        guard let destination = CGImageDestinationCreateWithURL(temp as CFURL, format.identifier as CFString, 1, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        CGImageDestinationAddImage(destination, output, props as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            try? FileManager.default.removeItem(at: temp)
            throw CocoaError(.fileWriteUnknown)
        }
        if FileManager.default.fileExists(atPath: url.path) {
            _ = try FileManager.default.replaceItemAt(url, withItemAt: temp)
        } else {
            try FileManager.default.moveItem(at: temp, to: url)
        }
    }

    private static func flattened(_ image: CGImage) -> CGImage {
        let space = image.colorSpace.flatMap { $0.model == .rgb ? $0 : nil } ?? CGColorSpace(name: CGColorSpace.sRGB)!
        guard let ctx = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return image }
        let rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        ctx.setFillColor(CGColor(gray: 1, alpha: 1))
        ctx.fill(rect)
        ctx.draw(image, in: rect)
        return ctx.makeImage() ?? image
    }
}

/// «Формат: [JPEG ▾]  Качество: ———o—» под окном сохранения.
private final class FormatAccessory: NSView {
    var onChange: ((ExportFormat) -> Void)?
    private let popup = NSPopUpButton()
    private let slider = NSSlider(value: 0.9, minValue: 0.3, maxValue: 1, target: nil, action: nil)
    private let qualityLabel = NSTextField(labelWithString: L.t("Качество:", "Quality:"))
    private let percent = NSTextField(labelWithString: "90 %")

    var quality: Double { slider.doubleValue }

    init(format: ExportFormat) {
        super.init(frame: NSRect(x: 0, y: 0, width: 460, height: 44))
        let formatLabel = NSTextField(labelWithString: L.t("Формат:", "Format:"))
        for f in ExportFormat.all { popup.addItem(withTitle: f.name) }
        popup.selectItem(withTitle: format.name)
        popup.target = self
        popup.action = #selector(formatChanged)
        slider.target = self
        slider.action = #selector(qualityChanged)
        slider.widthAnchor.constraint(equalToConstant: 140).isActive = true
        percent.widthAnchor.constraint(equalToConstant: 40).isActive = true
        let stack = NSStackView(views: [formatLabel, popup, qualityLabel, slider, percent])
        stack.spacing = 8
        stack.setCustomSpacing(20, after: popup)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        updateQualityVisibility(format)
    }

    required init?(coder: NSCoder) { fatalError() }

    private var selected: ExportFormat {
        ExportFormat.all[max(0, popup.indexOfSelectedItem)]
    }

    @objc private func formatChanged() {
        updateQualityVisibility(selected)
        onChange?(selected)
    }

    @objc private func qualityChanged() {
        percent.stringValue = "\(Int((slider.doubleValue * 100).rounded())) %"
    }

    private func updateQualityVisibility(_ format: ExportFormat) {
        for view in [qualityLabel, slider, percent] as [NSView] { view.isHidden = !format.lossy }
    }
}
