import DesignSystem
import SearchKit
import SwiftUI

struct FileSearchResultRow: View {
    let item: FileSearchItem
    let isSelected: Bool
    let density: CommandlyLayoutDensity
    let onSelect: () -> Void
    let onOpen: () -> Void
    let onShowActions: () -> Void

    var body: some View {
        LauncherApplicationRow(
            isSelected: isSelected,
            onSelect: onSelect,
            onOpen: onOpen,
            onContextAction: onShowActions,
            onHoverChange: handleHover
        ) {
            HStack(spacing: density.spacing(.sm)) {
                LauncherGlyph(
                    systemName: artwork.symbolName,
                    tone: artwork.tone,
                    isSelected: isSelected,
                    size: density.iconSize
                )
                Text(item.name)
                    .commandlyFont(size: 12, weight: .medium)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
            }
        } accessory: {
            EmptyView()
        }
        .accessibilityLabel("\(item.name), \(item.contentTypeDescription)")
        .accessibilityIdentifier("file-search-result-\(item.name)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityAction(named: "Open", onOpen)
        .accessibilityAction(named: "Show Actions", onShowActions)
    }

    private var artwork: LauncherFileArtwork { LauncherFileArtwork(item: item) }

    private func handleHover(_ hovering: Bool) {
        if hovering { onSelect() }
    }
}

struct FileSearchPreview: View {
    let item: FileSearchItem

    var body: some View {
        Group {
            if item.kind == .folder {
                folderPreview
            } else if isCSV {
                CSVFilePreview(item: item)
            } else {
                QuickLookSnapshotPreview(
                    url: item.url,
                    modificationDate: item.modifiedAt
                )
                .clipShape(
                    RoundedRectangle(cornerRadius: CornerRadius.md.rawValue, style: .continuous)
                )
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Preview of \(item.name)")
            }
        }
    }

    private var isCSV: Bool {
        item.url.pathExtension.lowercased() == "csv"
            || item.contentTypeIdentifier == "public.comma-separated-values-text"
    }

    private var folderPreview: some View {
        VStack(spacing: Spacing.sm.rawValue) {
            Image(systemName: "folder.fill")
                .commandlyFont(size: 54, weight: .medium)
                .foregroundStyle(BrandPalette.accentSoft)
            Text(item.name)
                .commandlyFont(size: 13, weight: .semibold)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
            case .loaded(let content):
                CSVTablePreview(content: content)
            case .failed:
                previewUnavailable
            }
        }
        .task(id: item.url) {
            await load()
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("CSV preview of \(item.name)")
    }

    private var previewUnavailable: some View {
        VStack(spacing: Spacing.xs.rawValue) {
            Image(systemName: "tablecells.badge.ellipsis")
                .commandlyFont(size: 28, weight: .medium)
                .foregroundStyle(.tertiary)
            Text("Preview unavailable")
                .commandlyFont(size: 11, weight: .semibold)
            Text("The CSV could not be read from its authorized folder.")
                .commandlyFont(size: 10)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func load() async {
        state = .loading
        do {
            state = .loaded(try await CSVPreviewLoader.load(url: item.url))
        } catch is CancellationError {
            return
        } catch {
            state = .failed
        }
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
                                .background(
                                    index.isMultiple(of: 2)
                                        ? Color.clear
                                        : Color.primary.opacity(0.025)
                                )
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
