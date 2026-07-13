import CommandKit
import DesignSystem
import SwiftUI

struct OfflineToolsView: View {
    @Bindable var viewModel: OfflineToolsViewModel
    @Environment(\.commandlyLayoutDensity) private var density

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle()
                .fill(LauncherPalette.separator)
                .frame(height: 1)
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(LauncherPalette.detail)
        }
        .accessibilityLabel(viewModel.tool.title)
    }

    private var header: some View {
        HStack(spacing: density.spacing(.sm)) {
            CommandlyBackButton(action: viewModel.goBack)
            Image(systemName: viewModel.tool.systemImage)
                .commandlyFont(size: 14, weight: .semibold)
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 24)
                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 7))
            VStack(alignment: .leading, spacing: 1) {
                Text(viewModel.tool.title)
                    .commandlyFont(size: 13, weight: .semibold)
                Text(viewModel.tool.subtitle)
                    .commandlyFont(size: 9)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, density.spacing(.md))
        .padding(.vertical, density.spacing(.xs))
        .background(LauncherPalette.chrome)
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.tool {
        case .emoji:
            emojiTool
        case .textCase:
            textCaseTool
        case .color:
            colorTool
        case .dictionary:
            dictionaryTool
        case .fonts:
            fontTool
        case .typing:
            typingTool
        }
    }

    private var emojiTool: some View {
        VStack(spacing: 0) {
            searchField(
                placeholder: "Search emoji names…",
                submit: { viewModel.perform(BuiltInCommandActionID.copy) }
            )
            Divider().opacity(0.35)
            if viewModel.filteredEmoji.isEmpty {
                LauncherApplicationEmptyState(
                    systemImage: "face.dashed",
                    title: "No matching emoji",
                    message: "Try a broader English name such as heart, hand, or sun."
                )
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVGrid(
                            columns: [GridItem(.adaptive(minimum: 64), spacing: density.spacing(.xs))],
                            spacing: density.spacing(.xs)
                        ) {
                            ForEach(viewModel.filteredEmoji) { emoji in
                                Button {
                                    viewModel.selectEmoji(emoji.id)
                                } label: {
                                    VStack(spacing: 4) {
                                        Text(emoji.symbol)
                                            .font(.system(size: 27))
                                        Text(emoji.name)
                                            .commandlyFont(size: 8, weight: .medium)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                    .frame(maxWidth: .infinity, minHeight: 54)
                                    .padding(4)
                                    .background(
                                        emoji.id == viewModel.selectedEmoji?.id
                                            ? LauncherPalette.selection
                                            : Color.primary.opacity(0.025),
                                        in: RoundedRectangle(cornerRadius: CornerRadius.md.rawValue)
                                    )
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(emoji.name)
                                .accessibilityValue(emoji.symbol)
                                .id(emoji.id)
                            }
                        }
                        .padding(density.spacing(.sm))
                    }
                    .onChange(of: viewModel.selectedEmojiID) { _, id in
                        guard let id, viewModel.shouldScrollToSelection else { return }
                        withAnimation(.easeOut(duration: MotionDuration.fast.rawValue)) {
                            proxy.scrollTo(id, anchor: .center)
                        }
                    }
                }
            }
        }
    }

    private var textCaseTool: some View {
        VStack(alignment: .leading, spacing: density.spacing(.sm)) {
            Picker("Text style", selection: $viewModel.textCaseStyle) {
                ForEach(TextCaseStyle.allCases) { style in
                    Text(style.title).tag(style)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("Text case style")

            HStack(spacing: density.spacing(.sm)) {
                editorCard(title: "Input") {
                    TextEditor(text: $viewModel.textInput)
                        .commandlyFont(size: 13, design: .monospaced)
                        .scrollContentBackground(.hidden)
                        .accessibilityLabel("Text to convert")
                }
                editorCard(title: "Converted") {
                    ScrollView {
                        Text(viewModel.textOutput.isEmpty ? "Converted text appears here." : viewModel.textOutput)
                            .commandlyFont(size: 13, design: .monospaced)
                            .foregroundStyle(viewModel.textOutput.isEmpty ? .secondary : .primary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .accessibilityLabel("Converted text")
                }
            }
        }
        .padding(density.spacing(.md))
    }

    private var colorTool: some View {
        VStack(alignment: .leading, spacing: density.spacing(.md)) {
            HStack(spacing: density.spacing(.sm)) {
                TextField("#RRGGBB or rgb(…)", text: $viewModel.colorInput)
                    .textFieldStyle(.roundedBorder)
                    .commandlyFont(size: 13, design: .monospaced)
                    .accessibilityLabel("Color value")
                Button("Pick from Screen") {
                    viewModel.sampleColor()
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Pick a color from the screen")
            }

            if let color = viewModel.parsedColor {
                HStack(alignment: .top, spacing: density.spacing(.lg)) {
                    RoundedRectangle(cornerRadius: CornerRadius.lg.rawValue, style: .continuous)
                        .fill(Color(nsColor: color.nsColor))
                        .frame(width: 150, height: 150)
                        .overlay {
                            RoundedRectangle(cornerRadius: CornerRadius.lg.rawValue, style: .continuous)
                                .strokeBorder(LauncherPalette.separator, lineWidth: 1)
                        }
                        .accessibilityLabel("Color preview")
                        .accessibilityValue(color.hex)

                    VStack(spacing: density.spacing(.sm)) {
                        colorValueRow(label: "HEX", value: color.hex) {
                            viewModel.perform(BuiltInCommandActionID.copy)
                        }
                        colorValueRow(label: "RGB", value: color.rgb) {
                            viewModel.perform(OfflineToolsActionID.copyRGB)
                        }
                        colorValueRow(label: "HSL", value: color.hsl) {
                            viewModel.perform(OfflineToolsActionID.copyHSL)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                Spacer()
                Text("All conversion happens on this Mac.")
                    .commandlyFont(size: 10)
                    .foregroundStyle(.tertiary)
            } else {
                LauncherApplicationEmptyState(
                    systemImage: "paintpalette",
                    title: "Enter a valid color",
                    message: "Supported forms: #RGB, #RGBA, #RRGGBB, #RRGGBBAA, rgb(), and rgba()."
                )
            }
        }
        .padding(density.spacing(.lg))
    }

    private var dictionaryTool: some View {
        VStack(spacing: 0) {
            searchField(placeholder: "Enter a word…", submit: viewModel.lookupDefinition)
            Divider().opacity(0.35)
            Group {
                if viewModel.isLookingUpDefinition {
                    ProgressView("Looking in macOS dictionaries…")
                        .commandlyFont(size: 12)
                } else if let definition = viewModel.dictionaryDefinition {
                    ScrollView {
                        Text(definition)
                            .commandlyFont(size: 14)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(density.spacing(.lg))
                    }
                } else {
                    LauncherApplicationEmptyState(
                        systemImage: "character.book.closed",
                        title: "Look up a word",
                        message: "Definitions come from dictionaries installed in macOS."
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var fontTool: some View {
        VStack(spacing: 0) {
            searchField(
                placeholder: "Search installed font families…",
                submit: { viewModel.perform(BuiltInCommandActionID.copy) }
            )
            Divider().opacity(0.35)
            HStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: density.spacing(.xxs)) {
                            ForEach(viewModel.filteredFonts, id: \.self) { family in
                                LauncherApplicationRow(
                                    isSelected: family == viewModel.selectedFontFamily,
                                    onSelect: { viewModel.selectFont(family) },
                                    onOpen: { viewModel.perform(BuiltInCommandActionID.copy) },
                                    onHoverChange: { hovering in
                                        if hovering { viewModel.selectFont(family) }
                                    }
                                ) {
                                    Text(family)
                                        .font(.custom(family, fixedSize: 13))
                                        .lineLimit(1)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                } accessory: {
                                    EmptyView()
                                }
                                .id(family)
                            }
                        }
                        .padding(.vertical, density.spacing(.xs))
                    }
                    .onChange(of: viewModel.selectedFontFamily) { _, family in
                        guard let family, viewModel.shouldScrollToSelection else { return }
                        withAnimation(.easeOut(duration: MotionDuration.fast.rawValue)) {
                            proxy.scrollTo(family, anchor: .center)
                        }
                    }
                }
                .frame(width: 270)
                .background(LauncherPalette.sidebar)

                Divider().opacity(0.35)

                if let family = viewModel.selectedFontFamily {
                    VStack(alignment: .leading, spacing: density.spacing(.lg)) {
                        Text(family)
                            .commandlyFont(size: 12, weight: .semibold)
                            .foregroundStyle(.secondary)
                        Text("Sphinx of black quartz, judge my vow.")
                            .font(.custom(family, fixedSize: 34))
                            .lineLimit(3)
                            .minimumScaleFactor(0.6)
                        Text("ABCDEFGHIJKLMNOPQRSTUVWXYZ\nabcdefghijklmnopqrstuvwxyz\n0123456789")
                            .font(.custom(family, fixedSize: 16))
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(density.spacing(.lg))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            }
        }
    }

    private var typingTool: some View {
        VStack(alignment: .leading, spacing: density.spacing(.md)) {
            HStack {
                metric(title: "Speed", value: "\(viewModel.typingResult.wordsPerMinute) WPM")
                metric(title: "Accuracy", value: "\(viewModel.typingResult.accuracyPercent)%")
                Spacer()
                Button("New Attempt") { viewModel.resetTyping() }
                    .buttonStyle(.bordered)
            }

            VStack(alignment: .leading, spacing: density.spacing(.xs)) {
                Text("COPY THIS PASSAGE")
                    .commandlyFont(size: 9, weight: .semibold)
                    .foregroundStyle(.tertiary)
                    .tracking(0.6)
                Text(TypingPracticeEngine.prompt)
                    .commandlyFont(size: 18, weight: .medium, design: .rounded)
                    .lineSpacing(5)
                    .textSelection(.disabled)
                    .accessibilityLabel("Typing practice passage")
            }
            .padding(density.spacing(.md))
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: CornerRadius.lg.rawValue))

            TextEditor(text: $viewModel.typingText)
                .commandlyFont(size: 16, design: .monospaced)
                .scrollContentBackground(.hidden)
                .padding(density.spacing(.sm))
                .background(Color.primary.opacity(0.055))
                .clipShape(RoundedRectangle(cornerRadius: CornerRadius.lg.rawValue))
                .overlay {
                    RoundedRectangle(cornerRadius: CornerRadius.lg.rawValue)
                        .strokeBorder(LauncherPalette.separator, lineWidth: 1)
                }
                .accessibilityLabel("Type the practice passage")
        }
        .padding(density.spacing(.lg))
    }

    private func searchField(placeholder: String, submit: @escaping () -> Void) -> some View {
        HStack(spacing: density.spacing(.xs)) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.tertiary)
            TextField(placeholder, text: $viewModel.query)
                .textFieldStyle(.plain)
                .commandlyFont(size: 14, weight: .medium)
                .onSubmit(submit)
                .onKeyPress(.upArrow) {
                    viewModel.moveSelection(offset: -1)
                    return .handled
                }
                .onKeyPress(.downArrow) {
                    viewModel.moveSelection(offset: 1)
                    return .handled
                }
        }
        .padding(.horizontal, density.spacing(.md))
        .padding(.vertical, 10)
        .background(LauncherPalette.chrome)
    }

    private func editorCard<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: density.spacing(.xs)) {
            Text(title.uppercased())
                .commandlyFont(size: 9, weight: .semibold)
                .foregroundStyle(.tertiary)
                .tracking(0.6)
            content()
                .padding(density.spacing(.sm))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(Color.primary.opacity(0.045))
                .clipShape(RoundedRectangle(cornerRadius: CornerRadius.md.rawValue))
                .overlay {
                    RoundedRectangle(cornerRadius: CornerRadius.md.rawValue)
                        .strokeBorder(LauncherPalette.separator, lineWidth: 1)
                }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func colorValueRow(
        label: String,
        value: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack {
                Text(label)
                    .commandlyFont(size: 10, weight: .semibold)
                    .foregroundStyle(.secondary)
                    .frame(width: 36, alignment: .leading)
                Text(value)
                    .commandlyFont(size: 13, design: .monospaced)
                    .textSelection(.enabled)
                Spacer()
                Image(systemName: "doc.on.doc")
                    .foregroundStyle(.tertiary)
            }
            .padding(density.spacing(.sm))
            .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: CornerRadius.md.rawValue))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Copy \(label) color")
        .accessibilityValue(value)
    }

    private func metric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .commandlyFont(size: 9, weight: .semibold)
                .foregroundStyle(.tertiary)
            Text(value)
                .commandlyFont(size: 15, weight: .semibold)
        }
        .padding(.horizontal, density.spacing(.sm))
        .padding(.vertical, density.spacing(.xs))
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: CornerRadius.md.rawValue))
        .accessibilityElement(children: .combine)
    }
}
