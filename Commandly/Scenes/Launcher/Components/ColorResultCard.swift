import CommandKit
import DesignSystem
import SwiftUI

/// Original compact root result: one swatch, one chosen value, and explicit format/copy controls.
struct ColorResultCard: View {
    @Bindable var model: ColorSearchModel
    let result: ColorSearchResult
    let isSelected: Bool
    let onSelect: () -> Void
    @Environment(\.commandlyLayoutDensity) private var density

    var body: some View {
        HStack(spacing: density.spacing(.sm)) {
            ColorSwatch(color: result.color).frame(width: 66, height: 66)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Color").commandlyFont(size: 12, weight: .semibold)
                        .accessibilityAddTraits(.isHeader)
                    if result.color.alpha < 1 {
                        Text("Includes transparency").commandlyFont(size: 10).foregroundStyle(.secondary)
                    }
                }
                Text(result.color.formatted(model.selectedFormat))
                    .commandlyFont(size: 13, design: .monospaced)
                    .lineLimit(2).textSelection(.enabled)
                if result.color.alpha < 1 && model.selectedFormat == .hex {
                    Text("Six-digit Hex omits transparency.")
                        .commandlyFont(size: 10).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 8) {
                Picker("Output format", selection: Binding(
                    get: { model.selectedFormat },
                    set: { format in
                        guard model.result?.id == result.id else { return }
                        onSelect()
                        model.selectedFormat = format
                    }
                )) {
                    ForEach(CommandlyColorFormat.allCases) { format in Text(format.title).tag(format) }
                }
                .labelsHidden().frame(width: 172)
                .accessibilityLabel("Color output format")
                HStack(spacing: 8) {
                    Button("Formats", systemImage: "list.bullet") {
                        onSelect()
                        model.presentActions(resultID: result.id)
                    }
                    .help("Choose a color format to copy (Command-K)")
                    Button("Copy", systemImage: "doc.on.doc") {
                        onSelect()
                        model.copy(resultID: result.id)
                    }
                    .accessibilityLabel("Copy \(model.selectedFormat.title)")
                }
                .controlSize(.small)
            }
        }
        .padding(density.spacing(.sm))
        .background(isSelected ? LauncherPalette.selection : Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .onTapGesture(perform: onSelect)
        .padding(.horizontal, density.spacing(.sm))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Color conversion result")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

extension ColorSearchModel {
    var filteredPanelActions: [LauncherActionPanelItem] {
        let needle = actionsQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        return actions.filter { needle.isEmpty || $0.title.localizedCaseInsensitiveContains(needle) }.map {
            LauncherActionPanelItem(id: $0.id, title: $0.title, systemImage: "doc.on.doc", keyHint: $0.keyHint, isEnabled: $0.isEnabled)
        }
    }
}
