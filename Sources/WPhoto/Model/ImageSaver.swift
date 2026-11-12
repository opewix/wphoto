import Foundation
import ImageIO

/// Поворот с записью в файл, как в Windows: меняется только метка ориентации EXIF,
/// пиксели не пережимаются — без потери качества. Пишем во временный файл, проверяем его
/// и только потом подменяем оригинал. Не вышло — поворот остаётся только на экране.
enum ImageSaver {
    private static let queue = DispatchQueue(label: "wphoto.save", qos: .userInitiated)

    static func rotate(_ url: URL, quarterTurns turns: Int, completion: @escaping (Bool) -> Void) {
        queue.async {
            let ok = apply(url, turns: turns)
            DispatchQueue.main.async { completion(ok) }
        }
    }

    private static func apply(_ url: URL, turns: Int) -> Bool {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let type = CGImageSourceGetType(source),
              CGImageSourceGetCount(source) == 1,
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else { return false }
        let current = props[kCGImagePropertyOrientation] as? UInt32 ?? 1
        let target = Orientation.rotate(current, quarterTurns: turns)
        let fm = FileManager.default
        guard let tempDir = try? fm.url(for: .itemReplacementDirectory, in: .userDomainMask,
                                        appropriateFor: url, create: true) else { return false }
        defer { try? fm.removeItem(at: tempDir) }
        let temp = tempDir.appendingPathComponent(url.lastPathComponent)
        guard let destination = CGImageDestinationCreateWithURL(temp as CFURL, type, 1, nil) else { return false }
        let options: [CFString: Any] = [
            kCGImageDestinationOrientation: NSNumber(value: target),
            kCGImageDestinationMergeMetadata: true,
        ]
        guard CGImageDestinationCopyImageSource(destination, source, options as CFDictionary, nil) else { return false }
        // Проверка: тот же формат и размер, новая ориентация.
        guard let check = CGImageSourceCreateWithURL(temp as CFURL, nil),
              CGImageSourceGetType(check) as String? == type as String,
              let checkProps = CGImageSourceCopyPropertiesAtIndex(check, 0, nil) as? [CFString: Any],
              checkProps[kCGImagePropertyPixelWidth] as? Int == props[kCGImagePropertyPixelWidth] as? Int,
              checkProps[kCGImagePropertyPixelHeight] as? Int == props[kCGImagePropertyPixelHeight] as? Int,
              (checkProps[kCGImagePropertyOrientation] as? UInt32 ?? 1) == target else { return false }
        do {
            _ = try fm.replaceItemAt(url, withItemAt: temp)
            return true
        } catch {
            return false
        }
    }
}

/// Ориентация EXIF как «отразить по горизонтали (или нет), затем повернуть по часовой».
enum Orientation {
    private static let table: [UInt32: (turns: Int, mirrored: Bool)] = [
        1: (0, false), 2: (0, true), 3: (2, false), 4: (2, true),
        5: (3, true), 6: (1, false), 7: (1, true), 8: (3, false),
    ]

    static func rotate(_ orientation: UInt32, quarterTurns: Int) -> UInt32 {
        let (turns, mirrored) = table[orientation] ?? (0, false)
        let newTurns = ((turns + quarterTurns) % 4 + 4) % 4
        return table.first { $0.value.turns == newTurns && $0.value.mirrored == mirrored }?.key ?? 1
    }
}
