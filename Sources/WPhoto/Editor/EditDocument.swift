import AppKit
import CoreImage

/// Рисунок, который правят: полное разрешение, шаги отмены и повтора, все операции.
/// Координаты — пиксели рисунка, начало в левом нижнем углу (как в CGContext и Core Image).
final class EditDocument {
    let source: URL
    private(set) var image: CGImage
    private var undoStack: [CGImage] = []
    private var redoStack: [CGImage] = []
    /// Сколько шагов от последнего сохранения; 0 — правок нет.
    private var changesSinceSave = 0
    var onChange: (() -> Void)?

    static let ciContext = CIContext(options: [.cacheIntermediates: false])

    init?(url: URL, quarterTurns: Int) {
        guard let decoded = ImageLoader.decode(url, fit: nil) else { return nil }
        source = url
        image = Self.normalized(decoded.cgImage.rotated(quarterTurns: quarterTurns))
        changesSinceSave = quarterTurns % 4 == 0 ? 0 : 1
    }

    var size: CGSize { CGSize(width: image.width, height: image.height) }
    var bounds: CGRect { CGRect(origin: .zero, size: size) }
    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }
    var isDirty: Bool { changesSinceSave != 0 }
    var colorSpace: CGColorSpace { image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)! }

    func markSaved() { changesSinceSave = 0 }

    // MARK: - Шаги

    private func commit(_ new: CGImage) {
        undoStack.append(image)
        redoStack.removeAll()
        // Не больше ~1 ГБ на шаги отмены.
        var bytes = undoStack.reduce(0) { $0 + $1.bytesPerRow * $1.height }
        while undoStack.count > 1, bytes > 1_000_000_000 {
            bytes -= undoStack[0].bytesPerRow * undoStack[0].height
            undoStack.removeFirst()
        }
        image = new
        changesSinceSave += 1
        onChange?()
    }

    func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(image)
        image = previous
        changesSinceSave -= 1
        onChange?()
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(image)
        image = next
        changesSinceSave += 1
        onChange?()
    }

    // MARK: - Холст

    /// RGBA 8 бит в цветовом пространстве рисунка — на таком можно рисовать.
    static func normalized(_ image: CGImage) -> CGImage {
        let space = image.colorSpace.flatMap { $0.model == .rgb ? $0 : nil } ?? CGColorSpace(name: CGColorSpace.sRGB)!
        guard let ctx = makeContext(width: image.width, height: image.height, space: space)
                ?? makeContext(width: image.width, height: image.height, space: CGColorSpace(name: CGColorSpace.sRGB)!) else { return image }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return ctx.makeImage() ?? image
    }

    private static func makeContext(width: Int, height: Int, space: CGColorSpace) -> CGContext? {
        CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                  space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    }

    private func redraw(width: Int, height: Int, _ body: (CGContext) -> Void) -> CGImage? {
        guard let ctx = Self.makeContext(width: width, height: height, space: colorSpace) else { return nil }
        ctx.interpolationQuality = .high
        body(ctx)
        return ctx.makeImage()
    }

    private func render(_ ci: CIImage, extent: CGRect? = nil) -> CGImage? {
        Self.ciContext.createCGImage(ci, from: extent ?? bounds, format: .RGBA8, colorSpace: colorSpace)
    }

    // MARK: - Операции

    func crop(_ rect: CGRect) {
        let r = rect.integral.intersection(bounds)
        guard r.width >= 1, r.height >= 1 else { return }
        // CGImage.cropping считает от верхнего края.
        let flipped = CGRect(x: r.minX, y: CGFloat(image.height) - r.maxY, width: r.width, height: r.height)
        guard let cropped = image.cropping(to: flipped) else { return }
        commit(Self.normalized(cropped))
    }

    func resize(to newSize: CGSize) {
        let w = max(1, Int(newSize.width.rounded())), h = max(1, Int(newSize.height.rounded()))
        guard w != image.width || h != image.height else { return }
        let ci = CIImage(cgImage: image)
        let sy = CGFloat(h) / CGFloat(image.height)
        let sx = CGFloat(w) / CGFloat(image.width)
        let scaled = ci.applyingFilter("CILanczosScaleTransform", parameters: [
            kCIInputScaleKey: sy, kCIInputAspectRatioKey: sx / sy,
        ])
        if let out = render(scaled.clampedToExtent(), extent: CGRect(x: 0, y: 0, width: w, height: h)) {
            commit(out)
        }
    }

    func rotate(clockwise: Bool) {
        commit(image.rotated(quarterTurns: clockwise ? 1 : -1))
    }

    func flip(horizontal: Bool) {
        let w = image.width, h = image.height
        if let out = redraw(width: w, height: h, { ctx in
            if horizontal {
                ctx.translateBy(x: CGFloat(w), y: 0)
                ctx.scaleBy(x: -1, y: 1)
            } else {
                ctx.translateBy(x: 0, y: CGFloat(h))
                ctx.scaleBy(x: 1, y: -1)
            }
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        }) {
            commit(out)
        }
    }

    func draw(_ annotation: Annotation) {
        if let out = redraw(width: image.width, height: image.height, { ctx in
            ctx.draw(image, in: bounds)
            annotation.draw(in: ctx)
        }) {
            commit(out)
        }
    }

    /// Размыть или «замостить» область — скрыть лицо, номер, текст.
    func obscure(_ rect: CGRect, pixelate: Bool) {
        let r = rect.integral.intersection(bounds)
        guard r.width >= 2, r.height >= 2 else { return }
        let ci = CIImage(cgImage: image)
        let long = max(size.width, size.height)
        let effect: CIImage
        if pixelate {
            let scale = max(6, max(long / 80, min(r.width, r.height) / 8))
            effect = ci.applyingFilter("CIPixellate", parameters: [
                kCIInputScaleKey: scale, kCIInputCenterKey: CIVector(x: r.minX, y: r.minY),
            ])
        } else {
            let radius = max(6, max(long / 120, min(r.width, r.height) / 10))
            effect = ci.clampedToExtent().applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: radius])
        }
        if let out = render(effect.cropped(to: r).composited(over: ci)) {
            commit(out)
        }
    }

    func apply(_ adjustments: Adjustments) {
        guard !adjustments.isIdentity, let out = render(adjustments.apply(to: CIImage(cgImage: image))) else { return }
        commit(out)
    }

    func apply(_ filter: QuickFilter) {
        if let out = render(filter.apply(to: CIImage(cgImage: image))) {
            commit(out)
        }
    }

    /// Уменьшенная копия для живого просмотра коррекции.
    func preview(maxPixels: CGFloat) -> CIImage {
        let ci = CIImage(cgImage: image)
        let scale = min(1, maxPixels / max(size.width, size.height))
        guard scale < 1 else { return ci }
        return ci.applyingFilter("CILanczosScaleTransform", parameters: [kCIInputScaleKey: scale])
    }

    func renderPreview(_ ci: CIImage) -> CGImage? {
        Self.ciContext.createCGImage(ci, from: ci.extent.integral, format: .RGBA8, colorSpace: colorSpace)
    }
}

