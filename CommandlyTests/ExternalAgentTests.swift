import AIKit
import CommandKit
import Foundation
import Testing
@testable import Commandly

struct ExternalAgentTests {
    @Test func endpointRejectsRemotePlaintextAndEmbeddedCredentials() throws {
        #expect(try ExternalAgentEndpoint.parse("http://127.0.0.1:8642/v1/").path == "/v1")
        #expect(try ExternalAgentEndpoint.parse("https://private.example/p/work/v1").path == "/p/work/v1")
        for value in ["http://private.example/v1", "https://token@private.example/v1", "https://private.example/v1?token=x", "https://private.example/a/../v1"] {
            #expect(throws: ExternalAgentError.self) { try ExternalAgentEndpoint.parse(value) }
        }
    }
    @Test func streamSeparatesToolProgressAndRequiresTerminalEvidence() async throws {
        let collector = ExternalAgentTestCollector()
        let parser = ExternalAgentStream(onText: { await collector.append($0) }, onProgress: { await collector.progress() })
        for line in [": keepalive", "event: hermes.tool.progress", "data: {\"tool\":\"generated-tool\"}", "",
                     "data: {\"choices\":[{\"index\":0,\"delta\":{\"content\":\"Hello\"}}]}", "",
                     "data: {\"choices\":[{\"index\":0,\"delta\":{},\"finish_reason\":\"stop\"}]}", "", "data: [DONE]", ""] {
            try await parser.accept(line)
        }
        try await parser.complete()
        #expect(await collector.text == "Hello"); #expect(await collector.progressCount == 1)
        let incomplete = ExternalAgentStream(onText: { _ in }, onProgress: {})
        await #expect(throws: ExternalAgentError.self) { try await incomplete.complete() }
    }
    @Test @MainActor func registryHasBothAgentApplicationsAndHotkeyTools() {
        let registry = LauncherApplicationRegistry.makeBuiltIn()
        for kind in ExternalAgentKind.allCases {
            let id = ExternalAgentApplication.id(kind)
            #expect(registry.isLaunchableCommand(id))
            #expect(registry.isLaunchableCommand(.init(rawValue: id.rawValue + ".tool.open")))
        }
    }
}
private actor ExternalAgentTestCollector {
    var text = ""
    var progressCount = 0
    func append(_ value: String) { text += value }
    func progress() { progressCount += 1 }
}
