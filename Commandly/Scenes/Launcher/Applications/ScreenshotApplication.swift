import CommandKit
import Infrastructure
import SwiftUI

@MainActor
struct ScreenshotApplication: LauncherApplication {
    static let applicationID = CommandID(rawValue: "screen.capture")
    static let regionToolID = CommandID(rawValue: "screen.capture.region")
    static let windowToolID = CommandID(rawValue: "screen.capture.window")
    static let displayToolID = CommandID(rawValue: "screen.capture.display")
    static let manifest = CommandManifest(
        id: applicationID, title: "Screenshot", subtitle: "Select, review, and save a screenshot locally",
        systemImage: "camera.viewfinder", category: .productivity, mode: .view,
        keywords: ["screenshot", "screen capture", "capture region", "capture window", "snip", "snapshot"], badgeTitle: "Application",
        defaultActions: [CommandActionDescriptor(id: ScreenshotActionID.capture, title: "Choose and Capture", isPrimary: true, keyHint: .return)]
    )
    let definition = LauncherApplicationDefinition(manifest: Self.manifest, parentID: BuiltInLauncherApplicationGroup.catalogID,
        kind: .application, order: 44, documentation: RegisteredApplicationDocumentation.screenshot)
    private let services: ScreenshotApplicationServices
    init(services: ScreenshotApplicationServices) { self.services = services }
    var toolDefinitions: [LauncherApplicationDefinition] {
        [.tool(id: Self.regionToolID, parentID: Self.applicationID, title: "Choose Screenshot Region",
               subtitle: "Select an area, then review the screenshot", systemImage: "viewfinder", keywords: ["region", "area", "snip", "screenshot"]),
         .tool(id: Self.windowToolID, parentID: Self.applicationID, title: "Choose Screenshot Window",
               subtitle: "Use the macOS window picker for one screenshot", systemImage: "macwindow", order: 1, keywords: ["window screenshot", "capture window"]),
         .tool(id: Self.displayToolID, parentID: Self.applicationID, title: "Choose Screenshot Display",
               subtitle: "Use the macOS display picker for one screenshot", systemImage: "display", order: 2, keywords: ["display screenshot", "capture screen"])]
    }
    func launch(in context: LauncherApplicationContext) -> LauncherApplicationLaunch { makeLaunch(kind: .region, context: context) }
    func launch(toolID: CommandID, arguments: CommandArguments, in context: LauncherApplicationContext) -> LauncherApplicationLaunch {
        _ = arguments
        return switch toolID {
        case Self.regionToolID: makeLaunch(kind: .region, context: context)
        case Self.windowToolID: makeLaunch(kind: .window, context: context)
        case Self.displayToolID: makeLaunch(kind: .display, context: context)
        default: .message("Screenshot entry is unavailable.")
        }
    }
    private func makeLaunch(kind: ScreenshotKind, context: LauncherApplicationContext) -> LauncherApplicationLaunch {
        let model = ScreenshotViewModel(services: services, onGoBack: context.navigation.goBack)
        model.kind = kind
        return .present(LauncherApplicationSession(manifest: Self.manifest, model: model) { ScreenshotView(viewModel: $0) })
    }
}
