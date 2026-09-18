import CommandKit
import SwiftUI

enum PortManagerApplicationID {
    nonisolated static let command = CommandID(rawValue: "system.port-manager")
    nonisolated static let inspectTool = CommandID(rawValue: "system.port-manager.inspect")
    nonisolated static let killPortTool = CommandID(rawValue: "system.port-manager.kill-port")
    nonisolated static let portArgument = "port"
}

@MainActor
struct PortManagerApplication: LauncherApplication {
    private static let manifest = CommandManifest(
        id: PortManagerApplicationID.command,
        title: "Port Manager",
        subtitle: "Inspect local listeners and stop an occupied port",
        systemImage: "point.3.connected.trianglepath.dotted",
        category: .system,
        mode: .view,
        keywords: ["port", "ports", "localhost", "listener", "server", "tcp", "udp", "kill port"],
        badgeTitle: "Application",
        defaultActions: [
            CommandActionDescriptor(id: PortManagerActionID.refresh, title: "Refresh", isPrimary: true, keyHint: .return),
            CommandActionDescriptor(id: BuiltInCommandActionID.openActions, title: "Actions", keyHint: .commandK)
        ]
    )

    let definition = LauncherApplicationDefinition(
        manifest: Self.manifest,
        parentID: BuiltInLauncherApplicationGroup.catalogID,
        kind: .application,
        order: 46,
        documentation: RegisteredApplicationDocumentation.portManager
    )

    private let service: any PortManaging

    init(service: any PortManaging = NativePortManager()) {
        self.service = service
    }

    var toolDefinitions: [LauncherApplicationDefinition] {
        [
            LauncherApplicationDefinition.tool(
                id: PortManagerApplicationID.inspectTool,
                parentID: PortManagerApplicationID.command,
                title: "Inspect Ports",
                subtitle: "Review local TCP and UDP listeners",
                systemImage: "point.3.connected.trianglepath.dotted",
                category: .system,
                keywords: ["port", "ports", "listener", "localhost", "tcp", "udp", "inspect"]
            ),
            LauncherApplicationDefinition.tool(
                id: PortManagerApplicationID.killPortTool,
                parentID: PortManagerApplicationID.command,
                title: "Kill Port",
                subtitle: "Find a listener by port and review stopping its process",
                systemImage: "xmark.circle",
                category: .system,
                order: 1,
                keywords: ["kill port", "stop port", "free port", "listener", "server"],
                arguments: [
                    CommandArgument(
                        name: PortManagerApplicationID.portArgument,
                        description: "The local port number to inspect before confirmation.",
                        isRequired: false,
                        valueType: .integer
                    )
                ]
            )
        ]
    }

    var commandDefinitions: [LauncherApplicationCommandDefinition] {
        [
            LauncherApplicationCommandDefinition(
                id: "port-manager.kill-port",
                title: "Kill Port",
                syntax: "kill port <number>",
                examples: ["kill port 3000", "stop port 8080"],
                toolID: PortManagerApplicationID.killPortTool,
                parser: Self.parseKillPortCommand
            )
        ]
    }

    func launch(in context: LauncherApplicationContext) -> LauncherApplicationLaunch {
        makeLaunch(initialPort: nil, context: context)
    }

    func launch(
        toolID: CommandID,
        arguments: CommandArguments,
        in context: LauncherApplicationContext
    ) -> LauncherApplicationLaunch {
        switch toolID {
        case PortManagerApplicationID.inspectTool:
            return makeLaunch(initialPort: nil, context: context)
        case PortManagerApplicationID.killPortTool:
            guard let value = arguments[PortManagerApplicationID.portArgument] else {
                return makeLaunch(initialPort: nil, context: context)
            }
            guard case .integer(let portValue) = value,
                  let port = UInt16(exactly: portValue),
                  port > 0 else {
                return .message("Port numbers must be between 1 and 65535.")
            }
            return makeLaunch(initialPort: port, context: context)
        default:
            return .message("Port Manager tool is unavailable.")
        }
    }

    private func makeLaunch(
        initialPort: UInt16?,
        context: LauncherApplicationContext
    ) -> LauncherApplicationLaunch {
        let model = PortManagerViewModel(
            service: service,
            initialPort: initialPort,
            onGoBack: context.navigation.goBack
        )
        return .present(LauncherApplicationSession(manifest: Self.manifest, model: model) {
            PortManagerView(viewModel: $0)
        })
    }

    nonisolated private static func parseKillPortCommand(
        _ query: String
    ) -> LauncherApplicationCommandMatch? {
        let parts = query
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
        guard parts.count == 3,
              ["kill", "stop"].contains(parts[0].lowercased()),
              parts[1].caseInsensitiveCompare("port") == .orderedSame,
              let value = Int(parts[2]),
              let port = UInt16(exactly: value),
              port > 0 else {
            return nil
        }
        return LauncherApplicationCommandMatch(
            id: "port-manager.kill-port.\(port)",
            title: "Kill Port \(port)",
            subtitle: "Port Manager · review and confirm",
            systemImage: "xmark.circle",
            reference: CommandReference(
                commandID: PortManagerApplicationID.killPortTool,
                arguments: CommandArguments([
                    PortManagerApplicationID.portArgument: .integer(Int(port))
                ])
            )
        )
    }
}

extension PortManagerViewModel: LauncherApplicationModel {}
