import CommandKit
import Infrastructure
import SwiftUI

struct KeyboardTriggerSettingsSection: View {
    @Bindable var model: KeyboardTriggerSettingsModel
    @State private var selectedKey = CompanionTriggerKey.f6
    @State private var usesHyper = false
    @State private var commandID = ""
    @State private var quicklinkID: UUID?
    @State private var doubleKey = CompanionDoubleTapKey.rightShift
    @State private var expansionItemID: UUID?
    @State private var keyword = ";hello"
    @State private var showsEnableExplanation = false
    var body: some View {
        GroupBox("Keyboard Triggers") {
            VStack(alignment: .leading, spacing: 14) {
                Text("Opt in to configured keys and optional expansion. The companion receives keyboard events before filtering, passes unrelated keys through, and keeps no typing history. Input Monitoring and Accessibility must be granted in Companion Setup.")
                    .font(.callout).foregroundStyle(.secondary)
                Toggle("Use Caps Lock as Hyper (⌃⌥⇧⌘)", isOn: Binding(get: { model.preferences.hyperEnabled }, set: model.setHyper))
                if model.preferences.hyperEnabled {
                    Toggle("A short Caps Lock tap keeps normal Caps Lock", isOn: Binding(get: { model.preferences.preserveCapsLockTap }, set: model.setPreserveCapsTap))
                }
                Text("Single keys pass through editable and unknown fields unless they are function keys or used with Hyper. Double taps use a modifier twice within 0.35 seconds; its normal modifier behavior remains available.")
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(model.preferences.assignments) { assignment in
                    HStack {
                        Text(bindingTitle(assignment) + " → " + model.title(for: assignment.destination))
                        Spacer()
                        Button("Remove") { model.remove(assignment.id) }.accessibilityLabel("Remove keyboard trigger")
                    }
                }
                VStack(alignment: .leading) {
                    Picker("Single key", selection: $selectedKey) {
                        ForEach(CompanionTriggerKey.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    if model.preferences.hyperEnabled { Toggle("Require Hyper", isOn: $usesHyper) }
                    Picker("Command", selection: $commandID) {
                        Text("Choose a registered command").tag("")
                        ForEach(model.commands) { Text($0.title).tag($0.id) }
                    }
                    Button("Add Command Key") {
                        guard let option = model.commands.first(where: { $0.id == commandID }) else { return }
                        model.addKey(selectedKey, hyper: model.preferences.hyperEnabled && usesHyper, destination: .command(option.reference))
                    }.disabled(commandID.isEmpty)
                }
                VStack(alignment: .leading) {
                    Picker("Folder Quicklink", selection: $quicklinkID) {
                        Text("Choose a saved folder Quicklink").tag(Optional<UUID>.none)
                        ForEach(folderQuicklinks) { Text($0.title).tag(Optional($0.id)) }
                    }
                    Picker("Double-tap modifier", selection: $doubleKey) {
                        ForEach(CompanionDoubleTapKey.allCases, id: \.self) { Text(doubleTitle($0)).tag($0) }
                    }
                    Button("Add Folder Double Tap") { if let quicklinkID { model.addDoubleTap(doubleKey, quicklink: quicklinkID) } }
                        .disabled(quicklinkID == nil)
                    Button("Add Quicklink Single Key") {
                        if let quicklinkID { model.addKey(selectedKey, hyper: model.preferences.hyperEnabled && usesHyper, destination: .quicklink(quicklinkID)) }
                    }.disabled(quicklinkID == nil)
                }
                Divider()
                Toggle("Automatically expand configured snippet and emoji keywords", isOn: Binding(get: { model.preferences.expansionsEnabled }, set: model.setExpansions))
                Text("Use a punctuation prefix such as ;hello. Space, Return, or Tab expands a complete keyword in a supported, non-secure editable field. Only literal snippets are eligible; named inputs, clipboard variables, and dynamic templates stay in the Library. Expansion bodies are shared only with this companion session.")
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(model.preferences.expansions) { assignment in
                    HStack {
                        Text(assignment.keyword + " → " + (model.libraryItems.first(where: { $0.id == assignment.itemID })?.title ?? "Unavailable library item"))
                        Spacer(); Button("Remove") { model.remove(assignment.id) }.accessibilityLabel("Remove expansion keyword")
                    }
                }
                TextField("Expansion keyword", text: $keyword)
                Picker("Snippet or Emoji Keyword", selection: $expansionItemID) {
                    Text("Choose a literal library item").tag(Optional<UUID>.none)
                    ForEach(model.libraryItems.filter { ($0.kind == .snippet || $0.kind == .emojiKeyword) && !$0.content.contains("{{") }) {
                        Text($0.title).tag(Optional($0.id))
                    }
                }
                Button("Add Expansion") { if let expansionItemID { model.addExpansion(keyword: keyword, itemID: expansionItemID) } }
                    .disabled(expansionItemID == nil || keyword.isEmpty)
            }.disabled(model.isBusy || model.isEnabled)
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Button("Enable Configured Triggers…") { showsEnableExplanation = true }.disabled(!model.canEnable || model.isEnabled)
                    Button("Stop Keyboard Triggers") { model.disable() }.disabled(!model.isEnabled && !model.isBusy)
                }
                if let message = model.message { Text(message).font(.callout).foregroundStyle(.secondary) }
            }.padding(.top, 12)
        }
        .task { model.refresh() }
        .alert("Enable configured keyboard triggers?", isPresented: $showsEnableExplanation) {
            Button("Enable") { model.enable() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The companion will intercept only the configured keys and, if selected above, replace matching keywords in supported text fields. Secure Input, a lost permission, disconnect, or session expiry stops it. Settings changes require stopping first.")
        }
    }
    private var folderQuicklinks: [ProductivityLibraryItem] {
        model.libraryItems.filter { item in
            item.kind == .quicklink && (try? ProductivityQuicklinkValidator().validatedURL(from: item.content).isFileURL) == true
        }
    }
    private func bindingTitle(_ value: KeyboardTriggerAssignment) -> String {
        if let key = value.key { return (value.requiresHyper ? "Hyper + " : "") + key.title }
        if let key = value.doubleTap { return doubleTitle(key) + " twice" }
        return "Unavailable trigger"
    }
    private func doubleTitle(_ value: CompanionDoubleTapKey) -> String {
        switch value {
        case .leftShift: "Left Shift"; case .rightShift: "Right Shift"
        case .leftControl: "Left Control"; case .rightControl: "Right Control"
        case .leftOption: "Left Option"; case .rightOption: "Right Option"
        case .leftCommand: "Left Command"; case .rightCommand: "Right Command"
        }
    }
}
