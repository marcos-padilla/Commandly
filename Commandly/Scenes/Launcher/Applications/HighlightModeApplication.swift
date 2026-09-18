import CommandKit
import Infrastructure
import SwiftUI

@MainActor
struct HighlightModeApplication:
    LauncherApplication,
    LauncherApplicationBackgroundInvoking,
    LauncherApplicationToolBackgroundInvoking
{
    static let applicationID = CommandID(rawValue: "highlight.mode")
    static let toggleToolID = CommandID(rawValue: "highlight.mode.toggle")

    static let manifest = CommandManifest(
        id: applicationID,
        title: "Highlight Mode",
        subtitle: "Visualize clicks, typing, shortcuts, and cursor position",
        systemImage: "cursorarrow.rays",
        category: .productivity,
        mode: .view,
        keywords: [
            "present", "presentation", "tutorial", "recording", "click", "keystroke",
            "shortcut", "cursor", "spotlight", "mouse",
        ],
        badgeTitle: "Application",
        defaultActions: [
            CommandActionDescriptor(
                id: HighlightModeActionID.toggle,
                title: "Toggle Highlight Mode",
                isPrimary: true,
                keyHint: .return
            ),
            CommandActionDescriptor(
                id: BuiltInCommandActionID.openActions,
                title: "Actions",
                keyHint: .commandK
            ),
        ]
    )

    let definition = LauncherApplicationDefinition(
        manifest: Self.manifest,
        parentID: BuiltInLauncherApplicationGroup.catalogID,
        kind: .application,
        order: 55,
        configurationFields: [
            LauncherConfigurationField(
                id: "mouse-clicks",
                variable: "showMouseClicks",
                title: "Mouse click highlights",
                description: "Animate a colored ring at every mouse click.",
                kind: .toggle,
                defaultValue: .boolean(true)
            ),
            LauncherConfigurationField(
                id: "keyboard-shortcuts",
                variable: "showKeyboardShortcuts",
                title: "Keyboard shortcuts",
                description: "Show pressed modifier combinations such as ⌘⇧P.",
                kind: .toggle,
                defaultValue: .boolean(true)
            ),
            LauncherConfigurationField(
                id: "typed-text",
                variable: "showTypedText",
                title: "Typed text",
                description: "Show an ephemeral rolling preview of typing. Text is never saved.",
                kind: .toggle,
                defaultValue: .boolean(true)
            ),
            LauncherConfigurationField(
                id: "cursor-spotlight",
                variable: "showCursorSpotlight",
                title: "Cursor spotlight",
                description: "Dim the screen around the pointer for quick orientation.",
                kind: .toggle,
                defaultValue: .boolean(true)
            ),
            LauncherConfigurationField(
                id: "spotlight-size",
                variable: "spotlightSize",
                title: "Spotlight size",
                kind: .selection,
                defaultValue: .text(HighlightModeSpotlightSize.medium.rawValue),
                options: [
                    LauncherConfigurationOption(id: "compact", title: "Compact"),
                    LauncherConfigurationOption(id: "medium", title: "Medium"),
                    LauncherConfigurationOption(id: "large", title: "Large"),
                ]
            ),
            LauncherConfigurationField(
                id: "accent-color",
                variable: "accentColor",
                title: "Highlight color",
                kind: .selection,
                defaultValue: .text(HighlightModeAccent.blue.rawValue),
                options: [
                    LauncherConfigurationOption(id: "blue", title: "Blue"),
                    LauncherConfigurationOption(id: "green", title: "Green"),
                    LauncherConfigurationOption(id: "orange", title: "Orange"),
                    LauncherConfigurationOption(id: "pink", title: "Pink"),
                ]
            ),
            LauncherConfigurationField(
                id: "display-duration",
                variable: "displayDuration",
                title: "Feedback duration",
                kind: .selection,
                defaultValue: .text(HighlightModeDisplayDuration.standard.rawValue),
                options: [
                    LauncherConfigurationOption(id: "short", title: "Short"),
                    LauncherConfigurationOption(id: "standard", title: "Standard"),
                    LauncherConfigurationOption(id: "long", title: "Long"),
                ]
            ),
        ],
        documentation: RegisteredApplicationDocumentation.highlightMode
    )

    private let service: any HighlightModeControlling

    init(service: any HighlightModeControlling) {
        self.service = service
    }

    var toolDefinitions: [LauncherApplicationDefinition] {
        [
            LauncherApplicationDefinition.tool(
                id: CommandID(rawValue: "\(Self.applicationID.rawValue).tool.open"),
                parentID: Self.applicationID,
                title: "Configure Highlight Mode",
                subtitle: "Choose click, typing, shortcut, and spotlight feedback",
                systemImage: "cursorarrow.rays",
                keywords: ["highlight", "configure", "presentation", "cursor", "click"]
            ),
            LauncherApplicationDefinition.tool(
                id: Self.toggleToolID,
                parentID: Self.applicationID,
                title: "Toggle Highlight Mode",
                subtitle: "Turn presentation feedback on or off",
                systemImage: "cursorarrow.motionlines",
                order: 1,
                keywords: ["highlight", "toggle", "present", "recording", "cursor", "spotlight"]
            )
        ]
    }

    var backgroundToolIDs: Set<CommandID> { [Self.toggleToolID] }

    func launch(in context: LauncherApplicationContext) -> LauncherApplicationLaunch {
        let model = HighlightModeViewModel(
            service: service,
            configuration: Self.configuration(from: context.settings),
            onOpenPermissions: context.navigation.openPermissionsSettings,
            onGoBack: context.navigation.goBack
        )
        return .present(
            LauncherApplicationSession(manifest: Self.manifest, model: model) {
                HighlightModeView(viewModel: $0)
            }
        )
    }

    func invokeInBackground(
        settings: LauncherApplicationResolvedSettings
    ) async -> CommandResult {
        let shouldEnable = service.state.isEnabled == false
        do {
            let state = try await service.setEnabled(
                shouldEnable,
                configuration: Self.configuration(from: settings)
            )
            return .success(message: state.isEnabled ? "Highlight Mode on." : "Highlight Mode off.")
        } catch HighlightModeError.accessibilityDenied {
            return .failure(message: "Highlight Mode needs Accessibility access.")
        } catch {
            return .failure(message: "Highlight Mode couldn’t start input monitoring.")
        }
    }

    func invokeToolInBackground(
        toolID: CommandID,
        arguments: CommandArguments,
        settings: LauncherApplicationResolvedSettings
    ) async -> CommandResult {
        _ = arguments
        guard toolID == Self.toggleToolID else {
            return .failure(message: "Highlight Mode tool is unavailable.")
        }
        return await invokeInBackground(settings: settings)
    }

    static func configuration(
        from settings: LauncherApplicationResolvedSettings
    ) -> HighlightModeConfiguration {
        HighlightModeConfiguration(
            showsMouseClicks: settings.value(for: "showMouseClicks")?.booleanValue ?? true,
            showsKeyboardShortcuts:
                settings.value(for: "showKeyboardShortcuts")?.booleanValue ?? true,
            showsTypedText: settings.value(for: "showTypedText")?.booleanValue ?? true,
            showsCursorSpotlight:
                settings.value(for: "showCursorSpotlight")?.booleanValue ?? true,
            spotlightSize: HighlightModeSpotlightSize(
                rawValue: settings.value(for: "spotlightSize")?.textValue ?? ""
            ) ?? .medium,
            accent: HighlightModeAccent(
                rawValue: settings.value(for: "accentColor")?.textValue ?? ""
            ) ?? .blue,
            displayDuration: HighlightModeDisplayDuration(
                rawValue: settings.value(for: "displayDuration")?.textValue ?? ""
            ) ?? .standard
        )
    }
}

extension HighlightModeViewModel: LauncherApplicationModel {}
