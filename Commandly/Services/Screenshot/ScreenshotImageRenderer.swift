import CoreGraphics
import Foundation
import ImageIO
import Infrastructure
import UniformTypeIdentifiers

/// Fresh sRGB screenshot encoding; all expensive pixel work runs on this actor.
actor ScreenshotImageRenderer {
    func render(_ input: CGImage, kind: ScreenshotKind) throws -> ScreenshotImage {
        try Task.checkCancellation()
        guard (1...8_192).contains(input.width), (1...8_192).contains(input.height),
              input.width * input.height <= 40_000_000 else { throw ScreenshotCaptureError.invalidImage }
        let image = try raster(input, width: input.width, height: input.height)
        let data = try encode(image, limit: 160 * 1_024 * 1_024)
        try Task.checkCancellation()
        let scale = min(1, 1_280 / Double(max(image.width, image.height)))
        let preview = try raster(image, width: max(1, Int((Double(image.width) * scale).rounded())),
                                height: max(1, Int((Double(image.height) * scale).rounded())))
        let previewData = try encode(preview, limit: 8 * 1_024 * 1_024)
        try Task.checkCancellation()
        return try ScreenshotImage(pngData: data, previewPNGData: previewData, kind: kind,
                                   pixelWidth: image.width, pixelHeight: image.height)
    }

    private func raster(_ image: CGImage, width: Int, height: Int) throws -> CGImage {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw ScreenshotCaptureError.invalidImage
        }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let rendered = context.makeImage() else { throw ScreenshotCaptureError.invalidImage }
        return rendered
    }

    private func encode(_ image: CGImage, limit: Int) throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
            throw ScreenshotCaptureError.invalidImage
        }
        // Newly rendered pixels only: no source metadata, titles, display IDs, or coordinates.
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination), data.length <= limit else { throw ScreenshotCaptureError.invalidImage }
        return data as Data
    }
}
