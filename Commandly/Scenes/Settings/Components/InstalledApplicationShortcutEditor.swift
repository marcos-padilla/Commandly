import DesignSystem
import SwiftUI

struct InstalledApplicationShortcutEditor: View {
    @Bindable var model: InstalledApplicationShortcutEditorModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Shortcut for \(model.applicationName)")
                .commandlyFont(size: 19, weight: .semibold)
                .accessibilityAddTraits(.isHeader)
            Text("Open this application from anywhere while Commandly is running. Record a key combination, then save it.")
                .commandlyFont(size: 12)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            ApplicationHotkeyRecorder(
                hotKey: model.hotKey, isDisabled: false,
                accessibilityTitle: model.applicationName,
                onChange: { model.hotKey = $0 },
                onRecordingChange: model.recordingChanged
            )
            Text("Use Command, Option, or Control with a key. Escape stops recording; Delete clears the draft shortcut.")
                .commandlyFont(size: 11)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let error = model.errorMessage {
                Label(error, systemImage: "exclamationmark.circle")
                    .commandlyFont(size: 11)
                    .foregroundStyle(SemanticColors.color(for: .danger))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button(model.showsOtherAssignments ? "Hide Other App Shortcuts" : "Manage Other App Shortcuts…",
                   action: model.toggleOtherAssignments)
                .buttonStyle(.borderless)
                .commandlyFont(size: 11)
            if model.showsOtherAssignments {
                if model.otherAssignments.isEmpty {
                    Text("No other application shortcuts are saved.")
                        .commandlyFont(size: 11).foregroundStyle(.secondary)
                } else {
                    ScrollView {
                        VStack(spacing: 10) {
                            ForEach(model.otherAssignments) { assignment in
                                HStack(spacing: 10) {
                                    Text(assignment.applicationName)
                                        .lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                                    Text(assignment.hotKey.displayTitle).foregroundStyle(.secondary)
                                    Button("Remove") { model.removeOtherAssignment(assignment.bundleIdentifier) }
                                        .disabled(model.isRecording)
                                        .accessibilityLabel("Remove shortcut for \(assignment.applicationName)")
                                }
                            }
                        }
                        .commandlyFont(size: 11)
                        .padding(.vertical, 3)
                    }
                    .frame(maxHeight: 150)
                }
                if let message = model.managementMessage {
                    Text(message).commandlyFont(size: 11).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack {
                Spacer()
                Button("Cancel", action: model.cancel).keyboardShortcut(.cancelAction)
                Button(model.removesShortcut ? "Remove Shortcut" : "Save Shortcut", action: model.save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!model.canSave)
                    .accessibilityIdentifier("installed-application-shortcut-save")
            }
        }
        .padding(24)
        .frame(width: 440)
    }
}
