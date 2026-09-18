import CommandKit
import Testing
@testable import Commandly

@MainActor
struct SlackEmojiApplicationTests {
    @Test func catalogRegistersSlackEmojiAndItsExplicitEntryPoint() {
        let registry = LauncherApplicationRegistry.makeBuiltIn()
        for id in [SlackEmojiApplication.id, SlackEmojiApplication.openToolID] {
            #expect(registry.definition(for: id) != nil)
            #expect(registry.isLaunchableCommand(id))
        }
    }
}
