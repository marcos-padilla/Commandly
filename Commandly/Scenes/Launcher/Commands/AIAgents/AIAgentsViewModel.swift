import AIKit
import CommandKit
import Foundation
import Observation

nonisolated enum AIAgentsPage: String, CaseIterable, Identifiable { case chat = "Chat", agent = "Agent", profile = "My Profile", memory = "Memory", skills = "Skills"; var id: String { rawValue } }

@Observable @MainActor final class AIAgentsViewModel: LauncherApplicationModel {
    let library: AIAgentLibrary
    private let service: any QuickAIServicing
    private let onGoBack: () -> Void
    private let onOpenSettings: () -> Void
    private let onOpenApplicationSettings: () -> Void
    private var generation = UUID()
    @ObservationIgnored private var work: Task<Void, Never>?
    private(set) var isBusy = false
    private(set) var statusMessage: String?
    var showsActionsMenu = false
    var page: AIAgentsPage = .chat
    var selectedAgentID: UUID?
    private(set) var chat: QuickAIViewModel?
    private(set) var choices: [QuickAISelection] = []
    var draftName = ""
    var draftInstructions = ""
    var draftUsesProfile = false
    var draftSkillIDs: Set<UUID> = []
    var draftModelID = ""
    var personalProfile = ""
    var skillID: UUID?
    var skillName = ""
    var skillInstructions = ""
    var memoryID: UUID?
    var memoryText = ""
    private(set) var memorySource: AIAgentMemorySource = .manual
    private var memoryDate = Date()
    private var editingAgentID: UUID?
    private var chatRevision: UUID?
    init(services: AIAgentsApplicationServices, selectedAgentID: UUID? = nil,
         onGoBack: @escaping () -> Void, onOpenSettings: @escaping () -> Void,
         onOpenApplicationSettings: @escaping () -> Void) {
        library = services.library; service = services.chat; self.selectedAgentID = selectedAgentID
        self.onGoBack = onGoBack; self.onOpenSettings = onOpenSettings; self.onOpenApplicationSettings = onOpenApplicationSettings
    }
    var agent: AIAgentProfile? { library.document.agents.first { $0.id == selectedAgentID } }
    var memories: [AIAgentMemory] { library.document.memories.filter { $0.agentID == selectedAgentID } }
    var contextChanged: Bool { chat != nil && chatRevision != library.document.revision }
    var selectedSkill: AIAgentSkill? { library.document.skills.first { $0.id == skillID } }
    var isEditingExistingAgent: Bool { editingAgentID != nil }
    var canSaveAgent: Bool { AIAgentLibraryDocument.validName(draftName) && draftInstructions.utf8.count <= 32_768 && choices.contains { $0.id == draftModelID } }
    var canSaveMemory: Bool { agent != nil && !memoryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && memoryText.utf8.count <= 8_192 }
    var canSaveSkill: Bool { AIAgentLibraryDocument.validName(skillName) && !skillInstructions.isEmpty && skillInstructions.utf8.count <= 16_384 }
    var memoryDisclosure: String {
        let enabled = memories.filter(\.isEnabled).count
        return "This agent sends its instructions, \(agent?.skillIDs.count ?? 0) chosen skills, \(enabled) enabled memories\(agent?.usesPersonalProfile == true ? ", and your saved personal profile" : "") with your messages. Chat stays in this session."
    }
    var footerActions: [CommandActionDescriptor] {
        if page == .chat, let chat, !contextChanged { return chat.footerActions }
        return [.init(id: BuiltInCommandActionID.goBack, title: "Back", isPrimary: true)]
    }
    var menuActions: [CommandActionDescriptor] { page == .chat ? (chat?.menuActions ?? []) : [] }
    func perform(_ id: CommandActionID) {
        if id == BuiltInCommandActionID.goBack { goBack() }
        else if !contextChanged { chat?.perform(id) }
    }
    func moveSelection(offset: Int) {}
    func handleEscape() -> Bool { chat?.handleEscape() ?? false }
    func start() {
        run { [self] in
            try await library.load()
            choices = try await service.catalog().selections
            personalProfile = library.document.personalProfile
            if agent == nil { selectedAgentID = library.document.agents.first?.id }
            loadAgentDraft()
            openChat()
        }
    }
    func selectAgent(_ id: UUID) {
        guard !isBusy else { return }
        chat?.stop(); chat = nil; selectedAgentID = id
        loadAgentDraft(); clearMemoryDraft(); page = .chat; openChat()
    }
    func newAgent() {
        chat?.stop(); chat = nil; editingAgentID = nil
        draftName = ""; draftInstructions = ""; draftUsesProfile = false; draftSkillIDs = []
        draftModelID = choices.first?.id ?? ""; page = .agent
    }
    func editAgent() { loadAgentDraft(); page = .agent }
    func saveAgent() {
        guard canSaveAgent, let choice = choices.first(where: { $0.id == draftModelID }) else { return }
        let profile = AIAgentProfile(id: editingAgentID ?? UUID(), name: draftName.trimmingCharacters(in: .whitespacesAndNewlines),
            instructions: draftInstructions, model: .init(providerID: choice.providerID, modelID: choice.modelID),
            usesPersonalProfile: draftUsesProfile, skillIDs: draftSkillIDs.sorted { $0.uuidString < $1.uuidString })
        run { [self] in
            try await library.update { doc in
                if let index = doc.agents.firstIndex(where: { $0.id == profile.id }) { doc.agents[index] = profile }
                else { doc.agents.append(profile) }
            }
            selectedAgentID = profile.id; editingAgentID = profile.id; page = .chat
            statusMessage = "Agent saved. Its launcher entry can be assigned a shortcut in Applications settings."
            openChat()
        }
    }
    func deleteAgent() {
        guard let agent else { return }
        run { [self] in
            chat?.stop(); chat = nil
            try await library.update { doc in doc.agents.removeAll { $0.id == agent.id }; doc.memories.removeAll { $0.agentID == agent.id } }
            selectedAgentID = library.document.agents.first?.id; loadAgentDraft(); openChat()
            statusMessage = "Agent and its saved memories deleted."
        }
    }
    func openChat() {
        chat?.stop(); chat = nil; page = .chat
        guard let agent else { return }
        guard let choice = choices.first(where: { $0.providerID == agent.model?.providerID && $0.modelID == agent.model?.modelID }) else {
            statusMessage = "This agent’s saved model is not loaded. Edit Agent to choose a configured model or explicitly refresh that provider’s models."
            return
        }
        do {
            let snapshot = library.document
            let context = try AIAgentContext.systemMessage(agent: agent, library: snapshot)
            let library = library
            let scoped = AIAgentQuickAIService(base: service, selection: choice, context: context) { [weak library] in
                guard library?.document.revision == snapshot.revision else { throw AIProviderRuntimeError.connectionMismatch }
            }
            chatRevision = snapshot.revision
            chat = QuickAIViewModel(service: scoped, onGoBack: onGoBack, onOpenSettings: onOpenSettings)
        } catch { statusMessage = "This agent’s saved context exceeds its limit or changed. Review its instructions, skills, and memories." }
    }
    func refreshModels() {
        let preferred = choices.first { $0.id == draftModelID }
            ?? choices.first { $0.providerID == agent?.model?.providerID }
            ?? choices.first
        guard let preferred else { onOpenSettings(); return }
        run { [self] in
            let loaded = try await service.refreshModels(for: preferred)
            choices.removeAll { $0.providerID == preferred.providerID }; choices += loaded
            if let saved = agent?.model, let match = choices.first(where: { $0.providerID == saved.providerID && $0.modelID == saved.modelID }) { draftModelID = match.id }
            else if !choices.contains(where: { $0.id == draftModelID }) { draftModelID = choices.first?.id ?? "" }
            statusMessage = "Model list refreshed from \(preferred.providerName)."
        }
    }
    func savePersonalProfile() {
        guard personalProfile.utf8.count <= 16_384 else { statusMessage = "Keep the profile to 16 KiB or less."; return }
        let text = personalProfile
        run { [self] in try await library.update { $0.personalProfile = text }; statusMessage = "Personal profile saved. Only agents with Use My Profile enabled receive it." }
    }
    func editMemory(_ memory: AIAgentMemory) {
        memoryID = memory.id; memoryText = memory.text; memorySource = memory.source; memoryDate = memory.createdAt; page = .memory
    }
    func remember(_ entry: QuickAIEntry) {
        memoryID = nil; memoryText = entry.text; memorySource = entry.isUser ? .userMessage : .agentReply; memoryDate = Date(); page = .memory
        statusMessage = "Review this excerpt, then choose Save Memory. Nothing has been saved yet."
    }
    func clearMemoryDraft() { memoryID = nil; memoryText = ""; memorySource = .manual; memoryDate = Date() }
    func saveMemory() {
        guard canSaveMemory, let agent else { return }
        let memory = AIAgentMemory(id: memoryID ?? UUID(), agentID: agent.id, text: memoryText, isEnabled: library.document.memories.first(where: { $0.id == memoryID })?.isEnabled ?? true,
            source: memorySource, createdAt: memoryDate)
        run { [self] in
            try await library.update { doc in
                if let index = doc.memories.firstIndex(where: { $0.id == memory.id }) { doc.memories[index] = memory }
                else { doc.memories.append(memory) }
            }
            clearMemoryDraft(); statusMessage = "Memory saved for this agent. Start a new chat to use the updated context."
        }
    }
    func toggleMemory(_ memory: AIAgentMemory) {
        run { [self] in try await library.update { doc in if let i = doc.memories.firstIndex(where: { $0.id == memory.id }) { doc.memories[i].isEnabled.toggle() } } }
    }
    func deleteMemory(_ memory: AIAgentMemory) {
        run { [self] in try await library.update { $0.memories.removeAll { $0.id == memory.id } }; clearMemoryDraft() }
    }
    func editSkill(_ skill: AIAgentSkill) { skillID = skill.id; skillName = skill.name; skillInstructions = skill.instructions; page = .skills }
    func newSkill() { skillID = nil; skillName = ""; skillInstructions = ""; page = .skills }
    func saveSkill() {
        guard canSaveSkill else { return }
        let skill = AIAgentSkill(id: skillID ?? UUID(), name: skillName.trimmingCharacters(in: .whitespacesAndNewlines), instructions: skillInstructions)
        run { [self] in
            try await library.update { doc in
                if let i = doc.skills.firstIndex(where: { $0.id == skill.id }) { doc.skills[i] = skill }
                else { doc.skills.append(skill) }
            }
            skillID = skill.id; statusMessage = "Skill saved. Enable it for an agent in the Agent tab."
        }
    }
    func deleteSkill(_ skill: AIAgentSkill) {
        run { [self] in
            try await library.update { doc in doc.skills.removeAll { $0.id == skill.id }; for i in doc.agents.indices { doc.agents[i].skillIDs.removeAll { $0 == skill.id } } }
            newSkill(); loadAgentDraft()
        }
    }
    func importSkill(_ url: URL) {
        run { [self] in let imported = try await library.importedSkill(from: url); editSkill(imported); statusMessage = "Imported for review. Save Skill to add these text instructions." }
    }
    func reportFileError() { statusMessage = "The skill file could not be read or written." }
    func openSettings() { onOpenSettings() }
    func openShortcutSettings() { onOpenApplicationSettings() }
    func goBack() { stop(); onGoBack() }
    func stop() { generation = UUID(); work?.cancel(); work = nil; isBusy = false; chat?.stop(); chat = nil; memoryText = "" }
    private func loadAgentDraft() {
        guard let agent else { return }
        editingAgentID = agent.id; draftName = agent.name; draftInstructions = agent.instructions
        draftUsesProfile = agent.usesPersonalProfile; draftSkillIDs = Set(agent.skillIDs)
        draftModelID = choices.first { $0.providerID == agent.model?.providerID && $0.modelID == agent.model?.modelID }?.id ?? ""
    }
    private func run(_ operation: @escaping @MainActor () async throws -> Void) {
        guard !isBusy else { return }
        isBusy = true; statusMessage = nil
        let token = generation
        work = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { if generation == token { isBusy = false; work = nil } }
            do { try await operation(); if generation == token, let issue = library.status { statusMessage = issue } }
            catch is CancellationError { return }
            catch { if generation == token { statusMessage = "Could not complete this change. Check model settings and library limits, then try again. Your last saved library is preserved." } }
        }
    }
}
