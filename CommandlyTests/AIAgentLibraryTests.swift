import AIKit
import CommandKit
import Foundation
import Testing
@testable import Commandly

struct AIAgentLibraryTests {
    @Test func contextOnlyIncludesExplicitAgentAllowlist() throws {
        let skill = AIAgentSkill(name: "Tone", instructions: "Use concise text.")
        let agent = AIAgentProfile(name: "Writer", instructions: "Help draft.", skillIDs: [skill.id])
        let other = AIAgentProfile(name: "Other", instructions: "Other instructions.")
        let doc = AIAgentLibraryDocument(personalProfile: "Private profile", agents: [agent, other], skills: [skill], memories: [
            .init(agentID: agent.id, text: "Allowed memory"), .init(agentID: agent.id, text: "Disabled memory", isEnabled: false),
            .init(agentID: other.id, text: "Other memory")])
        let text = try JSONEncoder().encode(AIAgentContext.systemMessage(agent: agent, library: doc))
        let encoded = String(decoding: text, as: UTF8.self)
        #expect(encoded.contains("Allowed memory")); #expect(encoded.contains("Use concise text."))
        #expect(!encoded.contains("Disabled memory")); #expect(!encoded.contains("Other memory")); #expect(!encoded.contains("Private profile"))
    }
    @Test func skillImportCreatesFreshIdentityAndRejectsUnknownVersion() throws {
        let skill = AIAgentSkill(name: "Review", instructions: "Explain tradeoffs.")
        let bytes = try JSONEncoder().encode(AIAgentSkillFile(skill: skill))
        let imported = try JSONDecoder().decode(AIAgentSkillFile.self, from: bytes).importedSkill()
        #expect(imported.id != skill.id); #expect(imported.instructions == skill.instructions)
        let invalid = Data("{\"format\":\"commandly-agent-skill\",\"version\":2,\"name\":\"Review\",\"instructions\":\"text\"}".utf8)
        #expect(throws: AIAgentLibraryError.invalidData) { try JSONDecoder().decode(AIAgentSkillFile.self, from: invalid).importedSkill() }
    }
    @Test func localStorePersistsExplicitMemoryAndRejectsStaleRevision() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("commandly-agent-fixture-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = LocalAIAgentLibraryStore(directory: directory)
        let original = try await store.load()
        #expect(!FileManager.default.fileExists(atPath: directory.path))
        let agent = AIAgentProfile(name: "Personal", instructions: "Help.")
        let saved = AIAgentLibraryDocument(agents: [agent], memories: [.init(agentID: agent.id, text: "User reviewed", source: .agentReply)])
        try await store.save(saved, replacing: original.revision)
        #expect(try await LocalAIAgentLibraryStore(directory: directory).load() == saved)
        do { try await store.save(saved, replacing: original.revision); Issue.record("Stale revision saved") }
        catch { #expect(error as? AIAgentLibraryError == .changed) }
    }
    @Test @MainActor func libraryChangesRefreshStableLauncherTools() async throws {
        let library = AIAgentLibrary(store: InMemoryAIAgentLibraryStore())
        let registry = LauncherApplicationRegistry()
        try registry.register(BuiltInLauncherApplicationGroup.aiExtensions)
        try registry.register(AIAgentsApplication(services: .init(library: library, chat: InMemoryQuickAIService())))
        library.onCatalogChange = { try registry.refreshTools(for: AIAgentsApplication.id) }
        try await library.load()
        let agent = AIAgentProfile(name: "Writing partner", instructions: "Help draft.")
        try await library.update { $0.agents.append(agent) }
        let toolID = AIAgentsApplication.toolID(for: agent.id)
        #expect(registry.definition(for: toolID)?.title == "Writing partner")
        try await library.update { $0.agents[0].name = "Editor" }
        #expect(registry.definition(for: toolID)?.title == "Editor")
        try await library.update { $0.agents.removeAll() }
        #expect(registry.definition(for: toolID) == nil)
    }
}
