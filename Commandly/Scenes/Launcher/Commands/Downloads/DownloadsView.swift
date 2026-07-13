import CommandKit
import DesignSystem
import Foundation
import SwiftUI

struct DownloadsView: View {
    @Bindable var viewModel: DownloadsViewModel
    @Environment(\.commandlyLayoutDensity) private var density

    var body: some View {
        LauncherApplicationScreen(
            query: $viewModel.query,
            searchPlaceholder: "Filter recent downloads…",
            searchAccessibilityIdentifier: "recent-downloads-query",
            sidebarWidth: 292,
            onBack: viewModel.goBack,
            onSubmit: viewModel.performPrimary,
            onMoveSelection: viewModel.moveSelection,
            onEscape: {
                if viewModel.handleEscape() == false {
                    viewModel.goBack()
                }
            }
        ) {
            refreshButton
        } sidebar: {
            downloadsList
        } detail: {
            downloadsDetail
        }
        .task {
            guard viewModel.loadState == .idle else { return }
            viewModel.load()
            await viewModel.waitForLoadForTesting()
        }
        .onDisappear {
            viewModel.stop()
        }
        .accessibilityLabel("Recent Downloads")
    }

    private var refreshButton: some View {
        Button {
            viewModel.refresh()
        } label: {
            Image(systemName: "arrow.clockwise")
                .commandlyFont(size: 12, weight: .semibold)
                .frame(width: 28, height: 28)
                .background(Color.primary.opacity(0.07))
                .clipShape(RoundedRectangle(cornerRadius: CornerRadius.sm.rawValue))
        }
        .buttonStyle(.plain)
        .keyboardShortcut("r", modifiers: .command)
        .disabled(viewModel.loadState == .loading)
        .accessibilityLabel("Refresh recent downloads")
        .help("Refresh Downloads (Command-R)")
    }

    private var downloadsList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: density.spacing(.xxs)) {
                    sidebarContent
                }
                .padding(.vertical, density.spacing(.xs))
            }
            .onChange(of: viewModel.selectedID) { _, selectedID in
                guard let selectedID, viewModel.shouldScrollToSelection else { return }
                withAnimation(.easeOut(duration: MotionDuration.fast.rawValue)) {
                    proxy.scrollTo(selectedID, anchor: .center)
                }
            }
        }
    }

    @ViewBuilder
    private var sidebarContent: some View {
        switch viewModel.loadState {
        case .idle:
            loadingState
        case .loading where viewModel.items.isEmpty:
            loadingState
        case .failed(let error) where viewModel.items.isEmpty:
            sidebarMessage(
                systemImage: "exclamationmark.arrow.trianglehead.2.clockwise.rotate.90",
                title: "Downloads unavailable",
                message: error.errorDescription ?? "Recent downloads could not be read.",
                offersRetry: true
            )
        case .empty:
            sidebarMessage(
                systemImage: "arrow.down.circle",
                title: "No recent downloads",
                message: "New files in Downloads will appear here after a refresh."
            )
        default:
            if viewModel.filteredItems.isEmpty {
                sidebarMessage(
                    systemImage: "line.3.horizontal.decrease.circle",
                    title: "No matching downloads",
                    message: "Clear the filter to see the latest files."
                )
            } else {
                ForEach(viewModel.filteredItems) { item in
                    downloadRow(item)
                        .id(item.id)
                }
            }
        }
    }

    private var loadingState: some View {
        VStack(spacing: density.spacing(.sm)) {
            ProgressView()
                .controlSize(.small)
            Text("Reading recent downloads…")
                .commandlyFont(size: 10, weight: .medium)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 250)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Reading recent downloads")
    }

    private func sidebarMessage(
        systemImage: String,
        title: String,
        message: String,
        offersRetry: Bool = false
    ) -> some View {
        VStack(spacing: density.spacing(.sm)) {
            LauncherApplicationEmptyState(
                systemImage: systemImage,
                title: title,
                message: message
            )
            .frame(height: 190)

            if offersRetry {
                Button("Try Again") {
                    viewModel.refresh(showSuccessMessage: false)
                }
                .buttonStyle(.bordered)
                .accessibilityHint("Scans the Downloads folder again")
            }
        }
        .frame(maxWidth: .infinity, minHeight: 250)
    }

    private func downloadRow(_ item: RecentDownloadItem) -> some View {
        let artwork = LauncherFileArtwork(fileURL: item.url)
        let isSelected = item.id == viewModel.selectedItem?.id
        return LauncherApplicationRow(
            isSelected: isSelected,
            onSelect: { viewModel.select(item.id) },
            onOpen: {
                viewModel.select(item.id)
                viewModel.perform(BuiltInCommandActionID.openFile)
            },
            onContextAction: {
                viewModel.select(item.id)
                viewModel.showsActionsMenu = true
            },
            onHoverChange: { hovering in
                if hovering {
                    viewModel.select(item.id)
                }
            }
        ) {
            HStack(spacing: density.spacing(.sm)) {
                LauncherGlyph(
                    systemName: artwork.symbolName,
                    tone: artwork.tone,
                    isSelected: isSelected,
                    size: 25
                )

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name)
                        .commandlyFont(size: 12, weight: .semibold)
                        .lineLimit(1)
                    Text(item.recencyDate, style: .relative)
                        .commandlyFont(size: 9, weight: .medium)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } accessory: {
            Text(ByteCountFormatter.string(fromByteCount: item.byteCount, countStyle: .file))
                .commandlyFont(size: 9, weight: .medium)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(item.name)
        .accessibilityValue(
            "Added \(item.recencyDate.formatted(date: .abbreviated, time: .shortened)), "
                + ByteCountFormatter.string(fromByteCount: item.byteCount, countStyle: .file)
        )
    }

    @ViewBuilder
    private var downloadsDetail: some View {
        if let item = viewModel.selectedItem {
            DownloadDetailPane(
                item: item,
                isNewest: item.id == viewModel.newestItem?.id,
                isPerformingAction: viewModel.isPerformingAction,
                open: { viewModel.perform(BuiltInCommandActionID.openFile) },
                reveal: { viewModel.perform(BuiltInCommandActionID.revealFile) },
                copy: { viewModel.perform(BuiltInCommandActionID.copyFile) }
            )
        } else if viewModel.loadState == .loading {
            ProgressView("Refreshing Downloads…")
                .controlSize(.small)
                .accessibilityLabel("Refreshing Downloads")
        } else {
            LauncherApplicationEmptyState(
                systemImage: "arrow.down.doc",
                title: "No download selected",
                message: "Choose a recent file to open, reveal, or copy it."
            )
        }
    }
}

