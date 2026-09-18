#if DEBUG
import Infrastructure
import SecurityKit
import Testing
@testable import Commandly

@MainActor
struct CameraDebugFixtureTests {
    @Test
    func generatedSessionProvidesPreviewMirroredPhotosAndAnExplicitStop() async throws {
        let services = CameraDebugFixture.services
        #expect(await services.permissions.state(for: .camera) == .authorized)
        let capture = services.makeCapture()
        let session = try await capture.start(deviceID: nil)
        var iterator = session.events.makeAsyncIterator()
        let event = try #require(await iterator.next())
        guard case .frame(let frame) = event else { Issue.record("Expected the generated preview frame"); return }
        #expect(frame.pixelWidth == 640 && frame.pixelHeight == 360)
        #expect(session.devices.count == 1 && session.devices.first?.name == "Generated Camera Fixture")
        let normal = try await capture.takePhoto(mirrored: false)
        let mirrored = try await capture.takePhoto(mirrored: true)
        #expect(normal.pixelWidth == 640 && normal.pixelHeight == 360)
        #expect(mirrored.pixelWidth == 640 && mirrored.pixelHeight == 360)
        #expect(normal.pngData != mirrored.pngData)
        try await services.photoCopier.copyPNG(normal.pngData)
        await capture.stop()
        #expect(await iterator.next() == .stopped)
        #expect(await iterator.next() == nil)
        await #expect(throws: CameraCaptureError.captureUnavailable) { try await capture.takePhoto(mirrored: false) }
    }
}
#endif
