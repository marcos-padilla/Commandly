import DesignSystem
import SwiftUI

struct FloatingNoteView: View {
    @Bindable var model: FloatingNoteModel
    @Environment(\.commandlyTextScale) private var textScale

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Label("QUICK NOTE", systemImage: "note.text")
                    .commandlyFont(size: 10, weight: .semibold)
                    .tracking(0.8)
                    .foregroundStyle(.secondary)
                Spacer()
                Toggle(isOn: $model.isPinned) {
                    Image(systemName: model.isPinned ? "pin.fill" : "pin")
                        .frame(width: 20, height: 20)
                }
                .toggleStyle(.button)
                .controlSize(.small)
                .help(model.isPinned ? "Stop keeping this note on top" : "Keep this note on top")
                .accessibilityLabel("Keep note on top")
                .accessibilityIdentifier("floating-note-pin")
            }
            .padding(.bottom, 14)

            TextField("Title, or let the first line name it", text: $model.title)
                .textFieldStyle(.plain)
                .commandlyFont(size: 20, weight: .semibold)
                .accessibilityLabel("Note title")
                .accessibilityIdentifier("floating-note-title")
                .padding(.bottom, 10)

            Divider().padding(.bottom, 10)
            FloatingNoteTextEditor(
                text: $model.content, isEditable: true, textScale: textScale,
                onClose: model.requestClose, onOversizedInput: model.reportOversizedInput
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if let message = model.errorMessage {
                VStack(alignment: .leading, spacing: 8) {
                    Label(message, systemImage: "exclamationmark.circle")
                        .commandlyFont(size: 12)
                        .fixedSize(horizontal: false, vertical: true)
                    if model.hasConflict {
                        Button("Save as Copy", action: model.saveAsCopy)
                            .keyboardShortcut("s", modifiers: [.command, .shift])
                            .disabled(model.isSaving)
                            .accessibilityIdentifier("floating-note-save-copy")
                    }
                }
                .foregroundStyle(.primary)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 9))
                .padding(.top, 8)
            }

            Divider().padding(.top, 10).padding(.bottom, 10)
            HStack(spacing: 10) {
                if model.isSaving { ProgressView().controlSize(.mini) }
                Text(model.statusText)
                    .commandlyFont(size: 11)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .accessibilityIdentifier("floating-note-save-status")
                Spacer(minLength: 0)
                Button("Save", action: model.save)
                    .keyboardShortcut("s", modifiers: .command)
                    .disabled(model.isSaving || (model.hasSaved && !model.hasUnsavedChanges))
                    .accessibilityIdentifier("floating-note-save")
                Button("Save & Close", action: model.saveAndClose)
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(model.isSaving)
                    .accessibilityIdentifier("floating-note-save-close")
            }
        }
        .padding(18)
        .background(Color(nsColor: .windowBackgroundColor))
        .alert("Save changes to this note?", isPresented: $model.showsCloseConfirmation) {
            Button("Save & Close", action: model.saveAndClose)
            Button("Discard Changes", role: .destructive, action: model.discardAndClose)
            Button("Keep Editing", role: .cancel, action: model.keepEditing)
        } message: {
            Text("Your saved note stays in Quick Notes. Unsaved edits are kept only while this window remains open.")
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Floating Quick Note")
    }
}
