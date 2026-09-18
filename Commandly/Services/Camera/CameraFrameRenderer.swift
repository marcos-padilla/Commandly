import CoreGraphics
import Foundation
import Infrastructure

/// Converts native camera frames to an immutable, bounded representation for MainActor display.
nonisolated enum CameraFrameRenderer {
    static let bitmapInfo = CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.noneSkipFirst.rawValue

    static func frame(from image: CGImage) throws -> CameraPreviewFrame {
        guard (1...960).contains(image.width), (1...960).contains(image.height),
              let context = CGContext(
                data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: bitmapInfo
              ) else { throw CameraCaptureError.invalidFrame }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard let bytes = context.data else { throw CameraCaptureError.invalidFrame }
        return try CameraPreviewFrame(data: Data(bytes: bytes, count: image.width * image.height * 4),
                                      pixelWidth: image.width, pixelHeight: image.height)
    }

    static func image(from frame: CameraPreviewFrame) -> CGImage? {
        guard let provider = CGDataProvider(data: frame.data as CFData) else { return nil }
        return CGImage(width: frame.pixelWidth, height: frame.pixelHeight, bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: frame.bytesPerRow, space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: bitmapInfo), provider: provider, decode: nil,
                       shouldInterpolate: true, intent: .defaultIntent)
    }
}
