import AIKit
import CoreGraphics
import Dispatch
import Foundation
import ImageIO
import Infrastructure
import UniformTypeIdentifiers

nonisolated protocol VisualAIImagePreparing: Sendable {
    func prepare(_ image: ScreenshotImage) async throws -> AIImageInput
}
/// Creates the exact provider-bound JPEG before review, on an actor executor away from the main actor.
actor VisualAIImagePreparer: VisualAIImagePreparing {
    private let queue = DispatchSerialQueue(label: "com.commandly.visual-ai.image", qos: .userInitiated)
    nonisolated var unownedExecutor: UnownedSerialExecutor { queue.asUnownedSerialExecutor() }
    func prepare(_ image: ScreenshotImage) throws -> AIImageInput {
        try Task.checkCancellation()
        guard let source = CGImageSourceCreateWithData(image.pngData as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetCount(source) == 1,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int, let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width == image.pixelWidth, height == image.pixelHeight,
              let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 2_048,
                kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceShouldCacheImmediately: true] as CFDictionary),
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: thumbnail.width, height: thumbnail.height, bitsPerComponent: 8,
                bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { throw ScreenshotCaptureError.invalidImage }
        context.setFillColor(CGColor(gray: 1, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: thumbnail.width, height: thumbnail.height))
        context.draw(thumbnail, in: CGRect(x: 0, y: 0, width: thumbnail.width, height: thumbnail.height))
        guard let pixels = context.makeImage() else { throw ScreenshotCaptureError.invalidImage }
        for quality in [0.85, 0.65, 0.45, 0.3] {
            try Task.checkCancellation()
            let data = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else { throw ScreenshotCaptureError.invalidImage }
            CGImageDestinationAddImage(destination, pixels, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
            guard CGImageDestinationFinalize(destination) else { throw ScreenshotCaptureError.invalidImage }
            if data.length <= 2 * 1_024 * 1_024 { return try AIImageInput(jpegData: data as Data, pixelWidth: pixels.width, pixelHeight: pixels.height) }
        }
        throw ScreenshotCaptureError.invalidImage
    }
}
