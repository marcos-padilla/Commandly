import CommandKit
import Infrastructure
import SwiftUI

/// Video-only preview and a still-photo review flow, with an explicit Start Camera gate.
@MainActor
struct CameraApplication: LauncherApplication {
    static let applicationID = CommandID(rawValue: "camera.preview")
    static let openToolID = CommandID(rawValue: "camera.preview.open")
    static let selfieToolID = CommandID(rawValue: "camera.preview.selfie")
    static let manifest = CommandManifest(
        id: applicationID, title: "Camera", subtitle: "Check your camera preview and take a photo",
        systemImage: "camera", category: .productivity, mode: .view,
        keywords: ["camera", "webcam", "mirror", "preview", "selfie", "take photo"], badgeTitle: "Application",
        defaultActions: [CommandActionDescriptor(id: CameraActionID.start, title: "Start Camera", isPrimary: true, keyHint: .return)]
    )
    let definition = LauncherApplicationDefinition(
        manifest: Self.manifest, parentID: BuiltInLauncherApplicationGroup.catalogID,
        kind: .application, order: 43, documentation: RegisteredApplicationDocumentation.camera
    )
    private let services: CameraApplicationServices
    init(services: CameraApplicationServices) { self.services = services }

    var toolDefinitions: [LauncherApplicationDefinition] {
        [
            .tool(id: Self.openToolID, parentID: Self.applicationID, title: "Open Camera Preview",
                  subtitle: "Start a local video preview when you’re ready", systemImage: "video",
                  keywords: ["camera", "webcam", "mirror", "video preview"]),
            .tool(id: Self.selfieToolID, parentID: Self.applicationID, title: "Take a Selfie",
                  subtitle: "Preview, capture, then review a photo before saving", systemImage: "camera", order: 1,
                  keywords: ["selfie", "photo", "portrait", "camera"])
        ]
    }

    func launch(in context: LauncherApplicationContext) -> LauncherApplicationLaunch { makeLaunch(context) }
    func launch(toolID: CommandID, arguments: CommandArguments, in context: LauncherApplicationContext) -> LauncherApplicationLaunch {
        _ = arguments
        guard toolID == Self.openToolID || toolID == Self.selfieToolID else { return .message("Camera entry is unavailable.") }
        return makeLaunch(context)
    }
    private func makeLaunch(_ context: LauncherApplicationContext) -> LauncherApplicationLaunch {
        let model = CameraViewModel(
            permissions: services.permissions, makeCapture: services.makeCapture, photoCopier: services.photoCopier,
            privacySettingsOpener: services.privacySettingsOpener, onGoBack: context.navigation.goBack
        )
        return .present(LauncherApplicationSession(manifest: Self.manifest, model: model) { CameraView(viewModel: $0) })
    }
}
