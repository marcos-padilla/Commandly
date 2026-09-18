import CommandKit
import Infrastructure

@MainActor
struct ScreenRecordingApplication: LauncherApplication {
    static let id = CommandID(rawValue: "screen.recording")
    static let windowToolID = CommandID(rawValue: "screen.recording.window")
    static let displayToolID = CommandID(rawValue: "screen.recording.display")
    static let stopToolID = CommandID(rawValue: "screen.recording.stop")
    static let manifest = CommandManifest(id: id, title: "Screen Recording",
        subtitle: "Record a chosen window or display, then review and save the video",
        systemImage: "record.circle", category: .productivity, mode: .view,
        keywords: ["screen recording", "record", "video", "screencast", "window", "display", "capture"], badgeTitle: "Application")
    let definition = LauncherApplicationDefinition(manifest: Self.manifest,
        parentID: BuiltInLauncherApplicationGroup.catalogID, kind: .application, order: 78,
        documentation: RegisteredApplicationDocumentation.screenRecording)
    let presenter: (any ScreenRecordingPresenting)?
    init(presenter: (any ScreenRecordingPresenting)? = nil) { self.presenter = presenter }

    var toolDefinitions: [LauncherApplicationDefinition] {
        [
            .tool(id: Self.windowToolID, parentID: Self.id, title: "Record a Window",
                  subtitle: "Choose recording settings, then share one window", systemImage: "macwindow",
                  keywords: ["record", "screen recording", "window", "video"]),
            .tool(id: Self.displayToolID, parentID: Self.id, title: "Record a Display",
                  subtitle: "Choose recording settings, then share one display", systemImage: "display",
                  keywords: ["record", "screen recording", "display", "screen", "video"]),
            .tool(id: Self.stopToolID, parentID: Self.id, title: "Stop Screen Recording",
                  subtitle: "Show recording controls and stop into video review", systemImage: "stop.circle",
                  keywords: ["record", "recording", "stop", "finish", "video"])
        ]
    }

    func launch(in context: LauncherApplicationContext) -> LauncherApplicationLaunch { open(source: nil, context: context) }

    func launch(toolID: CommandID, arguments: CommandArguments, in context: LauncherApplicationContext) -> LauncherApplicationLaunch {
        switch toolID {
        case Self.windowToolID: return open(source: .window, context: context)
        case Self.displayToolID: return open(source: .display, context: context)
        case Self.stopToolID:
            guard let presenter, presenter.hasActiveOrUnsavedRecording else { return .message("There is no recording to stop.") }
            context.navigation.dismissLauncher()
            presenter.stop()
            return .message("Recording controls opened.")
        default: return .message("That recording tool is unavailable.")
        }
    }

    private func open(source: ScreenRecordingSource?, context: LauncherApplicationContext) -> LauncherApplicationLaunch {
        guard let presenter else { return .message("Screen Recording is unavailable in this session.") }
        context.navigation.dismissLauncher()
        presenter.present(source: source)
        return .message("Screen Recording opened.")
    }
}
