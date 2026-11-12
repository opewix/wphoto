import AppKit
import ImageIO
import UniformTypeIdentifiers

/// «Свойства»: файл, размеры, даты и данные камеры из EXIF.
final class PropertiesPanel: NSWindowController {
    init() {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 420, height: 300),
                            styleMask: [.titled, .closable, .utilityWindow], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.isFloatingPanel = false
        panel.title = L.t("Свойства", "Properties")
        super.init(window: panel)
    }

    required init?(coder: NSCoder) { fatalError() }

    func show(_ url: URL, near parent: NSWindow?) {
        guard let window else { return }
        window.title = L.t("Свойства: ", "Properties: ") + url.lastPathComponent
        let rows = Self.rows(url).map { label, value -> [NSView] in
            let name = NSTextField(labelWithString: label + ":")
            name.textColor = .secondaryLabelColor
            name.alignment = .right
            let field = NSTextField(wrappingLabelWithString: value)
            field.isSelectable = true
            field.preferredMaxLayoutWidth = 280
            return [name, field]
        }
        let grid = NSGridView(views: rows)
        grid.rowSpacing = 6
        grid.columnSpacing = 10
        grid.column(at: 0).xPlacement = .trailing
        grid.translatesAutoresizingMaskIntoConstraints = false
        let host = NSView()
        host.addSubview(grid)
        NSLayoutConstraint.activate([
            grid.leadingAnchor.constraint(equalTo: host.leadingAnchor, constant: 20),
            grid.trailingAnchor.constraint(equalTo: host.trailingAnchor, constant: -20),
            grid.topAnchor.constraint(equalTo: host.topAnchor, constant: 18),
            grid.bottomAnchor.constraint(equalTo: host.bottomAnchor, constant: -18),
        ])
        window.contentView = host
        window.setContentSize(host.fittingSize)
        if !window.isVisible, let parent {
            window.setFrameTopLeftPoint(NSPoint(x: parent.frame.maxX - window.frame.width - 30, y: parent.frame.maxY - 60))
        }
        window.makeKeyAndOrderFront(nil)
    }

    static func rows(_ url: URL) -> [(String, String)] {
        var rows: [(String, String)] = [
            (L.t("Имя", "Name"), url.lastPathComponent),
            (L.t("Папка", "Folder"), url.deletingLastPathComponent().path),
        ]
        if let type = UTType(filenameExtension: url.pathExtension)?.localizedDescription {
            rows.append((L.t("Тип", "Type"), type))
        }
        let dates = DateFormatter()
        dates.dateStyle = .long
        dates.timeStyle = .short
        let attrs = (try? FileManager.default.attributesOfItem(atPath: url.path)) ?? [:]
        if let size = attrs[.size] as? Int64 {
            rows.append((L.t("Размер", "Size"), ByteCountFormatter.string(fromByteCount: size, countStyle: .file)))
        }
        if let source = CGImageSourceCreateWithURL(url as CFURL, nil),
           let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] {
            let size = ImageLoader.orientedSize(source)
            if size.width > 0 {
                rows.append((L.t("Размеры", "Dimensions"), "\(Int(size.width)) × \(Int(size.height))"))
            }
            if let dpi = props[kCGImagePropertyDPIWidth] as? Double {
                rows.append((L.t("Разрешение", "Resolution"), "\(Int(dpi.rounded())) dpi"))
            }
            if let profile = props[kCGImagePropertyProfileName] as? String {
                rows.append((L.t("Цветовой профиль", "Color profile"), profile))
            }
            let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:]
            let tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any] ?? [:]
            if let taken = exif[kCGImagePropertyExifDateTimeOriginal] as? String {
                let parser = DateFormatter()
                parser.dateFormat = "yyyy:MM:dd HH:mm:ss"
                parser.locale = Locale(identifier: "en_US_POSIX")
                rows.append((L.t("Дата съёмки", "Date taken"), parser.date(from: taken).map(dates.string) ?? taken))
            }
            let camera = [tiff[kCGImagePropertyTIFFMake] as? String, tiff[kCGImagePropertyTIFFModel] as? String]
                .compactMap { $0?.trimmingCharacters(in: .whitespaces) }
            if !camera.isEmpty {
                var parts = camera
                if parts.count == 2, parts[1].lowercased().hasPrefix(parts[0].lowercased()) { parts.removeFirst() }
                rows.append((L.t("Камера", "Camera"), parts.joined(separator: " ")))
            }
            var shot: [String] = []
            if let f = exif[kCGImagePropertyExifFNumber] as? Double { shot.append(String(format: "f/%.1f", f)) }
            if let t = exif[kCGImagePropertyExifExposureTime] as? Double, t > 0 {
                shot.append(t < 1 ? "1/\(Int((1 / t).rounded())) \(L.t("с", "s"))" : String(format: "%.1f %@", t, L.t("с", "s")))
            }
            if let iso = (exif[kCGImagePropertyExifISOSpeedRatings] as? [Int])?.first { shot.append("ISO \(iso)") }
            if let focal = exif[kCGImagePropertyExifFocalLength] as? Double {
                shot.append(String(format: "%.0f %@", focal, L.t("мм", "mm")))
            }
            if !shot.isEmpty { rows.append((L.t("Съёмка", "Exposure"), shot.joined(separator: ", "))) }
        }
        if let created = attrs[.creationDate] as? Date {
            rows.append((L.t("Создан", "Created"), dates.string(from: created)))
        }
        if let modified = attrs[.modificationDate] as? Date {
            rows.append((L.t("Изменён", "Modified"), dates.string(from: modified)))
        }
        return rows
    }
}
