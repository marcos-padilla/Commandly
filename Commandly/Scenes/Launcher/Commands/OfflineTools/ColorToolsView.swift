import CommandKit
import DesignSystem
import SwiftUI

struct ColorToolsView: View {
    @Bindable var viewModel: OfflineToolsViewModel
    @FocusState private var isInputFocused: Bool
    @Environment(\.commandlyLayoutDensity) private var density

    var body: some View {
        VStack(alignment: .leading, spacing: density.spacing(.sm)) {
            HStack(spacing: density.spacing(.sm)) {
                TextField("#966A5E, rgb(…), or hsl(…)", text: $viewModel.colorInput)
                    .textFieldStyle(.roundedBorder)
                    .commandlyFont(size: 13, design: .monospaced)
                    .focused($isInputFocused)
                    .onSubmit { viewModel.perform(BuiltInCommandActionID.copy) }
                    .onExitCommand {
                        if viewModel.showsActionsMenu { viewModel.showsActionsMenu = false }
                        else { viewModel.goBack() }
                    }
                    .accessibilityLabel("Color value")
                    .accessibilityHint("Enter a hexadecimal, RGB, or HSL color. Return copies the selected output format.")
                Button("Pick from Screen", systemImage: "eyedropper") { viewModel.sampleColor() }
                    .controlSize(.small)
            }
            if let color = viewModel.parsedColor {
                HStack(spacing: density.spacing(.sm)) {
                    ColorSwatch(color: color).frame(width: 54, height: 54)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Choose an output format").commandlyFont(size: 12, weight: .semibold)
                            .accessibilityAddTraits(.isHeader)
                        Text(color.alpha < 1 ? "Transparency is preserved except in six-digit Hex." : "Copy any value, or choose a format for Return.")
                            .commandlyFont(size: 11).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    Picker("Return copies", selection: $viewModel.selectedColorFormat) {
                        ForEach(CommandlyColorFormat.allCases) { format in
                            Text(format.title).tag(format)
                        }
                    }
                    .labelsHidden().frame(width: 165)
                    .accessibilityLabel("Output format for Return")
                }
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(CommandlyColorFormat.allCases) { format in
                            Button { viewModel.perform(format.copyActionID) } label: {
                                HStack(spacing: 10) {
                                    Text(format.title).commandlyFont(size: 11, weight: .medium).frame(width: 130, alignment: .leading)
                                    Text(color.formatted(format)).commandlyFont(size: 11, design: .monospaced)
                                        .lineLimit(1).minimumScaleFactor(0.75)
                                    Spacer(minLength: 0)
                                    Image(systemName: "doc.on.doc").foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, minHeight: 29, alignment: .leading)
                                .padding(.horizontal, 8)
                                .background(viewModel.selectedColorFormat == format ? LauncherPalette.selection : Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 6))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .keyboardShortcut(KeyEquivalent(Character(format.shortcutNumber)), modifiers: .command)
                            .accessibilityLabel("Copy \(format.title)")
                            .accessibilityValue(color.formatted(format))
                            .help("Copy \(format.title) (Command-\(format.shortcutNumber))")
                        }
                    }
                }
            } else {
                LauncherApplicationEmptyState(
                    systemImage: "paintpalette",
                    title: "Enter a color",
                    message: "Use #RGB, #RGBA, #RRGGBB, #RRGGBBAA, rgb(255 0 0 / 50%), or hsl(120deg 100% 50%)."
                )
            }
            Text("Conversions stay on this Mac. Copying updates your clipboard.")
                .commandlyFont(size: 10).foregroundStyle(.secondary)
        }
        .padding(density.spacing(.md))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Color conversions")
        .onAppear { DispatchQueue.main.async { isInputFocused = true } }
    }
}
