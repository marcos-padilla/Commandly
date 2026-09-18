import CoreGraphics
import Foundation
import ImageIO
import Infrastructure

/// Shared ImageIO validation. Only actor-backed Image Tools services call these synchronous helpers.
nonisolated enum ImageToolsImageDecoder {
    static let maximumInputBytes = 64 * 1_024 * 1_024
    static let maximumPixels = 40_000_000

    static func validatedSource(_ data: Data) throws -> CGImageSource {
        guard data.count <= maximumInputBytes else { throw ImageConversionError.inputTooLarge }
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary) else {
            throw ImageConversionError.invalidImage
        }
        let imageCount = CGImageSourceGetCount(source)
        guard imageCount > 0 else { throw ImageConversionError.invalidImage }
        guard imageCount == 1 else { throw ImageConversionError.animatedImageUnsupported }
        _ = try dimensions(source)
        return source
    }

    static func dimensions(_ source: CGImageSource) throws -> (width: Int, height: Int) {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0 else { throw ImageConversionError.invalidImage }
        guard width <= 16_384, height <= 16_384, width <= maximumPixels / height else {
            throw ImageConversionError.inputTooLarge
        }
        let orientation = properties[kCGImagePropertyOrientation] as? Int ?? 1
        return (5...8).contains(orientation) ? (height, width) : (width, height)
    }

    static func thumbnail(_ source: CGImageSource, longestEdge: Int) throws -> CGImage {
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: longestEdge,
            kCGImageSourceShouldCacheImmediately: true
        ] as CFDictionary) else { throw ImageConversionError.invalidImage }
        return image
    }
}
