import DesignSystem
import SwiftUI

/// A focused nickname editor usable from installed-app actions or a settings inspector.
struct ApplicationAliasEditor: View {
    @Bindable var model: ApplicationAliasEditorModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Alias for \(model.applicationName)")
                    .commandlyFont(size: 19, weight: .semibold)
                    .accessibilityAddTraits(.isHeader)
                Text("Type this nickname in Commandly to find this application. Its original name still works.")
                    .commandlyFont(size: 12)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 7) {
                ApplicationAliasTextField(text: $model.alias, onSubmit: model.save)
                if let message = model.validationMessage ?? model.saveError {
                    Label(message, systemImage: "exclamationmark.circle")
                        .commandlyFont(size: 11)
                        .foregroundStyle(SemanticColors.color(for: .danger))
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("Up to 64 characters. Clear the field to remove an alias.")
                        .commandlyFont(size: 11)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 10) {
                Spacer()
                Button("Cancel", action: model.cancel)
                    .keyboardShortcut(.cancelAction)
                Button(model.removesAlias ? "Remove Alias" : "Save Alias", action: model.save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(model.canSave == false)
                    .accessibilityIdentifier("application-alias-save")
            }
        }
        .padding(24)
        .frame(width: 440)
    }
}
