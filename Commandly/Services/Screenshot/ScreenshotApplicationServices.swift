import AppKit
import Foundation
import Infrastructure
import SecurityKit

@MainActor
struct ScreenshotApplicationServices {
    let permissions: any PermissionServicing
    let makeCapture: @MainActor () -> any ScreenshotCapturing
    let copier: any ScreenshotCopying
    let privacySettings: any PrivacySettingsOpening
    let annotator: any ScreenshotAnnotating

    init(permissions: any PermissionServicing, makeCapture: @escaping @MainActor () -> any ScreenshotCapturing,
         copier: any ScreenshotCopying, privacySettings: any PrivacySettingsOpening,
         annotator: any ScreenshotAnnotating = UnavailableScreenshotAnnotator()) {
        self.permissions = permissions; self.makeCapture = makeCapture; self.copier = copier
        self.privacySettings = privacySettings; self.annotator = annotator
    }

    static func live(permissions: any PermissionServicing, privacySettings: any PrivacySettingsOpening) -> Self {
        Self(permissions: permissions, makeCapture: { NativeScreenshotCaptureService() },
             copier: NativeScreenshotCopier(), privacySettings: privacySettings, annotator: CleanShotAnnotationService())
    }
    static var inMemory: Self {
        Self(permissions: InMemoryPermissionService(), makeCapture: { UnavailableScreenshotCapture() },
             copier: UnavailableScreenshotCopier(), privacySettings: InMemoryPrivacySettingsOpener())
    }
}

@MainActor
private struct NativeScreenshotCopier: ScreenshotCopying {
    func copyPNG(_ data: Data) async throws {
        try Task.checkCancellation()
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        guard pasteboard.setData(data, forType: .png) else { throw ScreenshotCaptureError.copyFailed }
    }
}

@MainActor
private final class UnavailableScreenshotCapture: ScreenshotCapturing {
    func capture(_ request: ScreenshotRequest) async throws -> ScreenshotImage { throw ScreenshotCaptureError.selectionUnavailable }
    func cancel() {}
}
nonisolated private struct UnavailableScreenshotCopier: ScreenshotCopying {
    func copyPNG(_ data: Data) async throws { throw ScreenshotCaptureError.copyFailed }
}
