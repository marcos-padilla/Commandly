import CommandKit
import SecurityKit

/// Opens the independent Window Switcher panel without coupling launcher routing to its windowing.
@MainActor
protocol WindowSwitcherPresenting: AnyObject {
    func present(configuration: WindowSwitcherConfiguration)
}

@MainActor
struct WindowSwitcherApplicationServices {
    let presenter: any WindowSwitcherPresenting

    static var inMemory: WindowSwitcherApplicationServices {
        WindowSwitcherApplicationServices(presenter: InMemoryWindowSwitcherPresenter())
    }
}

@MainActor
final class InMemoryWindowSwitcherPresenter: WindowSwitcherPresenting {
    private(set) var presentedConfigurations: [WindowSwitcherConfiguration] = []

    func present(configuration: WindowSwitcherConfiguration) {
        presentedConfigurations.append(configuration)
    }
}

@MainActor
struct WindowSwitcherApplication: LauncherApplication, LauncherApplicationBackgroundInvoking {
    static let applicationID = CommandID(rawValue: "windows.switcher")
    static let showActionID = CommandActionID(rawValue: "windows.switcher.show")

    static let manifest = CommandManifest(
        id: applicationID,
        title: "Window Switcher",
        subtitle: "Find, preview, and focus open macOS windows",
        systemImage: "rectangle.stack",
        category: .productivity,
        mode: .action,
        keywords: [
            "window",
            "switch",
            "application",
            "preview",
            "desktop",
            "display",
            "command tab",
            "dock",
        ],
        availabilityRequirements: [
            .permission(identifier: PermissionKind.accessibility.rawValue),
        ],
        badgeTitle: "Application",
        defaultActions: [
            CommandActionDescriptor(
                id: showActionID,
                title: "Show Window Switcher",
                isPrimary: true,
                keyHint: .return
            ),
        ]
    )

    let definition = LauncherApplicationDefinition(
        manifest: Self.manifest,
        parentID: BuiltInLauncherApplicationGroup.catalogID,
        kind: .application,
        order: 75,
        configurationFields: WindowSwitcherConfiguration.schema,
        documentation: RegisteredApplicationDocumentation.windowSwitcher
    )

    private let services: WindowSwitcherApplicationServices

    init(services: WindowSwitcherApplicationServices) {
        self.services = services
    }

    func launch(in context: LauncherApplicationContext) -> LauncherApplicationLaunch {
        services.presenter.present(
            configuration: Self.overlayConfiguration(from: context.settings)
        )
        return .dismiss
    }

    func invokeInBackground(
        settings: LauncherApplicationResolvedSettings
    ) async -> CommandResult {
        services.presenter.present(configuration: Self.overlayConfiguration(from: settings))
        return .success(message: "Window Switcher toggled.")
    }

    private static func overlayConfiguration(
        from settings: LauncherApplicationResolvedSettings
    ) -> WindowSwitcherConfiguration {
        var configuration = WindowSwitcherConfiguration(settings: settings)
        configuration.shortcutMode = .toggleOverlay
        return configuration
    }
}
