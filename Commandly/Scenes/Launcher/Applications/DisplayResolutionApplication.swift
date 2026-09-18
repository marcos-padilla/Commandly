import CommandKit

@MainActor
struct DisplayResolutionApplication: LauncherApplication {
    static let id = CommandID(rawValue: "system.display-resolution")
    static let manifest = CommandManifest(id: id, title: "Display Resolution",
        subtitle: "Preview a resolution with automatic revert", systemImage: "display", category: .system,
        mode: .action, keywords: ["display", "resolution", "screen", "hidpi", "retina", "refresh rate", "monitor"])
    let definition = LauncherApplicationDefinition(manifest: Self.manifest, kind: .application,
        documentation: RegisteredApplicationDocumentation.displayResolution)
    private let services: DisplayResolutionApplicationServices
    init(services: DisplayResolutionApplicationServices) { self.services = services }
    func launch(in context: LauncherApplicationContext) -> LauncherApplicationLaunch {
        context.navigation.dismissLauncher()
        services.coordinator.show()
        return .message("Display resolution chooser opened.")
    }
}
