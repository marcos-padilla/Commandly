import DesignSystem
import SwiftUI

struct DictationHistoryView: View {
    @Bindable var model: DictationHistoryViewModel
    let close: () -> Void
    @FocusState private var searchFocused: Bool
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Saved Dictations").commandlyFont(size: 17, weight: .semibold).accessibilityAddTraits(.isHeader)
                Spacer(); Button("Done", action: close).keyboardShortcut(.cancelAction)
            }
            TextField("Search saved text or language", text: $model.query).textFieldStyle(.roundedBorder).focused($searchFocused)
                .accessibilityLabel("Search saved dictations").onSubmit(model.copySelected)
            HStack(spacing: 14) {
                List(selection: $model.selectedID) {
                    ForEach(model.filtered) { entry in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(entry.title).lineLimit(2).commandlyFont(size: 12)
                            Text(entry.createdAt, format: .dateTime.month(.abbreviated).day().hour().minute())
                                .commandlyFont(size: 10).foregroundStyle(.secondary)
                        }.padding(.vertical, 4).tag(entry.id)
                    }
                }.frame(width: 210).accessibilityLabel("Saved dictation list")
                    .onKeyPress(.return) { model.copySelected(); return .handled }
                if let entry = model.selected {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 9) {
                            Text(entry.languageName).commandlyFont(size: 11).foregroundStyle(.secondary)
                            Text(entry.text).commandlyFont(size: 13).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }.id(entry.id).accessibilityElement(children: .contain).accessibilityLabel("Saved dictation text")
                } else {
                    Text(model.isBusy ? "Loading…" : "Only dictations you explicitly save appear here.")
                        .commandlyFont(size: 12).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                }
            }.frame(height: 300)
            if let error = model.errorMessage { Text(error).commandlyFont(size: 11).foregroundStyle(.orange) }
            if let status = model.statusMessage { Text(status).commandlyFont(size: 11).foregroundStyle(.secondary) }
            HStack {
                Button("Clear History…") { model.showsClearConfirmation = true }.disabled(model.isBusy || (model.entries.isEmpty && model.errorMessage == nil))
                Text("50 records · 2 MiB maximum · text only").commandlyFont(size: 10).foregroundStyle(.secondary)
                Spacer()
                Button("Delete…") { model.showsDeleteConfirmation = true }.disabled(model.isBusy || model.selected == nil)
                Button("Copy Text", action: model.copySelected).disabled(model.isBusy || model.selected == nil)
                    .keyboardShortcut("c", modifiers: [.command, .shift])
            }.controlSize(.small)
        }
        .padding(18).frame(width: 650)
        .onAppear { DispatchQueue.main.async { searchFocused = true } }
        .alert("Delete this saved dictation?", isPresented: $model.showsDeleteConfirmation) {
            Button("Keep", role: .cancel) {}; Button("Delete", role: .destructive, action: model.deleteSelected)
        } message: { Text("The selected saved text will be removed from local history. Your current draft is unchanged.") }
        .alert("Clear all dictation history?", isPresented: $model.showsClearConfirmation) {
            Button("Keep History", role: .cancel) {}; Button("Clear History", role: .destructive, action: model.clear)
        } message: { Text("This removes all saved dictations from Commandly. Your current draft and any text you copied elsewhere remain unchanged.") }
        .accessibilityElement(children: .contain).accessibilityLabel("Saved dictation history")
    }
}
