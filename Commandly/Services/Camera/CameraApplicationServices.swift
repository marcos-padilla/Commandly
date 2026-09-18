import AppKit
import Foundation
import Infrastructure
import SecurityKit

/// Creating these dependencies does not check permissions, discover devices, or create inputs.
@MainActor
struct CameraApplicationServices {
    let permissions: any PermissionServicing
    let makeCapture: @MainActor () -> any CameraCapturing
    let photoCopier: any CameraPhotoCopying
    let privacySettingsOpener: any PrivacySettingsOpening

    init(permissions: any PermissionServicing, makeCapture: @escaping @MainActor () -> any CameraCapturing,
         photoCopier: any CameraPhotoCopying, privacySettingsOpener: any PrivacySettingsOpening) {
        self.permissions = permissions
        self.makeCapture = makeCapture
        self.photoCopier = photoCopier
        self.privacySettingsOpener = privacySettingsOpener
    }

    static func live(permissions: any PermissionServicing, privacySettingsOpener: any PrivacySettingsOpening) -> Self {
        Self(permissions: permissions, makeCapture: { NativeCameraCaptureService() },
             photoCopier: NativeCameraPhotoCopier(), privacySettingsOpener: privacySettingsOpener)
    }

    static var inMemory: Self {
        Self(permissions: InMemoryPermissionService(), makeCapture: { UnavailableCameraCaptureService() },
             photoCopier: UnavailableCameraPhotoCopier(), privacySettingsOpener: InMemoryPrivacySettingsOpener())
    }
}

/// Accesses the pasteboard only inside an explicit Copy Photo action; it never reads contents.
@MainActor
private struct NativeCameraPhotoCopier: CameraPhotoCopying {
    func copyPNG(_ data: Data) async throws {
        try Task.checkCancellation()
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        guard pasteboard.setData(data, forType: .png) else { throw CameraCaptureError.copyFailed }
    }
}

private actor UnavailableCameraCaptureService: CameraCapturing {
    func start(deviceID: String?) throws -> CameraCaptureSession { throw CameraCaptureError.noCamera }
    func takePhoto(mirrored: Bool) throws -> CameraPhoto { throw CameraCaptureError.captureUnavailable }
    func stop() {}
}

nonisolated private struct UnavailableCameraPhotoCopier: CameraPhotoCopying {
    func copyPNG(_ data: Data) async throws { throw CameraCaptureError.copyFailed }
}
