import AppKit
import ImageIO

/// Раскодированный рисунок. `cgImage` уже повёрнут по EXIF и, как правило, уменьшен до экрана.
final class DecodedImage {
    let cgImage: CGImage
    /// Размер оригинала в пикселях с учётом поворота из EXIF.
    let fullSize: CGSize
    /// Раскодирован в полном разрешении — при увеличении заменять нечем.
    let isFull: Bool
    /// Встроенная миниатюра: показывается на миг, пока раскодируется сам рисунок.
    let isPreview: Bool
    /// Дата изменения файла: после поворота с записью в файл старые картинки не годятся.
    let stamp: Date

    init(cgImage: CGImage, fullSize: CGSize, isFull: Bool, isPreview: Bool, stamp: Date) {
        self.cgImage = cgImage
        self.fullSize = fullSize
        self.isFull = isFull
        self.isPreview = isPreview
        self.stamp = stamp
    }

    var cost: Int { cgImage.bytesPerRow * cgImage.height }
}

/// Быстрота — главное: рисунки декодируются в фоне под размер экрана, соседние — заранее,
/// готовые лежат в кэше. Полное разрешение — только когда его просит увеличение.
final class ImageLoader {
    static let shared = ImageLoader()

    private let cache = NSCache<NSString, DecodedImage>()
    private let currentQueue = DispatchQueue(label: "wphoto.decode.current", qos: .userInitiated)
    private let fullQueue = DispatchQueue(label: "wphoto.decode.full", qos: .userInitiated)
    private let prefetchQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 2
        queue.qualityOfService = .utility
        return queue
    }()
    private let lock = NSLock()
    private var latestCurrent = ""
    private var latestFull = ""

    private init() {
        cache.totalCostLimit = 1_200_000_000
    }

    // MARK: - Кэш

    private func key(_ url: URL, _ stamp: Date, _ fit: CGSize?) -> NSString {
        let size = fit.map { "\(Int($0.width))x\(Int($0.height))" } ?? "full"
        return "\(url.path)|\(stamp.timeIntervalSinceReferenceDate)|\(size)" as NSString
    }

    func cached(_ url: URL, fit: CGSize) -> DecodedImage? {
        guard let stamp = Self.stamp(url) else { return nil }
        return cache.object(forKey: key(url, stamp, nil)) ?? cache.object(forKey: key(url, stamp, fit))
    }

    func cachedFull(_ url: URL) -> DecodedImage? {
        guard let stamp = Self.stamp(url) else { return nil }
        return cache.object(forKey: key(url, stamp, nil))
    }

    private func store(_ image: DecodedImage, url: URL, fit: CGSize?) {
        cache.setObject(image, forKey: key(url, image.stamp, image.isFull ? nil : fit), cost: image.cost)
    }

    // MARK: - Загрузка

    /// Текущий рисунок. Если пользователь успел перелистнуть дальше, устаревшие запросы
    /// пропускаются, и их `completion` не вызывается.
    func load(_ url: URL, fit: CGSize, completion: @escaping (DecodedImage?) -> Void) {
        if let image = cached(url, fit: fit) {
            completion(image)
            return
        }
        let tag = "\(url.path)|\(fit)"
        lock.withLock { latestCurrent = tag }
        currentQueue.async { [weak self] in
            guard let self, self.lock.withLock({ self.latestCurrent == tag }) else { return }
            if let image = self.cached(url, fit: fit) {
                DispatchQueue.main.async { completion(image) }
                return
            }
            let image = Self.decode(url, fit: fit)
            if let image { self.store(image, url: url, fit: fit) }
            DispatchQueue.main.async { completion(image) }
        }
    }

    func loadFull(_ url: URL, completion: @escaping (DecodedImage?) -> Void) {
        if let image = cachedFull(url) {
            completion(image)
            return
        }
        let tag = url.path
        lock.withLock { latestFull = tag }
        fullQueue.async { [weak self] in
            guard let self, self.lock.withLock({ self.latestFull == tag }) else { return }
            let image = Self.decode(url, fit: nil)
            if let image { self.store(image, url: url, fit: nil) }
            DispatchQueue.main.async { completion(image) }
        }
    }

    /// Соседние рисунки — заранее, чтобы стрелка показывала следующий мгновенно.
    func prefetch(_ urls: [URL], fit: CGSize) {
        prefetchQueue.cancelAllOperations()
        for url in urls {
            prefetchQueue.addOperation { [weak self] in
                guard let self, self.cached(url, fit: fit) == nil,
                      let image = Self.decode(url, fit: fit) else { return }
                self.store(image, url: url, fit: fit)
            }
        }
    }

    // MARK: - Декодирование

    static func stamp(_ url: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }

    /// Размер оригинала с учётом EXIF-поворота.
    static func orientedSize(_ source: CGImageSource) -> CGSize {
        guard let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else { return .zero }
        let width = props[kCGImagePropertyPixelWidth] as? Int ?? 0
        let height = props[kCGImagePropertyPixelHeight] as? Int ?? 0
        let orientation = props[kCGImagePropertyOrientation] as? UInt32 ?? 1
        return (5...8).contains(orientation)
            ? CGSize(width: height, height: width)
            : CGSize(width: width, height: height)
    }

    /// `fit` — область в пикселях, в которую рисунок вписывается (экран); nil — полное разрешение.
    static func decode(_ url: URL, fit: CGSize?) -> DecodedImage? {
        guard let stamp = stamp(url),
              let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetCount(source) > 0 else { return nil }
        let full = orientedSize(source)
        let cap: CGFloat = 16384
        var limit = cap
        var isFull = true
        if full.width > 0, full.height > 0 {
            let longest = max(full.width, full.height)
            var target = min(longest, cap)
            if let fit {
                let scale = min(1, min(fit.width / full.width, fit.height / full.height))
                target = min(target, ceil(longest * scale))
            }
            isFull = target >= min(longest, cap)
            limit = target
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: Int(limit),
        ]
        var image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        if image == nil {
            image = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
        }
        guard let cgImage = image else { return nil }
        let size = full.width > 0 ? full : CGSize(width: cgImage.width, height: cgImage.height)
        return DecodedImage(cgImage: cgImage, fullSize: size, isFull: isFull, isPreview: false, stamp: stamp)
    }

    /// Встроенная в файл миниатюра (JPEG, HEIC, RAW) — достаётся за миллисекунды.
    /// Миниатюры с полями (другие пропорции) не годятся.
    static func quickPreview(_ url: URL) -> DecodedImage? {
        guard let stamp = stamp(url),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let full = orientedSize(source)
        guard full.width > 0, full.height > 0 else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceCreateThumbnailFromImageIfAbsent: false,
            kCGImageSourceThumbnailMaxPixelSize: 1024,
        ]
        guard let thumb = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let aspect = CGFloat(thumb.width) / CGFloat(thumb.height)
        guard abs(aspect - full.width / full.height) < 0.03 else { return nil }
        return DecodedImage(cgImage: thumb, fullSize: full, isFull: false, isPreview: true, stamp: stamp)
    }
}

extension CGImage {
    /// Копия, повёрнутая на `turns` четвертей оборота по часовой стрелке.
    func rotated(quarterTurns turns: Int) -> CGImage {
        let t = ((turns % 4) + 4) % 4
        guard t != 0 else { return self }
        let w = t % 2 == 0 ? width : height
        let h = t % 2 == 0 ? height : width
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return self }
        ctx.translateBy(x: CGFloat(w) / 2, y: CGFloat(h) / 2)
        ctx.rotate(by: -CGFloat(t) * .pi / 2)
        ctx.draw(self, in: CGRect(x: -CGFloat(width) / 2, y: -CGFloat(height) / 2, width: CGFloat(width), height: CGFloat(height)))
        return ctx.makeImage() ?? self
    }
}
