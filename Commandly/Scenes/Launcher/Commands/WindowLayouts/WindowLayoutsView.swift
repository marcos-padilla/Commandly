import CommandKit
import DesignSystem
import SwiftUI

struct WindowLayoutsView: View {
    @Bindable var viewModel: WindowLayoutsViewModel
    @Environment(\.commandlyLayoutDensity) private var density

    var body: some View {
        LauncherApplicationScreen(
            query: $viewModel.query,
            searchPlaceholder: "Search window layouts…",
            searchAccessibilityIdentifier: "window-layouts-query",
            onBack: viewModel.goBack,
            onSubmit: { viewModel.applySelected() },
            onMoveSelection: viewModel.moveSelection,
            onEscape: {
                if viewModel.handleEscape() == false { viewModel.goBack() }
            }
        ) {
            CommandlyOptionMenu(
                items: WindowLayoutSource.allCases.map {
                    CommandlyOptionItem(id: $0.id, title: $0.title)
                },
                selectionID: viewModel.source.id,
                accessibilityLabelText: "Window layout source"
            ) { item in
                if let source = WindowLayoutSource(rawValue: item.id) {
                    viewModel.source = source
                }
            }
        } sidebar: {
            layoutList
        } detail: {
            if viewModel.isEditingCustom {
                customEditor
            } else {
                layoutDetail
            }
        }
        .accessibilityLabel("Window Layouts")
    }

    private var layoutList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: density.spacing(.xxs)) {
                if viewModel.filteredPresets.isEmpty {
                    LauncherApplicationEmptyState(
                        systemImage: "rectangle.on.rectangle.slash",
                        title: "No layouts",
                        message: viewModel.source == .custom
                            ? "Create a custom normalized window rectangle."
                            : "Try a broader search."
                    )
                    .frame(minHeight: 260)
                } else {
                    ForEach(WindowLayoutPreset.Family.allCases, id: \.self) { family in
                        let values = viewModel.filteredPresets.filter { $0.family == family }
                        if values.isEmpty == false {
                            Text(family.title.uppercased())
                                .commandlyFont(size: 9, weight: .semibold)
                                .foregroundStyle(.tertiary)
                                .tracking(0.6)
                                .padding(.horizontal, density.spacing(.sm))
                                .padding(.top, density.spacing(.sm))
                            ForEach(values) { preset in
                                LauncherApplicationRow(
                                    isSelected: preset.id == viewModel.selectedPreset?.id,
                                    onSelect: { viewModel.select(preset.id) },
                                    onOpen: { viewModel.applySelected() },
                                    onHoverChange: { hovering in
                                        if hovering { viewModel.select(preset.id) }
                                    }
                                ) {
                                    HStack(spacing: density.spacing(.sm)) {
                                        layoutGlyph(rect: preset.rect, size: CGSize(width: 30, height: 20))
                                        Text(preset.title)
                                            .commandlyFont(size: 11, weight: .medium)
                                            .lineLimit(1)
                                        Spacer()
                                    }
                                } accessory: {
                                    EmptyView()
                                }
                            }
                        }
                    }
                }
            }
            .padding(.vertical, density.spacing(.xs))
        }
    }

    private var layoutDetail: some View {
        Group {
            if let preset = viewModel.selectedPreset {
                VStack(alignment: .leading, spacing: density.spacing(.lg)) {
                    VStack(alignment: .leading, spacing: density.spacing(.xxs)) {
                        Text(preset.title)
                            .commandlyFont(size: 18, weight: .semibold)
                        Text(preset.family.title)
                            .commandlyFont(size: 10, weight: .medium)
                            .foregroundStyle(.secondary)
                    }
                    layoutGlyph(rect: preset.rect, size: CGSize(width: 330, height: 210))
                        .frame(maxWidth: .infinity)
                    HStack {
                        metadata(label: "X", value: percent(preset.rect.x))
                        metadata(label: "Y", value: percent(preset.rect.y))
                        metadata(label: "Width", value: percent(preset.rect.width))
                        metadata(label: "Height", value: percent(preset.rect.height))
                    }
                    Button("Apply to Active Window") {
                        viewModel.applySelected()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.isApplying)
                    .accessibilityHint("May request Accessibility access on first use")
                    Spacer()
                    Text("Layouts use the active display’s visible work area and never move windows between Spaces.")
                        .commandlyFont(size: 10)
                        .foregroundStyle(.tertiary)
                }
                .padding(density.spacing(.lg))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                LauncherApplicationEmptyState(
                    systemImage: "rectangle.3.group",
                    title: "Select a layout",
                    message: "Choose one of 58 native presets or create your own."
                )
            }
        }
    }

    private var customEditor: some View {
        VStack(alignment: .leading, spacing: density.spacing(.md)) {
            Text("New Custom Layout")
                .commandlyFont(size: 18, weight: .semibold)
            TextField("Layout name", text: $viewModel.customTitle)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("Custom layout name")
            layoutGlyph(rect: viewModel.customDraftRect, size: CGSize(width: 300, height: 160))
                .frame(maxWidth: .infinity)
            slider(label: "Left", value: $viewModel.customX, range: 0...0.9)
            slider(label: "Top", value: $viewModel.customY, range: 0...0.9)
            slider(label: "Width", value: $viewModel.customWidth, range: 0.1...1)
            slider(label: "Height", value: $viewModel.customHeight, range: 0.1...1)
            if viewModel.customDraftRect.isValid == false {
                Label("The rectangle must stay inside the display.", systemImage: "exclamationmark.triangle")
                    .commandlyFont(size: 10, weight: .medium)
                    .foregroundStyle(.orange)
            }
            HStack {
                Button("Cancel") { viewModel.cancelCustomEditor() }
                    .buttonStyle(.bordered)
                Button("Save Layout") { viewModel.saveCustom() }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.customDraftIsValid == false)
            }
            Spacer()
        }
        .padding(density.spacing(.lg))
    }

    private func layoutGlyph(rect: NormalizedWindowRect, size: CGSize) -> some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.primary.opacity(0.035))
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(LauncherPalette.separator, lineWidth: 1)
            RoundedRectangle(cornerRadius: 5)
                .fill(BrandPalette.accent.opacity(rect.isValid ? 0.72 : 0.25))
                .frame(width: size.width * rect.width, height: size.height * rect.height)
                .offset(x: size.width * rect.x, y: size.height * rect.y)
        }
        .frame(width: size.width, height: size.height)
        .clipped()
        .accessibilityLabel("Window occupies \(percent(rect.width)) width and \(percent(rect.height)) height")
    }

    private func metadata(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .commandlyFont(size: 9, weight: .semibold)
                .foregroundStyle(.tertiary)
            Text(value)
                .commandlyFont(size: 12, weight: .semibold, design: .monospaced)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func slider(label: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        HStack {
            Text(label)
                .commandlyFont(size: 11, weight: .semibold)
                .frame(width: 50, alignment: .leading)
            Slider(value: value, in: range, step: 0.05)
            Text(percent(value.wrappedValue))
                .commandlyFont(size: 10, design: .monospaced)
                .frame(width: 38, alignment: .trailing)
        }
    }

    private func percent(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }
}
