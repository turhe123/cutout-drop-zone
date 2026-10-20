import Foundation
import CoreGraphics
import ImageIO

/// Encodes images with CGImageDestination and picks collision-free output file names.
enum ImageWriter {
    static func encode(_ image: CGImage, as format: ExportFormat) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data as CFMutableData,
                                                                 format.utType.identifier as CFString, 1, nil) else { return nil }
        let properties: [CFString: Any] = format == .jpeg ? [kCGImageDestinationLossyCompressionQuality: 0.92] : [:]
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }

    /// Writes without ever replacing an existing file.
    static func write(_ image: CGImage, as format: ExportFormat, to url: URL) throws {
        guard let data = encode(image, as: format) else { throw CutoutError.encodeFailed }
        try data.write(to: url, options: .withoutOverwriting)
    }

    /// `name.ext`, or `name 2.ext`, `name 3.ext`… if taken.
    static func uniqueURL(in folder: URL, baseName: String, ext: String) -> URL {
        var candidate = folder.appendingPathComponent(baseName).appendingPathExtension(ext)
        var counter = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = folder.appendingPathComponent("\(baseName) \(counter)").appendingPathExtension(ext)
            counter += 1
        }
        return candidate
    }

    /// Flattens a transparent image onto an opaque color (used for JPEG output).
    static func flatten(_ image: CGImage, on color: CGColor) -> CGImage? {
        let rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        guard let ctx = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: CutoutEngine.sRGB,
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        ctx.setFillColor(color)
        ctx.fill(rect)
        ctx.draw(image, in: rect)
        return ctx.makeImage()
    }
}
