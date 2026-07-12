import AppKit
import CommandKit
import DesignSystem
import QuickLookUI
import SearchKit
import SwiftUI

struct FileSearchView: View {
    @Bindable var viewModel: FileSearchViewModel
    @FocusState private var isSearchFocused: Bool
    @Environment(\.commandlyLayoutDensity) private var density

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.35)
            content
        }
        .onAppear {
            isSearchFocused = true
            viewModel.load()
        }
        .onDisappear {
            viewModel.stop()
        }
        .overlay {
            if viewModel.showsActionPanel {
                ZStack(alignment: .bottomTrailing) {
                    Color.black.opacity(0.001)
                        .contentShape(Rectangle())
                        .onTapGesture { viewModel.dismissActionPanel() }

                    LauncherActionPanel(
                        title: viewModel.actionPanelTitle,
                        actions: viewModel.filteredActionPanelItems,
                        query: $viewModel.actionQuery,
                        onSelect: { viewModel.performPanelAction($0) },
                        onDismiss: { viewModel.dismissActionPanel() },
                        onBack: { viewModel.actionPanelBack() }
                    )
                    .padding(.trailing, density.spacing(.md))
                    .padding(.bottom, density.spacing(.md))
                    .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .bottomTrailing)))
                }
            }
        }
        .animation(.easeInOut(duration: MotionDuration.fast.rawValue), value: viewModel.showsActionPanel)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("File Search")
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
                    .onSubmit { viewModel.perform(primaryActionID) }
                    .onKeyPress(.upArrow) {
                        viewModel.moveSelection(offset: -1)
                        return .handled
                    }
                    .onKeyPress(.downArrow) {
                        viewModel.moveSelection(offset: 1)
                        return .handled
                    }
                    .onKeyPress(.escape) {
                        if viewModel.showsActionPanel {
                            viewModel.actionPanelBack()
                        } else if viewModel.query.isEmpty == false {
                            viewModel.query = ""
                        } else {
                            viewModel.goBack()
                        }
                        return .handled
                    }
            }
            .padding(.horizontal, density.spacing(.sm))
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.md.rawValue, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
            )
            .overlay {
                RoundedRectangle(cornerRadius: CornerRadius.md.rawValue, style: .continuous)
                    .strokeBorder(Color.primary.opacity(isSearchFocused ? 0.18 : 0.08), lineWidth: 1)
            }

            CommandlyOptionMenu(
                items: FileSearchCategory.allCases.map {
                    CommandlyOptionItem(id: $0.id, title: $0.title)
                },
                selectionID: viewModel.category.id,
                accessibilityLabelText: "Filter file types",
                onSelect: { item in
                    if let category = FileSearchCategory(rawValue: item.id) {
                        viewModel.category = category
                    }
                }
            )
            .zIndex(30)
        }
        .padding(.horizontal, density.spacing(.md))
        .padding(.vertical, density.spacing(.sm))
        .zIndex(20)
    }

    private var primaryActionID: CommandActionID {
        viewModel.loadState == .needsFolderAccess
            ? BuiltInCommandActionID.settings
            : BuiltInCommandActionID.openFile
    }

    private var content: some View {
        HStack(spacing: 0) {
            resultsPane
                .frame(width: 280)
                .layoutPriority(1)
                .clipped()
            Divider().opacity(0.35)
            detailPane
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var resultsPane: some View {
        switch viewModel.loadState {
        case .idle where viewModel.results.isEmpty, .loading where viewModel.results.isEmpty:
            VStack(spacing: density.spacing(.xs)) {
                ProgressView()
                    .controlSize(.small)
                Text("Searching your index…")
                    .commandlyFont(size: 11, weight: .medium)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .needsFolderAccess:
            FileSearchEmptyState(
                systemImage: "folder.badge.questionmark",
                title: "Choose folders to search",
                message: "Choose folders Commandly may search and manage."
            )
        case .failed:
            FileSearchEmptyState(
                systemImage: "exclamationmark.magnifyingglass",
                title: "Search unavailable",
                message: "Check Spotlight and try again."
            )
        default:
            if viewModel.results.isEmpty {
                FileSearchEmptyState(
                    systemImage: "doc.text.magnifyingglass",
                    title: "No files found",
                    message: "Try another name, phrase, or filter."
                )
            } else {
                resultList
            }
        }
    }

    private var resultList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: density.spacing(.xxs)) {
                    Text(viewModel.sectionTitle.uppercased())
                        .commandlyFont(size: 10, weight: .semibold)
                        .foregroundStyle(.tertiary)
                        .tracking(0.5)
                        .padding(.horizontal, density.spacing(.sm))
                        .padding(.top, density.spacing(.sm))

                    ForEach(viewModel.results) { item in
                        FileSearchResultRow(
                            item: item,
                            isSelected: viewModel.selectedItem?.id == item.id,
                            density: density,
                            onSelect: { viewModel.select(item.id) },
                            onOpen: {
                                viewModel.select(item.id)
                                viewModel.perform(BuiltInCommandActionID.openFile)
                            },
                            onShowActions: { viewModel.presentActions(for: item.id) }
                        )
                        .id(item.id)
                    }
                }
                .padding(.bottom, density.spacing(.xs))
            }
            .onChange(of: viewModel.selectedID) { _, id in
                guard let id, viewModel.shouldScrollToSelection else { return }
                withAnimation(.easeOut(duration: MotionDuration.fast.rawValue)) {
                    proxy.scrollTo(id, anchor: .center)
                }
            }
        }
    }

    @ViewBuilder
    private var detailPane: some View {
        if let item = viewModel.selectedItem {
            VStack(alignment: .leading, spacing: 0) {
                FileSearchPreview(item: item)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(density.spacing(.md))

                if viewModel.showsDetails {
                    Divider().opacity(0.35)

                    VStack(alignment: .leading, spacing: density.spacing(.xs)) {
                        Text("METADATA")
                            .commandlyFont(size: 10, weight: .semibold)
                            .foregroundStyle(.tertiary)
                            .tracking(0.5)
                        metadataRow("Name", item.name)
                        metadataRow("Where", abbreviatedPath(item.parentPath))
                        metadataRow("Type", item.contentTypeDescription)
                        if let byteCount = item.byteCount, item.kind == .file {
                            metadataRow("Size", ByteCountFormatter.string(fromByteCount: byteCount, countStyle: .file))
                        }
                        if let createdAt = item.createdAt {
                            metadataRow("Created", createdAt.formatted(date: .abbreviated, time: .shortened))
                        }
                        if let modifiedAt = item.modifiedAt {
                            metadataRow("Modified", modifiedAt.formatted(date: .abbreviated, time: .shortened))
                        }
                        if item.matchKind == .contents {
                            metadataRow("Matched", "File contents")
                        }
                    }
                    .padding(density.spacing(.md))
                }
            }
        } else {
            FileSearchEmptyState(
                systemImage: "doc",
                title: "Select a file",
                message: "Its preview and metadata will appear here."
            )
        }
    }

    private func metadataRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: density.spacing(.sm)) {
            Text(label)
                .commandlyFont(size: 11, weight: .semibold)
                .foregroundStyle(.secondary)
                .frame(width: 62, alignment: .leading)
            Text(value)
                .commandlyFont(size: 11, weight: .medium)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
    }

    private func abbreviatedPath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        guard path == home || path.hasPrefix("\(home)/") else { return path }
        return "~" + path.dropFirst(home.count)
    }
}

