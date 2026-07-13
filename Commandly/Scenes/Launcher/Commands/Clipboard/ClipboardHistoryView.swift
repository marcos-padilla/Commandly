import SwiftUI
import AppKit
import DesignSystem
import CommandKit

struct ClipboardHistoryView: View {
    @Bindable var viewModel: ClipboardHistoryViewModel
    @State private var lastPointerLocation: CGPoint?
    @State private var isSearchHovered = false
    @FocusState private var isSearchFocused: Bool
    @Environment(\.commandlyLayoutDensity) private var density

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle()
                .fill(LauncherPalette.separator)
                .frame(height: 1)
            content
        }
        .onAppear {
            isSearchFocused = true
        }
        .accessibilityLabel("Clipboard History")
    }

    private var header: some View {
        HStack(spacing: density.spacing(.sm)) {
            CommandlyBackButton {
                viewModel.goBack()
            }

            HStack(spacing: density.spacing(.xs)) {
                Image(systemName: "magnifyingglass")
                    .commandlyFont(size: 13, weight: .medium)
                    .foregroundStyle(.tertiary)
                TextField(viewModel.searchPlaceholder, text: $viewModel.query)
                    .textFieldStyle(.plain)
                    .commandlyFont(size: 14, weight: .medium)
                    .focused($isSearchFocused)
                    .onSubmit {
                        viewModel.perform(BuiltInCommandActionID.copy)
                    }
                    .onKeyPress(.upArrow) {
                        viewModel.moveSelection(offset: -1)
                        return .handled
                    }
                    .onKeyPress(.downArrow) {
                        viewModel.moveSelection(offset: 1)
                        return .handled
                    }
                    .onKeyPress(.escape) {
                        if viewModel.query.isEmpty == false {
                            viewModel.query = ""
                            return .handled
                        }
                        viewModel.goBack()
                        return .handled
                    }
            }
            .padding(.horizontal, density.spacing(.sm))
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(searchFillOpacity))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.primary.opacity(searchStrokeOpacity), lineWidth: 1)
            }
            .onHover { hovering in
                isSearchHovered = hovering
            }
            .animation(.easeOut(duration: MotionDuration.fast.rawValue), value: isSearchHovered)
            .animation(.easeOut(duration: MotionDuration.fast.rawValue), value: isSearchFocused)
            .accessibilityElement(children: .contain)

            CommandlyOptionMenu(
                items: ClipboardHistoryFilter.allCases.map {
                    CommandlyOptionItem(id: $0.rawValue, title: $0.title)
                },
                selectionID: viewModel.filter.rawValue,
                accessibilityLabelText: "Filter by type",
                onSelect: { item in
                    if let filter = ClipboardHistoryFilter(rawValue: item.id) {
                        viewModel.filter = filter
                    }
                }
            )
            .zIndex(30)
        }
        .padding(.horizontal, density.spacing(.md))
        .padding(.vertical, density.spacing(.xs))
        .background(LauncherPalette.chrome)
        .zIndex(20)
    }

    private var searchFillOpacity: Double {
        if isSearchFocused { return 0.09 }
        if isSearchHovered { return 0.07 }
        return 0.05
    }

    private var searchStrokeOpacity: Double {
        if isSearchFocused { return 0.18 }
        if isSearchHovered { return 0.10 }
        return 0
    }

    private var content: some View {
        HStack(spacing: 0) {
            listPane
                .frame(width: 270)
                .layoutPriority(1)
                .background(LauncherPalette.sidebar)
                .clipped()
            Rectangle()
                .fill(LauncherPalette.separator)
                .frame(width: 1)
            detailPane
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .layoutPriority(0)
                .background(LauncherPalette.detail)
                .clipped()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var listPane: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: density.spacing(.xxs)) {
                    if viewModel.sections.isEmpty {
                        Text("No clipboard entries")
                            .commandlyFont(size: 12, weight: .medium)
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, density.spacing(.xl))
                    } else {
                        ForEach(viewModel.sections, id: \.title) { section in
                            Text(section.title.uppercased())
                                .commandlyFont(size: 10, weight: .semibold)
                                .foregroundStyle(.tertiary)
                                .tracking(0.5)
                                .padding(.horizontal, density.spacing(.sm))
                                .padding(.top, density.spacing(.sm))
                                .padding(.bottom, 2)

                            ForEach(section.entries) { entry in
                                clipboardRow(entry)
                                    .id(entry.id)
                            }
                        }
                    }
                }
                .padding(.vertical, density.spacing(.xs))
            }
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    if lastPointerLocation != location {
                        lastPointerLocation = location
                        viewModel.beginPointerInput()
                    }
                case .ended:
                    lastPointerLocation = nil
                }
            }
            .onChange(of: viewModel.selectedID) { _, newValue in
                guard let newValue, viewModel.shouldScrollToSelection else { return }
                withAnimation(.easeOut(duration: MotionDuration.fast.rawValue)) {
                    proxy.scrollTo(newValue, anchor: .center)
                }
            }
        }
    }

    private func clipboardRow(_ entry: ClipboardHistoryEntry) -> some View {
        ClipboardHistoryRow(
            entry: entry,
            isSelected: entry.id == viewModel.selectedEntry?.id,
            density: density,
            onSelect: { viewModel.select(entry.id) },
            onCopy: { viewModel.copyEntry(entry) },
            onHoverChange: { hovering in
                if hovering {
                    viewModel.setHovered(entry.id)
                } else {
                    viewModel.clearHovered(entry.id)
                }
            }
        )
    }

    private var detailPane: some View {
        Group {
            if let entry = viewModel.selectedEntry {
                VStack(alignment: .leading, spacing: 0) {
                    ScrollView {
                        preview(for: entry)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(density.spacing(.md))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    Divider().opacity(0.35)

                    information(for: entry)
                        .padding(density.spacing(.md))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: density.spacing(.xs)) {
                    Image(systemName: "clipboard")
                        .commandlyFont(size: 28, weight: .medium)
                        .foregroundStyle(.tertiary)
                    Text("Select an entry")
                        .commandlyFont(size: 13, weight: .semibold)
                    Text("Copy something to start building history.")
                        .commandlyFont(size: 11)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    @ViewBuilder
    private func preview(for entry: ClipboardHistoryEntry) -> some View {
        switch entry.contentType {
        case .text:
            Text(entry.text ?? entry.preview)
                .commandlyFont(size: 13, weight: .regular, design: .monospaced)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .image:
            liveImagePreview(tiffData: entry.imageTIFFData, analysisKey: entry.id.uuidString)
        case .fileURL:
            fileURLPreview(for: entry)
        }
    }

    @ViewBuilder
    private func fileURLPreview(for entry: ClipboardHistoryEntry) -> some View {
        VStack(alignment: .leading, spacing: density.spacing(.sm)) {
            if let imageURL = entry.firstImageFileURL {
                fileImagePreview(at: imageURL, analysisKey: "\(entry.id.uuidString)-\(imageURL.path)")
            }
            VStack(alignment: .leading, spacing: density.spacing(.xs)) {
                ForEach(entry.fileURLs, id: \.self) { url in
                    Text(url.path)
                        .commandlyFont(size: 12, weight: .medium, design: .monospaced)
                        .textSelection(.enabled)
                }
            }
        }
    }

    @ViewBuilder
    private func fileImagePreview(at url: URL, analysisKey: String) -> some View {
        if let image = NSImage(contentsOf: url) {
            constrainedLiveTextPreview(image: image, analysisKey: analysisKey)
        } else {
            Text("Image preview unavailable")
                .commandlyFont(size: 12)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func liveImagePreview(tiffData: Data?, analysisKey: String) -> some View {
        if let data = tiffData, let image = NSImage(data: data) {
            constrainedLiveTextPreview(image: image, analysisKey: analysisKey)
        } else {
            Text("Image preview unavailable")
                .commandlyFont(size: 12)
                .foregroundStyle(.secondary)
        }
    }

    /// Fixed-height preview so large screenshots cannot expand the detail pane.
    private func constrainedLiveTextPreview(image: NSImage, analysisKey: String) -> some View {
        ClipboardLiveTextImageView(image: image, analysisKey: analysisKey)
            .frame(maxWidth: .infinity)
            .frame(height: 220)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.md.rawValue, style: .continuous))
            .accessibilityLabel("Image preview")
    }

    private func information(for entry: ClipboardHistoryEntry) -> some View {
        VStack(alignment: .leading, spacing: density.spacing(.sm)) {
            Text("Information")
                .commandlyFont(size: 11, weight: .semibold)
                .foregroundStyle(.secondary)

            infoRow(label: "Source", value: entry.sourceAppName ?? "Unknown")
            infoRow(label: "Content type", value: entry.contentType.title)
            if entry.contentType == .text {
                infoRow(label: "Characters", value: "\(entry.characterCount)")
                infoRow(label: "Words", value: "\(entry.wordCount)")
            }
            if entry.enrichmentStatus == .pending {
                infoRow(label: "Search index", value: "Indexing for search…")
            } else if entry.enrichmentStatus == .ready {
                infoRow(label: "Search index", value: enrichmentReadySummary(for: entry))
            } else if entry.enrichmentStatus == .failed {
                infoRow(label: "Search index", value: "Unavailable")
            } else if entry.enrichmentStatus == .skipped, entry.contentType != .text {
                infoRow(label: "Search index", value: "Filename only")
            }
            if entry.classificationLabels.isEmpty == false {
                infoRow(
                    label: "Labels",
                    value: entry.classificationLabels.prefix(6).joined(separator: ", ")
                )
            }
            infoRow(label: "Copied", value: viewModel.copiedLabel(for: entry))
        }
    }

    private func enrichmentReadySummary(for entry: ClipboardHistoryEntry) -> String {
        var parts: [String] = []
        if let text = entry.searchableText, text.isEmpty == false {
            parts.append("Text indexed")
        }
        if entry.classificationLabels.isEmpty == false {
            parts.append("\(entry.classificationLabels.count) labels")
        }
        return parts.isEmpty ? "Ready" : parts.joined(separator: " · ")
    }

    private func infoRow(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .commandlyFont(size: 12, weight: .medium)
                .foregroundStyle(.secondary)
                .frame(width: 100, alignment: .leading)
            Text(value)
                .commandlyFont(size: 12, weight: .medium)
                .foregroundStyle(.primary)
            Spacer(minLength: 0)
        }
    }
}

/// Sidebar row with hover Copy control. Copy sits outside the selection control
/// so clicking it does not also trigger row selection.
private struct ClipboardHistoryRow: View {
    let entry: ClipboardHistoryEntry
    let isSelected: Bool
    let density: CommandlyLayoutDensity
    let onSelect: () -> Void
    let onCopy: () -> Void
    let onHoverChange: (Bool) -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: density.spacing(.sm)) {
            Button(action: onSelect) {
                HStack(spacing: density.spacing(.sm)) {
                    LauncherGlyph(
                        systemName: artwork.symbolName,
                        tone: artwork.tone,
                        isSelected: isSelected,
                        size: density.iconSize
                    )

                    Text(entry.preview)
                        .commandlyFont(size: 12, weight: .medium)
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isHovered {
                ClipboardHistoryCopyButton(onCopy: onCopy)
            }
        }
        .padding(.horizontal, density.spacing(.sm))
        .padding(.vertical, density.rowVerticalPadding)
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.md.rawValue, style: .continuous)
                .fill(isSelected ? LauncherPalette.selection : Color.clear)
        )
        .overlay {
            RoundedRectangle(cornerRadius: CornerRadius.md.rawValue, style: .continuous)
                .strokeBorder(isSelected ? LauncherPalette.separator : Color.clear, lineWidth: 1)
        }
        .padding(.horizontal, density.spacing(.xs))
        .onHover { hovering in
            isHovered = hovering
            onHoverChange(hovering)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(entry.preview)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityAction(named: "Copy", onCopy)
    }

    private var artwork: LauncherFileArtwork {
        switch entry.contentType {
        case .text:
            return .text
        case .image:
            return .image
        case .fileURL:
            guard let url = entry.fileURLs.first else { return .generic }
            return LauncherFileArtwork(fileURL: url)
        }
    }
}

/// Compact row Copy control with hover chrome and a brief success morph.
private struct ClipboardHistoryCopyButton: View {
    let onCopy: () -> Void

    @State private var isHovered = false
    @State private var isPressed = false
    @State private var didSucceed = false
    @State private var successToken = 0

    var body: some View {
        Button {
            onCopy()
            successToken += 1
        } label: {
            HStack(spacing: 4) {
                Image(systemName: didSucceed ? "checkmark" : "doc.on.doc")
                    .commandlyFont(size: 10, weight: .semibold)
                    .contentTransition(.symbolEffect(.replace))
                    .symbolEffect(.bounce, value: didSucceed)

                Text(didSucceed ? "Copied" : "Copy")
                    .commandlyFont(size: 11, weight: .semibold)
                    .contentTransition(.opacity)
            }
            .foregroundStyle(labelColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(fillColor)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(
                        BrandPalette.accent.opacity(isHovered || didSucceed ? 0.28 : 0),
                        lineWidth: 1
                    )
            }
            .scaleEffect(isPressed ? 0.96 : (isHovered || didSucceed ? 1.04 : 1))
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.28, dampingFraction: 0.72), value: isHovered)
        .animation(CopySuccessFeedback.succeedSpring, value: didSucceed)
        .animation(.easeOut(duration: MotionDuration.fast.rawValue), value: isPressed)
        .onHover { hovering in
            isHovered = hovering
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
        .task(id: successToken) {
            await CopySuccessFeedback.runMorph(token: successToken, didSucceed: $didSucceed)
        }
        .accessibilityLabel(didSucceed ? "Copied" : "Copy")
    }

    private var labelColor: Color {
        if didSucceed { return BrandPalette.accentSoft }
        return isHovered ? Color.primary : Color.secondary
    }

    private var fillColor: Color {
        if didSucceed { return BrandPalette.accent.opacity(0.22) }
        if isHovered { return BrandPalette.accent.opacity(0.14) }
        return Color.primary.opacity(0.08)
    }
}
