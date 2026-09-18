import DesignSystem
import Infrastructure
import SwiftUI

struct FileBrowserView: View {
    @Bindable var model: FileBrowserViewModel
    @Environment(\.commandlyLayoutDensity) private var density

    var body: some View {
        LauncherApplicationScreen(
            query: $model.query, searchPlaceholder: "Filter this folder…",
            searchAccessibilityIdentifier: "file-browser-query", searchFocusRequest: model.searchFocusRequest,
            onBack: model.goBack, onSubmit: model.performPrimary, onMoveSelection: model.moveSelection,
            onEscape: { if model.handleEscape() == false { model.goBack() } }
        ) {
            HStack(spacing: 8) {
                Button(action: model.goUp) { Image(systemName: "arrow.up") }
                    .buttonStyle(.borderless).disabled(model.location == nil)
                    .keyboardShortcut(.upArrow, modifiers: .command)
                    .accessibilityLabel("Parent folder").help("Parent folder (Command-Up)")
                Button(action: model.refresh) { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.borderless).keyboardShortcut("r", modifiers: .command)
                    .accessibilityLabel("Refresh folder").help("Refresh (Command-R)")
            }
        } sidebar: {
            browserList
        } detail: {
            details
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("File Browser")
        .onAppear { model.start() }
        .onDisappear { model.stop() }
    }

    private var browserList: some View {
        VStack(alignment: .leading, spacing: density.spacing(.xs)) {
            Text(model.locationTitle).commandlyFont(size: 11, weight: .semibold)
                .foregroundStyle(.secondary).padding(.horizontal, density.spacing(.sm))
                .padding(.top, density.spacing(.sm)).accessibilityAddTraits(.isHeader)
            if model.phase == .loading {
                ProgressView("Loading folder…").padding(density.spacing(.md))
            } else if model.phase == .ready {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: density.spacing(.xs)) {
                            ForEach(model.rows) { row in
                                LauncherApplicationRow(isSelected: model.selectedID == row.id,
                                    onSelect: { model.select(row.id) },
                                    onOpen: { model.select(row.id); model.performPrimary() },
                                    onHoverChange: { _ in }
                                ) {
                                    HStack(spacing: density.spacing(.sm)) {
                                        Image(systemName: row.isFolder ? "folder" : "doc")
                                            .frame(width: 20).accessibilityHidden(true)
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(row.title).commandlyFont(size: 12, weight: .medium).lineLimit(1)
                                            Text(row.kindTitle).commandlyFont(size: 10).foregroundStyle(.secondary).lineLimit(1)
                                        }
                                    }
                                } accessory: { EmptyView() }
                                .id(row.id)
                            }
                            if model.rows.isEmpty {
                                Text(model.query.isEmpty ? "This folder is empty." : "No names match this filter.")
                                    .commandlyFont(size: 12).foregroundStyle(.secondary)
                                    .padding(density.spacing(.md))
                            }
                        }
                        .padding(density.spacing(.xs))
                    }
                    .onChange(of: model.selectedID) { _, id in
                        if let id { proxy.scrollTo(id, anchor: .center) }
                    }
                }
            }
            if model.snapshot?.isTruncated == true {
                Text("Showing a limited portion of this folder. Filtering applies to these displayed items.")
                    .commandlyFont(size: 10).foregroundStyle(.secondary).padding(density.spacing(.sm))
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder private var details: some View {
        if model.phase == .needsAccess || model.phase == .failed {
            VStack(spacing: density.spacing(.md)) {
                LauncherApplicationEmptyState(systemImage: "folder.badge.questionmark", title: "Folder access",
                    message: model.errorMessage ?? "Choose a folder in Permissions.")
                Button("Choose Authorized Folders", action: model.openPermissions).buttonStyle(.borderedProminent)
                if model.phase == .failed { Button("Try Again", action: model.refresh).buttonStyle(.borderless) }
            }.padding(density.spacing(.lg))
        } else if let selected = model.selectedRow {
            ScrollView {
                VStack(alignment: .leading, spacing: density.spacing(.md)) {
                    Text(model.relativeLocation).commandlyFont(size: 11).foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    Image(systemName: selected.isFolder ? "folder" : "doc.text")
                        .commandlyFont(size: 42, weight: .light).accessibilityHidden(true)
                    Text(selected.title).commandlyFont(size: 21, weight: .semibold)
                        .textSelection(.enabled).accessibilityAddTraits(.isHeader)
                    Text(selected.kindTitle).commandlyFont(size: 12).foregroundStyle(.secondary)
                    if case .entry(let entry) = selected {
                        if let byteCount = entry.byteCount {
                            LauncherApplicationMetadataRow(label: "Size", value: ByteCountFormatter.string(fromByteCount: byteCount, countStyle: .file))
                        }
                        if let date = entry.modifiedAt {
                            LauncherApplicationMetadataRow(label: "Modified", value: date.formatted(date: .abbreviated, time: .shortened))
                        }
                    }
                    if selected.isActionable {
                        Button(selected.isFolder ? "Open Folder" : "Open File", action: model.performPrimary)
                            .buttonStyle(.borderedProminent).disabled(model.isOpening)
                    } else {
                        Text("Links and aliases stay closed. Authorize their destination folder directly to browse it.")
                            .commandlyFont(size: 12).foregroundStyle(.secondary)
                    }
                    Text("Browsing reads names and metadata in this folder. Files open only when you choose Open.")
                        .commandlyFont(size: 11).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading).padding(density.spacing(.lg))
            }
            .id(selected.id)
        } else {
            LauncherApplicationEmptyState(systemImage: "folder", title: model.locationTitle,
                message: model.phase == .loading ? "Reading this folder’s immediate children…" : "Select an item to see its details.")
        }
    }
}
