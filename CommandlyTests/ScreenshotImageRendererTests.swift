import CoreGraphics
import Foundation
import ImageIO
import Infrastructure
import ScreenCaptureKit
import Testing
@testable import Commandly

struct ScreenshotImageRendererTests {
    @Test
    func generatedImageBecomesAReviewedPNGWithBoundedPreviewAndNoPrivateSourceMetadata() async throws {
        let image = try generatedImage(width: 1_600, height: 900)
        let result = try await ScreenshotImageRenderer().render(image, kind: .window)
        #expect(result.pixelWidth == 1_600 && result.pixelHeight == 900 && result.kind == .window)
        let source = try #require(CGImageSourceCreateWithData(result.pngData as CFData, nil))
        #expect(CGImageSourceGetCount(source) == 1)
        let properties = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any])
        #expect(properties[kCGImagePropertyGPSDictionary as String] == nil)
        #expect(properties[kCGImagePropertyTIFFDictionary as String] == nil)
        let preview = try #require(CGImageSourceCreateWithData(result.previewPNGData as CFData, nil))
        let previewImage = try #require(CGImageSourceCreateImageAtIndex(preview, 0, nil))
        #expect(previewImage.width == 1_280 && previewImage.height == 720)
    }

    @Test
    func rendererRejectsOversizedRasterAndAlreadyCancelledTask() async throws {
        let tooWide = try generatedImage(width: 8_193, height: 1)
        await #expect(throws: ScreenshotCaptureError.invalidImage) { try await ScreenshotImageRenderer().render(tooWide, kind: .display) }
        let small = try generatedImage(width: 20, height: 20)
        let task = Task { withUnsafeCurrentTask { $0?.cancel() }; return try await ScreenshotImageRenderer().render(small, kind: .region) }
        await #expect(throws: CancellationError.self) { try await task.value }
    }

    @Test
    func artifactBoundsRejectEmptyAndInconsistentDimensions() {
        let data = Data([1])
        for (width, height) in [(0, 1), (1, -1), (8_193, 1), (8_192, 8_192)] {
            #expect(throws: ScreenshotCaptureError.invalidImage) {
                try ScreenshotImage(pngData: data, previewPNGData: data, kind: .region, pixelWidth: width, pixelHeight: height)
            }
        }
        #expect(throws: ScreenshotCaptureError.invalidImage) {
            try ScreenshotImage(pngData: Data(), previewPNGData: data, kind: .window, pixelWidth: 1, pixelHeight: 1)
        }
    }

    @Test
    func nativeScreenshotConfigurationNeverWritesAFileOrRequestsHDR() throws {
        let configuration = try ScreenshotNativeConfiguration.make(points: CGSize(width: 1_440, height: 900), scale: 2, showsCursor: false)
        #expect(configuration.width == 2_880 && configuration.height == 1_800)
        #expect(configuration.fileURL == nil && configuration.dynamicRange == .sdr)
        #expect(configuration.ignoreShadows && configuration.includeChildWindows == false && configuration.showsCursor == false)
        #expect(ScreenshotNativeConfiguration.failure(NSError(domain: SCStreamErrorDomain, code: SCStreamError.Code.userDeclined.rawValue)) == .permissionRequired)
        #expect(ScreenshotNativeConfiguration.failure(NSError(domain: SCStreamErrorDomain, code: SCStreamError.Code.userStopped.rawValue)) == .cancelled)
        #expect(ScreenshotNativeConfiguration.failure(NSError(domain: "private-data-must-not-be-surfaced", code: 42)) == .captureFailed)
    }

    private func generatedImage(width: Int, height: Int) throws -> CGImage {
        let context = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0.2, green: 0.6, blue: 0.9, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return try #require(context.makeImage())
    }
}
