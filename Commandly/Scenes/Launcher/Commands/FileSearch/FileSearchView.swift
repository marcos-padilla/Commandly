import CommandKit
import DesignSystem
import Foundation
import SearchKit
import SwiftUI

struct FileSearchView: View {
    @Bindable var viewModel: FileSearchViewModel
    @Environment(\.commandlyLayoutDensity) private var density

    var body: some View {
        LauncherApplicationScreen(
            query: $viewModel.query,
            searchPlaceholder: viewModel.searchPlaceholder,
            searchAccessibilityIdentifier: "file-search-query",
            onBack: viewModel.goBack,
            onSubmit: { viewModel.perform(primaryActionID) },
            onMoveSelection: viewModel.moveSelection,
            onEscape: {
                if viewModel.handleEscape() == false {
                    viewModel.goBack()
                }
            }
        ) {
            CommandlyOptionMenu(
                items: FileSearchCategory.allCases.map {
                    CommandlyOptionItem(id: $0.id, title: $0.title)
                },
                selectionID: viewModel.category.id,
                accessibilityLabelText: "Filter file types"
            ) { item in
                if let category = FileSearchCategory(rawValue: item.id) {
                    viewModel.category = category
                }
            }
        } sidebar: {
            resultsPane
        } detail: {
            detailPane
        }
        .onAppear {
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

    private var primaryActionID: CommandActionID {
        viewModel.loadState == .needsFolderAccess
            ? BuiltInCommandActionID.settings
            : BuiltInCommandActionID.openFile
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
        case .indexing where viewModel.results.isEmpty:
            VStack(spacing: density.spacing(.xs)) {
                ProgressView()
                    .controlSize(.small)
                Text("Building your local file index…")
                    .commandlyFont(size: 11, weight: .medium)
                    .foregroundStyle(.secondary)
                Text("Names appear first; content and image text are added in the background.")
                    .commandlyFont(size: 10, weight: .regular)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, density.spacing(.md))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .needsFolderAccess:
            LauncherApplicationEmptyState(
                systemImage: "folder.badge.questionmark",
                title: "Choose folders to search",
                message: "Choose folders Commandly may search and manage."
            )
        case .failed:
            LauncherApplicationEmptyState(
                systemImage: "exclamationmark.magnifyingglass",
                title: "Search unavailable",
                message: "Check Spotlight and try again."
            )
        default:
            if viewModel.results.isEmpty {
                LauncherApplicationEmptyState(
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
                        if item.tags.isEmpty == false {
                            metadataRow("Tags", item.tags.joined(separator: ", "))
                        }
                        switch item.matchKind {
                        case .contents:
                            metadataRow("Matched", "File contents")
                        case .metadata:
                            metadataRow("Matched", "Metadata")
                        case .tag:
                            metadataRow("Matched", "Finder tag")
                        case .filename, .recent:
                            EmptyView()
                        }
                    }
                    .padding(density.spacing(.md))
                }
            }
        } else {
            LauncherApplicationEmptyState(
                systemImage: "doc",
                title: "Select a file",
                message: "Its preview and metadata will appear here."
            )
        }
    }

    private func metadataRow(_ label: String, _ value: String) -> some View {
        LauncherApplicationMetadataRow(label: label, value: value)
    }

    private func abbreviatedPath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        guard path == home || path.hasPrefix("\(home)/") else { return path }
        return "~" + path.dropFirst(home.count)
    }
}
