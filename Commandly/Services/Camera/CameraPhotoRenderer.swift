import CoreGraphics
import Foundation
import ImageIO
import Infrastructure
import UniformTypeIdentifiers

/// Synchronous pixel processing for the camera service's background executor. No device or file I/O.
nonisolated enum CameraPhotoRenderer {
    static func render(_ encodedData: Data, mirrored: Bool) throws -> CameraPhoto {
        try Task.checkCancellation()
        let source = try ImageToolsImageDecoder.validatedSource(encodedData)
        let dimensions = try ImageToolsImageDecoder.dimensions(source)
        let sourceEdge = max(dimensions.width, dimensions.height)
        let input = try ImageToolsImageDecoder.thumbnail(source, longestEdge: min(4_096, sourceEdge))
        try Task.checkCancellation()
        let output = try raster(input, width: input.width, height: input.height, mirrored: mirrored)
        let pngData = try encode(output)
        try Task.checkCancellation()
        let previewScale = min(1, 960 / Double(max(output.width, output.height)))
        let preview = try raster(
            output,
            width: max(1, Int((Double(output.width) * previewScale).rounded())),
            height: max(1, Int((Double(output.height) * previewScale).rounded())),
            mirrored: false
        )
        let previewPNGData = try encode(preview)
        try Task.checkCancellation()
        return CameraPhoto(
            pngData: pngData,
            previewPNGData: previewPNGData,
            pixelWidth: output.width,
            pixelHeight: output.height
        )
    }

    private static func raster(
        _ image: CGImage, width: Int, height: Int, mirrored: Bool
    ) throws -> CGImage {
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                  space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else { throw CameraCaptureError.encodingFailed }
        if mirrored {
            context.translateBy(x: CGFloat(width), y: 0)
            context.scaleBy(x: -1, y: 1)
        }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let output = context.makeImage() else { throw CameraCaptureError.encodingFailed }
        return output
    }

    private static func encode(_ image: CGImage) throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data, UTType.png.identifier as CFString, 1, nil
        ) else { throw CameraCaptureError.encodingFailed }
        // Encode only freshly rendered sRGB pixels. Source EXIF, GPS, comments, orientation, and
        // embedded thumbnails are never copied to either exported bytes or the preview.
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination), data.length <= 80 * 1_024 * 1_024 else {
            throw CameraCaptureError.encodingFailed
        }
        return data as Data
    }
}
