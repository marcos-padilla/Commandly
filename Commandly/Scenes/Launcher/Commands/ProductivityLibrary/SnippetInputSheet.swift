import DesignSystem
import SwiftUI

/// Named values are held only for this copy operation and cleared on dismissal.
struct SnippetInputSheet: View {
    @Bindable var viewModel: ProductivityLibraryViewModel
    @FocusState private var focusedField: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(viewModel.pendingSnippet?.title ?? "Fill in Snippet")
                    .commandlyFont(size: 19, weight: .semibold)
                    .accessibilityAddTraits(.isHeader)
                Text("Fill in these values, then copy your finished snippet.")
                    .commandlyFont(size: 12)
                    .foregroundStyle(.secondary)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(viewModel.snippetFields, id: \.self) { name in
                        VStack(alignment: .leading, spacing: 5) {
                            Text(name).commandlyFont(size: 12, weight: .medium)
                            TextField(name, text: Binding(
                                get: { viewModel.snippetInputs[name] ?? "" },
                                set: { viewModel.snippetInputs[name] = $0 }
                            ))
                            .textFieldStyle(.roundedBorder)
                            .focused($focusedField, equals: name)
                            .accessibilityLabel(name)
                        }
                    }
                }
            }
            .frame(maxHeight: 300)
            if let message = viewModel.statusMessage {
                Label(message, systemImage: "exclamationmark.circle")
                    .commandlyFont(size: 11)
                    .foregroundStyle(SemanticColors.color(for: .danger))
            }
            HStack {
                Text("Values are cleared when this window closes.")
                    .commandlyFont(size: 11)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Cancel", action: viewModel.cancelSnippetInput)
                    .keyboardShortcut(.cancelAction)
                Button(viewModel.isPerformingPrimaryAction ? "Copying…" : "Copy Snippet", action: viewModel.copyPreparedSnippet)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!viewModel.canCopyPreparedSnippet)
            }
        }
        .padding(24)
        .frame(width: 520)
        .onAppear { focusedField = viewModel.snippetFields.first }
    }
}
