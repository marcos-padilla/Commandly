import CommandKit
import Foundation
import Testing
@testable import Commandly

@MainActor struct WindowLayoutCommandTests {
    @Test func registersPresetsAndRefreshesCustomCommandsWithoutLosingSiblings() throws {
        let services = WindowLayoutsApplicationServices(layoutService: InMemoryWindowLayoutService(), customStore: InMemoryCustomWindowLayoutStore())
        let registry = LauncherApplicationRegistry.makeBuiltIn(windowLayoutsServices: services)
        #expect(services.commandCatalog.presets.count == 58)
        for preset in services.commandCatalog.presets {
            #expect(registry.isLaunchableCommand(WindowLayoutCommandCatalog.toolID(preset)))
        }
        services.commandCatalog.onCatalogChange = { try registry.refreshTools(for: WindowLayoutsApplication.id) }
        let custom = CustomWindowLayout(id: UUID(), title: "Review space", rect: .init(x: 0.1, y: 0.1, width: 0.6, height: 0.8))
        try services.customStore.save(custom)
        let toolID = CommandID(rawValue: "windows.layouts.apply.custom." + custom.id.uuidString.lowercased())
        #expect(registry.isLaunchableCommand(toolID))
        #expect(registry.isLaunchableCommand(QuickAIApplication.id))
        try services.customStore.delete(id: custom.id)
        #expect(!registry.isLaunchableCommand(toolID))
        #expect(registry.isLaunchableCommand(QuickAIApplication.id))
    }
}
