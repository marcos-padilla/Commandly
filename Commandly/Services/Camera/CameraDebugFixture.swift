#if DEBUG
import CoreGraphics
import CoreText
import Foundation
import ImageIO
import Infrastructure
import SecurityKit
import UniformTypeIdentifiers

/// Explicit debug-only dependencies for UI acceptance. No camera, TCC, network, or system clipboard.
@MainActor
enum CameraDebugFixture {
    static var services: CameraApplicationServices {
        CameraApplicationServices(
            permissions: InMemoryPermissionService(states: [.camera: .authorized]),
            makeCapture: { GeneratedCameraCapture() }, photoCopier: GeneratedCameraPhotoCopier(),
            privacySettingsOpener: InMemoryPrivacySettingsOpener()
        )
    }
}

private actor GeneratedCameraCapture: CameraCapturing {
    private var events: AsyncStream<CameraCaptureEvent>.Continuation?
    private var sourcePNG: Data?
    private var sessionID: UUID?
    private let device = CameraDevice(id: "generated-camera-fixture", name: "Generated Camera Fixture")

    func start(deviceID: String?) throws -> CameraCaptureSession {
        try Task.checkCancellation()
        stop()
        guard deviceID == nil || deviceID == device.id else { throw CameraCaptureError.deviceUnavailable }
        // This isolated method creates all pixels on the actor's background executor after Start.
        let image = try GeneratedCameraPixels.image()
        let frame = try CameraFrameRenderer.frame(from: image)
        let data = try GeneratedCameraPixels.png(image)
        try Task.checkCancellation()
        let stream = AsyncStream<CameraCaptureEvent>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let identifier = UUID()
        sessionID = identifier
        stream.continuation.onTermination = { [weak self] _ in
            Task { await self?.stop(ifCurrent: identifier) }
        }
        events = stream.continuation
        sourcePNG = data
        events?.yield(.frame(frame))
        return CameraCaptureSession(devices: [device], selectedDeviceID: device.id, events: stream.stream)
    }

    func takePhoto(mirrored: Bool) throws -> CameraPhoto {
        try Task.checkCancellation()
        guard let sourcePNG, events != nil else { throw CameraCaptureError.captureUnavailable }
        let photo = try CameraPhotoRenderer.render(sourcePNG, mirrored: mirrored)
        try Task.checkCancellation()
        return photo
    }

    func stop() {
        sessionID = nil
        sourcePNG = nil
        events?.yield(.stopped)
        events?.finish()
        events = nil
    }

    private func stop(ifCurrent identifier: UUID) {
        guard sessionID == identifier else { return }
        stop()
    }
}

/// Copy success can be checked in UI without changing the user's clipboard during acceptance.
nonisolated private struct GeneratedCameraPhotoCopier: CameraPhotoCopying {
    func copyPNG(_ data: Data) async throws {
        try Task.checkCancellation()
        guard data.isEmpty == false else { throw CameraCaptureError.copyFailed }
    }
}

nonisolated private enum GeneratedCameraPixels {
    static func image() throws -> CGImage {
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil, width: 640, height: 360, bitsPerComponent: 8, bytesPerRow: 0,
                space: colorSpace, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
              ) else { throw CameraCaptureError.encodingFailed }
        context.setFillColor(CGColor(red: 0.08, green: 0.10, blue: 0.18, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 640, height: 360))
        context.setFillColor(CGColor(red: 0.93, green: 0.40, blue: 0.24, alpha: 1))
        context.fill(CGRect(x: 42, y: 80, width: 170, height: 170))
        context.setFillColor(CGColor(red: 0.28, green: 0.76, blue: 0.88, alpha: 1))
        context.fillEllipse(in: CGRect(x: 420, y: 80, width: 170, height: 170))
        text("GENERATED CAMERA FIXTURE", size: 26, at: CGPoint(x: 105, y: 292), in: context)
        text("LEFT", size: 22, at: CGPoint(x: 94, y: 48), in: context)
        text("RIGHT", size: 22, at: CGPoint(x: 463, y: 48), in: context)
        guard let image = context.makeImage() else { throw CameraCaptureError.encodingFailed }
        return image
    }

    static func png(_ image: CGImage) throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
            throw CameraCaptureError.encodingFailed
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw CameraCaptureError.encodingFailed }
        return data as Data
    }

    private static func text(_ value: String, size: CGFloat, at point: CGPoint, in context: CGContext) {
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName("Helvetica-Bold" as CFString, size, nil),
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 1, alpha: 1)
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: value, attributes: attributes))
        context.textPosition = point
        CTLineDraw(line, context)
    }
}
#endif
