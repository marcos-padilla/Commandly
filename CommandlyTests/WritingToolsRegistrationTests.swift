import AppKit
import CommandKit
import Testing
@testable import Commandly

@MainActor
struct WritingToolsRegistrationTests {
    @Test func builtInRegistryContainsBothWritingEntryPointsWithoutStartingChecks() {
        let registry = LauncherApplicationRegistry.makeBuiltIn()
        #expect(registry.isLaunchableCommand(WritingToolsApplication.id))
        #expect(registry.isLaunchableCommand(WritingToolsApplication.reviewToolID))
        #expect(registry.isLaunchableCommand(WritingToolsApplication.inlineHelpToolID))
    }

    @Test func builtApplicationDeclaresExactTextServiceSelectorAndBoundedTimeout() throws {
        let services = try #require(Bundle.main.object(forInfoDictionaryKey: "NSServices") as? [[String: Any]])
        let candidate = services.first { ($0["NSMessage"] as? String) == "quickFixSelection" }
        let entry = try #require(candidate)
        #expect(entry["NSPortName"] as? String == "Commandly")
        #expect(entry["NSSendTypes"] as? [String] == ["public.utf8-plain-text"])
        #expect(entry["NSReturnTypes"] as? [String] == ["public.utf8-plain-text"])
        #expect(entry["NSTimeout"] as? String == NativeWritingServiceProvider.advertisedTimeoutMilliseconds)
        let provider = NativeWritingServiceProvider(checker: InMemoryWritingChecker())
        #expect(provider.responds(to: NSSelectorFromString("quickFixSelection:userData:error:")))
    }
}
