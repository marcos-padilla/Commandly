import CommandKit
import Infrastructure
import SwiftUI

@MainActor
struct MicrophoneControlApplication:
    LauncherApplication,
    LauncherApplicationToolBackgroundInvoking
{
    static let id = CommandID(rawValue: "microphone.control")
    static let toggleToolID = CommandID(rawValue: "microphone.control.toggle")

    private static let manifest = CommandManifest(
        id: id,
        title: "Microphone Control",
        subtitle: "See and change the default microphone’s system mute",
        systemImage: "mic.circle",
        category: .system,
        mode: .view,
        keywords: ["microphone", "mic", "mute", "unmute", "audio", "input", "privacy", "on", "off"],
        badgeTitle: "Application",
        defaultActions: [
            CommandActionDescriptor(
                id: MicrophoneControlActionID.toggle,
                title: "Toggle Microphone",
                isPrimary: true,
                keyHint: .return
            ),
            CommandActionDescriptor(
                id: BuiltInCommandActionID.openActions,
                title: "Actions",
                keyHint: .commandK
            )
        ]
    )

    let definition = LauncherApplicationDefinition(
        manifest: Self.manifest,
        parentID: BuiltInLauncherApplicationGroup.catalogID,
        kind: .application,
        order: 50,
        documentation: RegisteredApplicationDocumentation.microphoneControl
    )

    private let service: any MicrophoneControlling

    init(service: any MicrophoneControlling) {
        self.service = service
    }

    var toolDefinitions: [LauncherApplicationDefinition] {
        [
            LauncherApplicationDefinition.tool(
                id: CommandID(rawValue: "\(Self.id.rawValue).tool.open"),
                parentID: Self.id,
                title: "Open Microphone Control",
                subtitle: "Review the default input device and mute state",
                systemImage: "mic.circle",
                category: .system,
                keywords: ["microphone", "mic", "audio input", "mute status"]
            ),
            LauncherApplicationDefinition.tool(
                id: Self.toggleToolID,
                parentID: Self.id,
                title: "Toggle Microphone",
                subtitle: "Mute or unmute the default input device",
                systemImage: "mic.slash",
                category: .system,
                order: 1,
                keywords: ["microphone", "mic", "mute", "unmute", "toggle", "on", "off"]
            )
        ]
    }

    var backgroundToolIDs: Set<CommandID> { [Self.toggleToolID] }

    func launch(in context: LauncherApplicationContext) -> LauncherApplicationLaunch {
        let model = MicrophoneControlViewModel(
            service: service,
            onGoBack: context.navigation.goBack
        )
        return .present(
            LauncherApplicationSession(manifest: Self.manifest, model: model) {
                MicrophoneControlView(viewModel: $0)
            }
        )
    }

    func invokeToolInBackground(
        toolID: CommandID,
        arguments: CommandArguments,
        settings: LauncherApplicationResolvedSettings
    ) async -> CommandResult {
        _ = arguments
        _ = settings
        guard toolID == Self.toggleToolID else {
            return .failure(message: "Microphone tool is unavailable.")
        }
        do {
            let state = try await service.state()
            guard let isMuted = state.isMuted, state.canChangeMute else {
                return .failure(message: "The default microphone has no writable mute control.")
            }
            let updated = try await service.setMuted(isMuted == false)
            let nowMuted = updated.isMuted ?? (isMuted == false)
            return .success(
                message: nowMuted ? "Microphone muted." : "Microphone unmuted."
            )
        } catch {
            return .failure(message: "Microphone mute couldn’t be changed.")
        }
    }
}

extension MicrophoneControlViewModel: LauncherApplicationModel {}
