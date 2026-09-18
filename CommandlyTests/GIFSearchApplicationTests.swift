import CommandKit
import Testing
@testable import Commandly

@MainActor
struct GIFSearchApplicationTests {
    @Test func catalogRegistersGIFSearchAndItsExplicitEntryPoint() {
        let registry = LauncherApplicationRegistry.makeBuiltIn()
        for id in [GIFSearchApplication.id, GIFSearchApplication.openToolID] {
            #expect(registry.definition(for: id) != nil)
            #expect(registry.isLaunchableCommand(id))
        }
    }
}
