import SwiftUI
import AppKit
import DesignSystem
import CommandKit

struct ClipboardHistoryView: View {
    @Bindable var viewModel: ClipboardHistoryViewModel
    @State private var lastPointerLocation: CGPoint?
    @Environment(\.commandlyLayoutDensity) private var density

    var body: some View {
        LauncherApplicationScreen(
            query: $viewModel.query,
            searchPlaceholder: viewModel.searchPlaceholder,
            searchAccessibilityIdentifier: "clipboard-history-query",
            onBack: viewModel.goBack,
            onSubmit: { viewModel.perform(BuiltInCommandActionID.copy) },
            onMoveSelection: viewModel.moveSelection,
            onEscape: {
                if viewModel.handleEscape() == false {
                    viewModel.goBack()
                }
            }
        ) {
            CommandlyOptionMenu(
                items: ClipboardHistoryFilter.allCases.map {
                    CommandlyOptionItem(id: $0.rawValue, title: $0.title)
                },
                selectionID: viewModel.filter.rawValue,
                accessibilityLabelText: "Filter by type"
            ) { item in
                if let filter = ClipboardHistoryFilter(rawValue: item.id) {
                    viewModel.filter = filter
                }
            }
        } sidebar: {
            listPane
        } detail: {
            detailPane
        }
        .accessibilityLabel("Clipboard History")
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
                LauncherApplicationEmptyState(
                    systemImage: "clipboard",
                    title: "Select an entry",
                    message: "Copy something to start building history."
                )
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
        LauncherApplicationMetadataRow(
            label: label,
            value: value,
            labelWidth: 100,
            fontSize: 12,
            truncatesValue: false
        )
    }
}
