import CoreImage
import CoreImage.CIFilterBuiltins
import ImageIO
import Vision

/// Errors surfaced to the user as a short message on the item row.
enum CutoutError: LocalizedError {
    case unreadable, renderFailed, encodeFailed

    var errorDescription: String? {
        switch self {
        case .unreadable: "Unsupported or corrupted image"
        case .renderFailed: "Could not render cutout"
        case .encodeFailed: "Could not encode image"
        }
    }
}

/// Vision output kept per image so masks can be regenerated when the instance selection changes.
final class SubjectAnalysis {
    let observation: VNInstanceMaskObservation
    let handler: VNImageRequestHandler

    init(observation: VNInstanceMaskObservation, handler: VNImageRequestHandler) {
        self.observation = observation
        self.handler = handler
    }
}

/// Parameters for compositing a cutout.
struct RenderOptions {
    var background: CGColor?
    var feather: Double
    var trim: Bool
    var instances: IndexSet
}

/// Serializes all Vision / Core Image work off the main thread.
actor CutoutWorker {
    func load(_ url: URL) throws -> CGImage { try CutoutEngine.loadImage(at: url) }
    func analyze(_ image: CGImage) throws -> SubjectAnalysis? { try CutoutEngine.analyze(image) }
    func render(_ image: CGImage, _ analysis: SubjectAnalysis, _ options: RenderOptions) throws -> (CGImage, CGRect) {
        try CutoutEngine.render(original: image, analysis: analysis, options: options)
    }
}

/// Stateless image pipeline: ImageIO loading, Vision subject lifting, mask compositing and mask queries.
enum CutoutEngine {
    static let context = CIContext(options: [.cacheIntermediates: false])
    static let sRGB = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
    /// Larger inputs are downscaled before running the model; the mask is scaled back up.
    static let maxModelDimension: CGFloat = 2048

    /// Loads the full-resolution image with its EXIF orientation applied.
    static func loadImage(at url: URL) throws -> CGImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), CGImageSourceGetCount(source) > 0,
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = props[kCGImagePropertyPixelWidth] as? Int,
              let height = props[kCGImagePropertyPixelHeight] as? Int else { throw CutoutError.unreadable }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(width, height),
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw CutoutError.unreadable
        }
        return image
    }

    /// Runs foreground instance segmentation; returns nil when no subject is found.
    static func analyze(_ image: CGImage) throws -> SubjectAnalysis? {
        let input = downscaled(image)
        let handler = VNImageRequestHandler(cgImage: input, options: [:])
        let request = VNGenerateForegroundInstanceMaskRequest()
        try handler.perform([request])
        guard let observation = request.results?.first, !observation.allInstances.isEmpty else { return nil }
        return SubjectAnalysis(observation: observation, handler: handler)
    }

    /// Composites the original over the requested background through the (feathered) mask.
    /// Returns the image and its crop rect normalized to the original with a top-left origin.
    static func render(original: CGImage, analysis: SubjectAnalysis, options: RenderOptions) throws -> (CGImage, CGRect) {
        let source = CIImage(cgImage: original)
        let extent = source.extent
        let buffer = try analysis.observation.generateScaledMaskForImage(forInstances: options.instances,
                                                                         from: analysis.handler)
        var mask = CIImage(cvPixelBuffer: buffer)
        mask = mask.transformed(by: CGAffineTransform(scaleX: extent.width / mask.extent.width,
                                                      y: extent.height / mask.extent.height))
        if options.feather > 0 {
            mask = mask.clampedToExtent().applyingGaussianBlur(sigma: options.feather).cropped(to: extent)
        }

        let blend = CIFilter.blendWithMask()
        blend.inputImage = source
        blend.backgroundImage = options.background.map { CIImage(color: CIColor(cgColor: $0)).cropped(to: extent) }
            ?? CIImage.empty()
        blend.maskImage = mask
        guard var output = blend.outputImage?.cropped(to: extent) else { throw CutoutError.renderFailed }

        var crop = CGRect(x: 0, y: 0, width: 1, height: 1)
        if options.trim, let box = subjectBounds(in: analysis.observation.instanceMask, instances: options.instances) {
            let pad = CGFloat(options.feather) * 2
            let rect = CGRect(x: box.minX * extent.width, y: (1 - box.maxY) * extent.height,
                              width: box.width * extent.width, height: box.height * extent.height)
                .insetBy(dx: -pad, dy: -pad).integral.intersection(extent)
            if !rect.isEmpty {
                output = output.cropped(to: rect)
                crop = CGRect(x: rect.minX / extent.width, y: 1 - rect.maxY / extent.height,
                              width: rect.width / extent.width, height: rect.height / extent.height)
            }
        }
        guard let image = context.createCGImage(output, from: output.extent, format: .RGBA8, colorSpace: sRGB) else {
            throw CutoutError.renderFailed
        }
        return (image, crop)
    }

    /// Bounding box of the selected instances, normalized with a top-left origin.
    static func subjectBounds(in buffer: CVPixelBuffer, instances: IndexSet) -> CGRect? {
        var lookup = [Bool](repeating: false, count: 256)
        for index in instances where index < 256 { lookup[index] = true }
        var minX = Int.max, minY = Int.max, maxX = -1, maxY = -1
        let found: Bool = withMask(buffer) { pixels, width, height, rowBytes in
            for y in 0..<height {
                let row = pixels + y * rowBytes
                for x in 0..<width where lookup[Int(row[x])] {
                    minX = min(minX, x); maxX = max(maxX, x)
                    minY = min(minY, y); maxY = max(maxY, y)
                }
            }
            return maxX >= 0
        } ?? false
        guard found else { return nil }
        let w = CGFloat(CVPixelBufferGetWidth(buffer)), h = CGFloat(CVPixelBufferGetHeight(buffer))
        return CGRect(x: CGFloat(minX) / w, y: CGFloat(minY) / h,
                      width: CGFloat(maxX - minX + 1) / w, height: CGFloat(maxY - minY + 1) / h)
    }

    /// Instance label under a normalized (top-left origin) point, or nil for background.
    static func instance(at point: CGPoint, in buffer: CVPixelBuffer) -> Int? {
        withMask(buffer) { pixels, width, height, rowBytes in
            let x = min(max(Int(point.x * CGFloat(width)), 0), width - 1)
            let y = min(max(Int(point.y * CGFloat(height)), 0), height - 1)
            let label = Int(pixels[y * rowBytes + x])
            return label == 0 ? nil : label
        } ?? nil
    }

    private static func withMask<T>(_ buffer: CVPixelBuffer,
                                    _ body: (UnsafePointer<UInt8>, Int, Int, Int) -> T) -> T? {
        guard CVPixelBufferGetPixelFormatType(buffer) == kCVPixelFormatType_OneComponent8 else { return nil }
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }
        return body(base.assumingMemoryBound(to: UInt8.self), CVPixelBufferGetWidth(buffer),
                    CVPixelBufferGetHeight(buffer), CVPixelBufferGetBytesPerRow(buffer))
    }

    private static func downscaled(_ image: CGImage) -> CGImage {
        let scale = maxModelDimension / CGFloat(max(image.width, image.height))
        guard scale < 1 else { return image }
        let scaled = CIImage(cgImage: image).transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        return context.createCGImage(scaled, from: scaled.extent.integral, format: .RGBA8, colorSpace: sRGB) ?? image
    }
}