private struct FileSearchResultRow: View {
    let item: FileSearchItem
    let isSelected: Bool
    let density: CommandlyLayoutDensity
    let onSelect: () -> Void
    let onOpen: () -> Void
    let onShowActions: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: density.spacing(.sm)) {
                Image(systemName: itemSystemImage)
                    .commandlyFont(size: 13, weight: .semibold)
                    .foregroundStyle(isSelected ? Color.white : BrandPalette.accentSoft)
                    .frame(width: 25, height: 25)
                    .background(
                        RoundedRectangle(cornerRadius: CornerRadius.sm.rawValue, style: .continuous)
                            .fill(isSelected ? BrandPalette.accent : BrandPalette.accent.opacity(0.16))
                    )
                Text(item.name)
                    .commandlyFont(size: 12, weight: .medium)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .simultaneousGesture(TapGesture(count: 2).onEnded(onOpen))
        .padding(.horizontal, density.spacing(.sm))
        .padding(.vertical, density.rowVerticalPadding)
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.md.rawValue, style: .continuous)
                .fill(isSelected ? BrandPalette.accent.opacity(0.18) : Color.clear)
        )
        .padding(.horizontal, density.spacing(.xs))
        .background {
            LauncherRightClickCatcher(onRightClick: onShowActions)
        }
        .onHover { hovering in
            if hovering { onSelect() }
        }
        .accessibilityLabel("\(item.name), \(item.contentTypeDescription)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityAction(named: "Open", onOpen)
        .accessibilityAction(named: "Show Actions", onShowActions)
    }

    private var itemSystemImage: String {
        if item.kind == .folder { return "folder.fill" }
        guard let identifier = item.contentTypeIdentifier else { return "doc.fill" }
        if identifier.contains("image") { return "photo.fill" }
        if identifier.contains("audio") { return "waveform" }
        if identifier.contains("movie") || identifier.contains("video") { return "film.fill" }
        if identifier.contains("archive") || identifier.contains("zip") { return "archivebox.fill" }
        if identifier.contains("source") || identifier.contains("script") { return "chevron.left.forwardslash.chevron.right" }
        return "doc.fill"
    }
}

