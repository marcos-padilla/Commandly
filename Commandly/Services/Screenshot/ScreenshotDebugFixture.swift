#if DEBUG
import CoreGraphics
import CoreText
import Foundation
import Infrastructure
import SecurityKit

/// Explicit test dependencies; no screen metadata, pixels, TCC, native picker, or real clipboard.
@MainActor
enum ScreenshotDebugFixture {
    static var services: ScreenshotApplicationServices {
        ScreenshotApplicationServices(permissions: InMemoryPermissionService(states: [.screenRecording: .authorized]),
            makeCapture: { GeneratedScreenshotCapture() }, copier: GeneratedScreenshotCopier(), privacySettings: InMemoryPrivacySettingsOpener())
    }
}

@MainActor
private final class GeneratedScreenshotCapture: ScreenshotCapturing {
    private let pixels = GeneratedScreenshotPixels()
    private let renderer = ScreenshotImageRenderer()
    private var generation = 0
    func capture(_ request: ScreenshotRequest) async throws -> ScreenshotImage {
        let id = generation
        let image = try await pixels.makeImage()
        let result = try await renderer.render(image, kind: request.kind)
        try Task.checkCancellation()
        guard id == generation else { throw CancellationError() }
        return result
    }
    func cancel() { generation += 1 }
}
nonisolated private struct GeneratedScreenshotCopier: ScreenshotCopying {
    func copyPNG(_ data: Data) async throws { try Task.checkCancellation(); guard data.isEmpty == false else { throw ScreenshotCaptureError.copyFailed } }
}
private actor GeneratedScreenshotPixels {
    func makeImage() throws -> CGImage {
        try Task.checkCancellation()
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: 800, height: 450, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { throw ScreenshotCaptureError.invalidImage }
        context.setFillColor(CGColor(red: 0.06, green: 0.09, blue: 0.17, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 800, height: 450))
        context.setFillColor(CGColor(red: 0.33, green: 0.65, blue: 0.96, alpha: 1))
        context.fill(CGRect(x: 60, y: 72, width: 220, height: 200))
        context.setFillColor(CGColor(red: 0.97, green: 0.64, blue: 0.31, alpha: 1))
        context.fillEllipse(in: CGRect(x: 530, y: 72, width: 200, height: 200))
        let text = NSAttributedString(string: "GENERATED SCREENSHOT", attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName("Helvetica-Bold" as CFString, 34, nil),
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 1, alpha: 1)
        ])
        context.textPosition = CGPoint(x: 158, y: 350)
        CTLineDraw(CTLineCreateWithAttributedString(text), context)
        guard let image = context.makeImage() else { throw ScreenshotCaptureError.invalidImage }
        return image
    }
}
#endif
