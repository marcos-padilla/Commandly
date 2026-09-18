import DesignSystem
import SwiftUI

/// Metadata editing never reads or changes the captured clipboard payload.
struct ClipboardOrganizationFields: View {
    @Bindable var viewModel: ClipboardHistoryViewModel
    @FocusState private var focusesName: Bool
    @Environment(\.commandlyLayoutDensity) private var density

    var body: some View {
        VStack(alignment: .leading, spacing: density.spacing(.md)) {
            VStack(alignment: .leading, spacing: density.spacing(.xs)) {
                Text("Name")
                    .commandlyFont(size: 12, weight: .semibold)
                TextField("Use the original preview", text: $viewModel.editorName)
                    .textFieldStyle(.roundedBorder)
                    .focused($focusesName)
                    .accessibilityLabel("Clipboard entry name")
                    .onSubmit(viewModel.saveEditor)
                Text("Optional · up to 120 characters")
                    .commandlyFont(size: 10)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: density.spacing(.xs)) {
                HStack {
                    Text("Collection")
                        .commandlyFont(size: 12, weight: .semibold)
                    Spacer()
                    if viewModel.availableCollections.isEmpty == false {
                        Menu("Choose Existing") {
                            ForEach(viewModel.availableCollections, id: \.self) { collection in
                                Button(collection) { viewModel.editorCollection = collection }
                            }
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                        .accessibilityLabel("Choose an existing clipboard collection")
                    }
                }
                TextField("For example, Research", text: $viewModel.editorCollection)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Clipboard collection name")
                    .onSubmit(viewModel.saveEditor)
                Text("Use the same name to group entries. Leave blank to remove the collection.")
                    .commandlyFont(size: 10)
                    .foregroundStyle(.secondary)
            }

            Label("Names, collections, and pins last until Commandly quits.", systemImage: "info.circle")
                .commandlyFont(size: 11)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.top, density.spacing(.sm))
        .onAppear {
            DispatchQueue.main.async { focusesName = true }
        }
    }
}