private struct FileSearchPreview: View {
    let item: FileSearchItem

    var body: some View {
        if item.kind == .folder {
            VStack(spacing: Spacing.sm.rawValue) {
                Image(systemName: "folder.fill")
                    .commandlyFont(size: 54, weight: .medium)
                    .foregroundStyle(BrandPalette.accentSoft)
                Text(item.name)
                    .commandlyFont(size: 13, weight: .semibold)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            if isCSV {
                CSVFilePreview(item: item)
            } else {
                QuickLookPreview(url: item.url)
                    .clipShape(RoundedRectangle(cornerRadius: CornerRadius.md.rawValue, style: .continuous))
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Preview of \(item.name)")
            }
        }
    }

    private var isCSV: Bool {
        item.url.pathExtension.lowercased() == "csv"
            || item.contentTypeIdentifier == "public.comma-separated-values-text"
    }
}

private struct CSVFilePreview: View {
    private enum LoadState: Equatable {
        case loading
        case loaded(CSVPreviewContent)
        case failed
    }

    let item: FileSearchItem
    @State private var state: LoadState = .loading

    var body: some View {
        Group {
            switch state {
            case .loading:
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case let .loaded(content):
                CSVTablePreview(content: content)
            case .failed:
                VStack(spacing: Spacing.xs.rawValue) {
                    Image(systemName: "tablecells.badge.ellipsis")
                        .commandlyFont(size: 28, weight: .medium)
                        .foregroundStyle(.tertiary)
                    Text("Preview unavailable")
                        .commandlyFont(size: 11, weight: .semibold)
                    Text("The CSV could not be read from its authorized folder.")
                        .commandlyFont(size: 10, weight: .regular)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: item.url) {
            state = .loading
            do {
                state = .loaded(try await CSVPreviewLoader.load(url: item.url))
            } catch is CancellationError {
                return
            } catch {
                state = .failed
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("CSV preview of \(item.name)")
    }
}

private struct CSVTablePreview: View {
    let content: CSVPreviewContent
    private let columnWidth: CGFloat = 132
    private let rowHeight: CGFloat = 28

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView([.horizontal, .vertical]) {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                    Section {
                        ForEach(Array(content.rows.enumerated()), id: \.offset) { index, row in
                            tableRow(row, isHeader: false)
                                .background(index.isMultiple(of: 2) ? Color.clear : Color.primary.opacity(0.025))
                        }
                    } header: {
                        tableRow(content.headers, isHeader: true)
                            .background(.background)
                    }
                }
            }
            if content.isTruncated {
                Text("Showing a preview of this CSV")
                    .commandlyFont(size: 9, weight: .medium)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, Spacing.xs.rawValue)
                    .padding(.vertical, 6)
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.md.rawValue, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: CornerRadius.md.rawValue, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
        }
    }

    private func tableRow(_ values: [String], isHeader: Bool) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(values.enumerated()), id: \.offset) { _, value in
                Text(value.isEmpty ? "—" : value)
                    .font(.system(size: 9, weight: isHeader ? .semibold : .regular))
                    .foregroundStyle(isHeader ? .primary : .secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(width: columnWidth, height: rowHeight, alignment: .leading)
                    .padding(.horizontal, 7)
                    .overlay(alignment: .trailing) {
                        Divider().opacity(0.35)
                    }
            }
        }
        .overlay(alignment: .bottom) {
            Divider().opacity(0.35)
        }
    }
}

private struct QuickLookPreview: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        if let preview = QLPreviewView(frame: .zero, style: .normal) {
            preview.autostarts = true
            preview.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(preview)
            NSLayoutConstraint.activate([
                preview.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                preview.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                preview.topAnchor.constraint(equalTo: container.topAnchor),
                preview.bottomAnchor.constraint(equalTo: container.bottomAnchor)
            ])
        }
        return container
    }

    func updateNSView(_ view: NSView, context: Context) {
        (view.subviews.first { $0 is QLPreviewView } as? QLPreviewView)?.previewItem = url as NSURL
    }
}

private struct FileSearchEmptyState: View {
    let systemImage: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: Spacing.xs.rawValue) {
            Image(systemName: systemImage)
                .commandlyFont(size: 25, weight: .medium)
                .foregroundStyle(.tertiary)
            Text(title)
                .commandlyFont(size: 12, weight: .semibold)
            Text(message)
                .commandlyFont(size: 10, weight: .regular)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 220)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Spacing.md.rawValue)
        .accessibilityElement(children: .combine)
    }
}