// MARK: - Коррекция цвета

/// Ползунки коррекции; значения −100…100 (резкость 0…100), 0 — без изменений.
struct Adjustments: Equatable {
    var brightness: Double = 0
    var contrast: Double = 0
    var saturation: Double = 0
    var hue: Double = 0          // градусы, −180…180
    var exposure: Double = 0
    var warmth: Double = 0
    var vibrance: Double = 0
    var sharpness: Double = 0

    var isIdentity: Bool { self == Adjustments() }

    func apply(to input: CIImage) -> CIImage {
        var img = input
        if exposure != 0 {
            img = img.applyingFilter("CIExposureAdjust", parameters: [kCIInputEVKey: exposure / 50])
        }
        if brightness != 0 || contrast != 0 || saturation != 0 {
            img = img.applyingFilter("CIColorControls", parameters: [
                kCIInputBrightnessKey: brightness * 0.003,
                kCIInputContrastKey: 1 + contrast * 0.006,
                kCIInputSaturationKey: 1 + saturation / 100,
            ])
        }
        if hue != 0 {
            img = img.applyingFilter("CIHueAdjust", parameters: [kCIInputAngleKey: hue * .pi / 180])
        }
        if vibrance != 0 {
            img = img.applyingFilter("CIVibrance", parameters: ["inputAmount": vibrance / 100])
        }
        if warmth != 0 {
            // Цель «нейтрального» ниже 6500 K — теплее, выше — холоднее.
            img = img.applyingFilter("CITemperatureAndTint", parameters: [
                "inputNeutral": CIVector(x: 6500, y: 0),
                "inputTargetNeutral": CIVector(x: 6500 - warmth * 30, y: 0),
            ])
        }
        if sharpness > 0 {
            img = img.applyingFilter("CISharpenLuminance", parameters: [kCIInputSharpnessKey: sharpness / 50])
        }
        return img.cropped(to: input.extent)
    }
}

/// Фильтры в одно нажатие.
enum QuickFilter: String, CaseIterable {
    case autoEnhance, grayscale, sepia, invert, sharpen, vignette

    var title: String {
        switch self {
        case .autoEnhance: return L.t("Автоулучшение", "Auto Enhance")
        case .grayscale: return L.t("Чёрно-белое", "Black & White")
        case .sepia: return L.t("Сепия", "Sepia")
        case .invert: return L.t("Негатив", "Invert Colors")
        case .sharpen: return L.t("Повысить резкость", "Sharpen")
        case .vignette: return L.t("Виньетка", "Vignette")
        }
    }

    func apply(to input: CIImage) -> CIImage {
        switch self {
        case .autoEnhance:
            return input.autoAdjustmentFilters(options: [.redEye: false]).reduce(input) { image, filter in
                filter.setValue(image, forKey: kCIInputImageKey)
                return filter.outputImage ?? image
            }.cropped(to: input.extent)
        case .grayscale:
            return input.applyingFilter("CIPhotoEffectMono")
        case .sepia:
            return input.applyingFilter("CISepiaTone", parameters: [kCIInputIntensityKey: 0.85])
        case .invert:
            return input.applyingFilter("CIColorInvert")
        case .sharpen:
            return input.applyingFilter("CISharpenLuminance", parameters: [kCIInputSharpnessKey: 0.8]).cropped(to: input.extent)
        case .vignette:
            let radius = max(input.extent.width, input.extent.height) * 0.75
            return input.applyingFilter("CIVignetteEffect", parameters: [
                kCIInputCenterKey: CIVector(x: input.extent.midX, y: input.extent.midY),
                kCIInputRadiusKey: radius, kCIInputIntensityKey: 0.8, "inputFalloff": 0.6,
            ]).cropped(to: input.extent)
        }
    }
}
