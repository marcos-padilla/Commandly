import AIKit
import DesignSystem
import SwiftUI
import UniformTypeIdentifiers

struct AIAgentSkillDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data
    init(skill: AIAgentSkill) throws { data = try JSONEncoder().encode(AIAgentSkillFile(skill: skill)) }
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents, data.count <= 32_768 else { throw AIAgentLibraryError.invalidData }
        self.data = data
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

struct AIAgentsView: View {
    @Bindable var model: AIAgentsViewModel
    @State private var showsImport = false
    @State private var showsExport = false
    @State private var exportDocument: AIAgentSkillDocument?
    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HStack(spacing: 0) {
                sidebar.frame(width: 165)
                Divider()
                VStack(spacing: 0) {
                    Picker("Agent workspace", selection: $model.page) {
                        ForEach(AIAgentsPage.allCases) { Text($0.rawValue).tag($0) }
                    }.pickerStyle(.segmented).padding(10).disabled(model.isBusy)
                    if model.isBusy { ProgressView().controlSize(.small).padding(.bottom, 6) }
                    if let message = model.statusMessage {
                        Text(message).font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 12).padding(.bottom, 6)
                    }
                    content.frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .background(LauncherPalette.detail)
        .task { model.start() }
        .onDisappear { model.stop() }
        .fileImporter(isPresented: $showsImport, allowedContentTypes: [.json]) { result in
            switch result { case .success(let url): model.importSkill(url); case .failure: model.reportFileError() }
        }
        .fileExporter(isPresented: $showsExport, document: exportDocument, contentType: .json, defaultFilename: "Commandly Agent Skill") { result in
            if case .failure = result { model.reportFileError() }
        }
        .accessibilityLabel("Custom AI Agents")
    }
    private var header: some View {
        HStack(spacing: 10) {
            Button(action: model.goBack) { Image(systemName: "chevron.left") }.buttonStyle(.plain).accessibilityLabel("Back to launcher")
            Image(systemName: "person.crop.square.badge.sparkles")
            Text("AI Agents").font(.headline)
            Spacer()
            Button("Shortcuts", action: model.openShortcutSettings).help("Assign a hotkey to each agent’s launcher entry in Applications settings")
            Button("AI Settings", action: model.openSettings)
        }.padding(12).background(LauncherPalette.chrome)
    }
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack { Text("Your Agents").font(.caption).foregroundStyle(.secondary); Spacer(); Button(action: model.newAgent) { Image(systemName: "plus") }.accessibilityLabel("Create agent") }.padding(10)
            ScrollView {
                LazyVStack(spacing: 3) {
                    ForEach(model.library.document.agents) { agent in
                        Button { model.selectAgent(agent.id) } label: {
                            HStack { Image(systemName: "sparkles"); Text(agent.name).lineLimit(2); Spacer(minLength: 0) }
                                .font(.system(size: 12)).padding(8).background(model.selectedAgentID == agent.id ? Color.accentColor.opacity(0.15) : .clear, in: RoundedRectangle(cornerRadius: 6))
                        }.buttonStyle(.plain).accessibilityLabel("Open agent \(agent.name)")
                    }
                }.padding(.horizontal, 5)
            }
            Button("New Agent", action: model.newAgent).padding(10)
        }.disabled(model.isBusy)
    }
    @ViewBuilder private var content: some View {
        switch model.page {
        case .chat:
            if model.contextChanged {
                empty("Saved context changed", "Start a new chat to use the current agent, profile, skills, and memories. Previous context will be cleared.", action: "Start New Chat", model.openChat)
            } else if let chat = model.chat {
                QuickAIView(viewModel: chat, title: model.agent?.name ?? "AI Agent", subtitle: "Your configured text assistant", contextDisclosure: model.memoryDisclosure, onRemember: model.remember)
            } else if model.agent == nil {
                empty("Create an agent", "Give it instructions, choose your model, and select the context it may use.", action: "New Agent", model.newAgent)
            } else {
                empty("Choose a model", "This agent’s configured model must be available from your saved provider connection. Editing the agent does not contact the provider.", action: "Edit Agent", model.editAgent)
            }
        case .agent: agentEditor
        case .profile: profileEditor
        case .memory: memoryEditor
        case .skills: skillEditor
        }
    }
    private var agentEditor: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                TextField("Agent name", text: $model.draftName).accessibilityLabel("Agent name")
                Text("Instructions").font(.headline)
                editor($model.draftInstructions, label: "Agent instructions", height: 130)
                Text("This agent writes and discusses text. It cannot run tools, browse, or continue work in the background.").font(.caption).foregroundStyle(.secondary)
                Picker("Provider and model", selection: $model.draftModelID) {
                    Text("Choose a model").tag("")
                    ForEach(model.choices) { Text($0.title).tag($0.id) }
                }
                HStack {
                    Button("Refresh Provider Models", action: model.refreshModels)
                    Text("Contacts the selected provider using your saved connection.").font(.caption).foregroundStyle(.secondary)
                }
                Toggle("Use My Profile", isOn: $model.draftUsesProfile)
                Text("Enabled instruction skills").font(.headline)
                if model.library.document.skills.isEmpty { Text("Create or import a text skill in Skills.").font(.caption).foregroundStyle(.secondary) }
                ForEach(model.library.document.skills) { skill in
                    Toggle(skill.name, isOn: Binding(get: { model.draftSkillIDs.contains(skill.id) }, set: { enabled in
                        if enabled { model.draftSkillIDs.insert(skill.id) } else { model.draftSkillIDs.remove(skill.id) }
                    }))
                }
                HStack {
                    Button("Save Agent", action: model.saveAgent).buttonStyle(.borderedProminent).disabled(!model.canSaveAgent)
                    if model.isEditingExistingAgent { Button("Delete Agent and Memories", role: .destructive, action: model.deleteAgent) }
                }
                Text("Each saved agent appears in launcher search. Use Shortcuts to assign its own hotkey in Applications settings.").font(.caption).foregroundStyle(.secondary)
            }.padding(14).disabled(model.isBusy)
        }
    }
    private var profileEditor: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Your profile, in your words").font(.headline)
                Text("Write preferences or background you want selected agents to use. This stays on this Mac until you send a message with Use My Profile enabled. It is not a place for passwords or API keys.").font(.caption).foregroundStyle(.secondary)
                editor($model.personalProfile, label: "Personal AI profile", height: 220)
                Text("\(model.personalProfile.utf8.count) / 16384 bytes").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                HStack {
                    Button("Save Profile", action: model.savePersonalProfile).buttonStyle(.borderedProminent).disabled(model.personalProfile.utf8.count > 16_384)
                    Button("Clear Draft") { model.personalProfile = "" }
                }
                Text("Save an empty profile to remove its stored contents. No activity is collected automatically.").font(.caption).foregroundStyle(.secondary)
            }.padding(14).disabled(model.isBusy)
        }
    }
    private var memoryEditor: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(model.agent.map { "Memory for \($0.name)" } ?? "Select an agent to manage memory").font(.headline)
                Text("Only explicitly saved, enabled memories are sent with this agent’s messages. Edit or delete them at any time.").font(.caption).foregroundStyle(.secondary)
                ForEach(model.memories) { memory in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(memory.text).lineLimit(3).textSelection(.enabled)
                        Text("\(sourceTitle(memory.source)) · \(memory.createdAt.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(.secondary)
                        HStack {
                            Button(memory.isEnabled ? "Disable" : "Enable") { model.toggleMemory(memory) }
                            Button("Edit") { model.editMemory(memory) }
                            Button("Delete", role: .destructive) { model.deleteMemory(memory) }
                        }.font(.caption)
                    }.padding(10).frame(maxWidth: .infinity, alignment: .leading).background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 6))
                }
                Divider()
                Text(model.memoryID == nil ? "Review a new memory" : "Edit memory").font(.headline)
                Text(sourceTitle(model.memorySource)).font(.caption).foregroundStyle(.secondary)
                editor($model.memoryText, label: "Memory text to save", height: 130)
                Text("\(model.memoryText.utf8.count) / 8192 bytes · edit long replies to the excerpt you want to keep").font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("Save Memory", action: model.saveMemory).buttonStyle(.borderedProminent).disabled(!model.canSaveMemory)
                    Button("Clear Draft", action: model.clearMemoryDraft)
                }
            }.padding(14).disabled(model.isBusy)
        }
    }
    private var skillEditor: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack { Text("Reusable text skills").font(.headline); Spacer(); Button("New", action: model.newSkill); Button("Import JSON") { showsImport = true } }
                Text("Skills contain instructions only. Importing a file does not execute code or enable the skill for an agent.").font(.caption).foregroundStyle(.secondary)
                ForEach(model.library.document.skills) { skill in
                    HStack {
                        Button(skill.name) { model.editSkill(skill) }.buttonStyle(.plain)
                        Spacer()
                        Button("Export") {
                            do { exportDocument = try AIAgentSkillDocument(skill: skill); showsExport = true }
                            catch { model.reportFileError() }
                        }
                        Button("Delete", role: .destructive) { model.deleteSkill(skill) }
                    }
                }
                Divider()
                TextField("Skill name", text: $model.skillName).accessibilityLabel("Instruction skill name")
                editor($model.skillInstructions, label: "Reusable skill instructions", height: 200)
                Text("\(model.skillInstructions.utf8.count) / 16384 bytes").font(.caption).foregroundStyle(.secondary)
                Button("Save Skill", action: model.saveSkill).buttonStyle(.borderedProminent).disabled(!model.canSaveSkill)
            }.padding(14).disabled(model.isBusy)
        }
    }
    private func editor(_ text: Binding<String>, label: String, height: CGFloat) -> some View {
        TextEditor(text: text).font(.system(size: 12)).frame(minHeight: height).scrollContentBackground(.hidden).padding(6)
            .background(LauncherPalette.surface, in: RoundedRectangle(cornerRadius: 6)).accessibilityLabel(label)
    }
    private func empty(_ title: String, _ detail: String, action: String, _ run: @escaping () -> Void) -> some View {
        VStack(spacing: 12) { Text(title).font(.title3.bold()); Text(detail).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center); Button(action, action: run).buttonStyle(.borderedProminent) }
            .padding(24).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    private func sourceTitle(_ source: AIAgentMemorySource) -> String {
        switch source { case .manual: "Written by you"; case .userMessage: "Saved from your message"; case .agentReply: "Saved from an agent reply" }
    }
}