private struct DownloadDetailPane: View {
    let item: RecentDownloadItem
    let isNewest: Bool
    let isPerformingAction: Bool
    let open: () -> Void
    let reveal: () -> Void
    let copy: () -> Void
    @Environment(\.commandlyLayoutDensity) private var density

    var body: some View {
        let artwork = LauncherFileArtwork(fileURL: item.url)
        VStack(spacing: density.spacing(.lg)) {
            VStack(spacing: density.spacing(.sm)) {
                LauncherGlyph(
                    systemName: artwork.symbolName,
                    tone: artwork.tone,
                    isSelected: false,
                    size: 58
                )

                VStack(spacing: 4) {
                    if isNewest {
                        Text("NEWEST DOWNLOAD")
                            .commandlyFont(size: 8, weight: .bold)
                            .tracking(0.8)
                            .foregroundStyle(BrandPalette.accentSoft)
                    }
                    Text(item.name)
                        .commandlyFont(size: 18, weight: .semibold)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .textSelection(.enabled)
                    Text(item.url.pathExtension.isEmpty ? "File" : item.url.pathExtension.uppercased())
                        .commandlyFont(size: 9, weight: .semibold)
                        .foregroundStyle(.tertiary)
                }
            }

            HStack(spacing: density.spacing(.sm)) {
                Button("Open", systemImage: "arrow.up.forward.app") {
                    open()
                }
                .buttonStyle(.borderedProminent)
                .accessibilityHint("Opens the file in its default application")

                Button("Show in Finder", systemImage: "folder") {
                    reveal()
                }
                .buttonStyle(.bordered)

                Button("Copy File", systemImage: "doc.on.doc") {
                    copy()
                }
                .buttonStyle(.bordered)
                .accessibilityHint("Copies the file URL for pasting into another application")
            }
            .controlSize(.regular)
            .disabled(isPerformingAction)

            VStack(alignment: .leading, spacing: density.spacing(.sm)) {
                LauncherApplicationMetadataRow(
                    label: "Added",
                    value: item.recencyDate.formatted(date: .abbreviated, time: .shortened),
                    labelWidth: 70
                )
                LauncherApplicationMetadataRow(
                    label: "Modified",
                    value: item.modifiedAt.formatted(date: .abbreviated, time: .shortened),
                    labelWidth: 70
                )
                LauncherApplicationMetadataRow(
                    label: "Size",
                    value: ByteCountFormatter.string(fromByteCount: item.byteCount, countStyle: .file),
                    labelWidth: 70
                )
                LauncherApplicationMetadataRow(
                    label: "Location",
                    value: item.url.deletingLastPathComponent().path,
                    labelWidth: 70
                )
            }
            .frame(maxWidth: 360)
            .padding(density.spacing(.sm))
            .background(Color.primary.opacity(0.035))
            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.md.rawValue))
            .overlay {
                RoundedRectangle(cornerRadius: CornerRadius.md.rawValue)
                    .strokeBorder(LauncherPalette.separator, lineWidth: 1)
            }
        }
        .padding(density.spacing(.lg))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
    }
}
