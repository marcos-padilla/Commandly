import DesignSystem
import Infrastructure
import SwiftUI

struct StorageCleanerView: View {
    @Bindable var viewModel: StorageCleanerViewModel
    @Environment(\.commandlyLayoutDensity) private var density

    var body: some View {
        LauncherApplicationScreen(
            query: $viewModel.query,
            searchPlaceholder: "Filter cleanup candidates…",
            searchAccessibilityIdentifier: "storage-cleaner-query",
            sidebarWidth: 230,
            onBack: viewModel.goBack,
            onSubmit: viewModel.toggleSelectedRow,
            onMoveSelection: viewModel.moveSelection,
            onEscape: {
                if viewModel.handleEscape() == false {
                    viewModel.goBack()
                }
            },
            filterControl: {
                headerStatus
            },
            sidebar: {
                categorySidebar
            },
            detail: {
                candidateDetail
            }
        )
        .task {
            viewModel.start()
        }
        .onDisappear {
            viewModel.stop()
        }
        .onKeyPress(phases: .down) { press in
            guard press.modifiers.contains(.command),
                  press.characters == "\r" || press.characters == "\n" else {
                return .ignored
            }
            viewModel.requestCleanupConfirmation()
            return .handled
        }
        .alert(
            "Move Selected Items to Trash?",
            isPresented: confirmationBinding,
            presenting: viewModel.pendingConfirmation
        ) { _ in
            Button("Cancel", role: .cancel) {
                viewModel.cancelCleanupConfirmation()
            }
            Button("Move to Trash", role: .destructive) {
                viewModel.confirmCleanup()
            }
        } message: { confirmation in
            Text(confirmation.message)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Storage Cleaner")
    }

    private var confirmationBinding: Binding<Bool> {
        Binding(
            get: { viewModel.pendingConfirmation != nil },
            set: { isPresented in
                if isPresented == false {
                    viewModel.cancelCleanupConfirmation()
                }
            }
        )
    }

    private var headerStatus: some View {
        HStack(spacing: density.spacing(.xs)) {
            if viewModel.isScanning {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("Scanning storage")
            }
            Text(viewModel.selectedSummary)
                .commandlyFont(size: 10, weight: .semibold)
                .foregroundStyle(viewModel.selectedPaths.isEmpty ? .secondary : BrandPalette.accent)
                .monospacedDigit()
                .accessibilityLabel("Selected \(viewModel.selectedSummary)")
        }
    }

    private var categorySidebar: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(StorageCleanerCategory.allCases) { category in
                        categoryRow(category)
                    }
                }
                .padding(.vertical, density.spacing(.xs))
            }

            VStack(alignment: .leading, spacing: density.spacing(.xs)) {
                if let duplicateScopeName = viewModel.duplicateScopeName {
                    Label(duplicateScopeName, systemImage: "folder")
                        .commandlyFont(size: 10, weight: .medium)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .help("Current duplicate scan folder")
                }

                Button {
                    viewModel.chooseAndScanDuplicateFolder()
                } label: {
                    Label("Find Exact Duplicates…", systemImage: "doc.on.doc")
                        .commandlyFont(size: 11, weight: .semibold)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, density.spacing(.sm))
                        .padding(.vertical, 7)
                        .background(
                            RoundedRectangle(
                                cornerRadius: CornerRadius.md.rawValue,
                                style: .continuous
                            )
                            .fill(Color.primary.opacity(0.06))
                        )
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isScanning || viewModel.isCleaning)
                .accessibilityHint(
                    "Choose one folder for an on-device byte-for-byte duplicate scan."
                )

                Label("Nothing is deleted automatically.", systemImage: "lock.shield")
                    .commandlyFont(size: 9, weight: .medium)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityElement(children: .combine)
            }
            .padding(density.spacing(.sm))
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(LauncherPalette.separator)
                    .frame(height: 1)
            }
        }
    }

    private func categoryRow(_ category: StorageCleanerCategory) -> some View {
        let isSelected = viewModel.category == category
        return Button {
            viewModel.setCategory(category)
        } label: {
            HStack(spacing: density.spacing(.sm)) {
                Image(systemName: category.systemImage)
                    .commandlyFont(size: 13, weight: .semibold)
                    .foregroundStyle(isSelected ? BrandPalette.accent : .secondary)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 2) {
                    Text(category.title)
                        .commandlyFont(size: 11, weight: .semibold)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(
                        ByteCountFormatter.string(
                            fromByteCount: viewModel.byteCount(in: category),
                            countStyle: .file
                        )
                    )
                    .commandlyFont(size: 9, weight: .medium)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
                }

                Spacer(minLength: 0)

                Text("\(viewModel.itemCount(in: category))")
                    .commandlyFont(size: 9, weight: .semibold)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .padding(.horizontal, density.spacing(.sm))
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(
                    cornerRadius: CornerRadius.md.rawValue,
                    style: .continuous
                )
                .fill(isSelected ? Color.primary.opacity(0.1) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, density.spacing(.xs))
        .accessibilityLabel(category.title)
        .accessibilityValue(
            "\(viewModel.itemCount(in: category)) candidates, \(ByteCountFormatter.string(fromByteCount: viewModel.byteCount(in: category), countStyle: .file))"
        )
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private var candidateDetail: some View {
        VStack(spacing: 0) {
            candidateSummary
            Rectangle()
                .fill(LauncherPalette.separator)
                .frame(height: 1)
            candidateContent
        }
    }

    private var candidateSummary: some View {
        HStack(spacing: density.spacing(.sm)) {
            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.category.title)
                    .commandlyFont(size: 13, weight: .semibold)
                Text(categoryExplanation)
                    .commandlyFont(size: 9, weight: .medium)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: density.spacing(.sm))

            Text(
                ByteCountFormatter.string(
                    fromByteCount: viewModel.visibleByteCount,
                    countStyle: .file
                )
            )
            .commandlyFont(size: 10, weight: .semibold)
            .foregroundStyle(.secondary)
            .monospacedDigit()

            Button("Select All") {
                viewModel.selectAllVisible()
            }
            .buttonStyle(.plain)
            .commandlyFont(size: 10, weight: .semibold)
            .disabled(viewModel.filteredItems.isEmpty || viewModel.isCleaning)
            .accessibilityHint("Exact duplicate groups will still keep at least one copy.")

            Button("Clear") {
                viewModel.clearVisibleSelection()
            }
            .buttonStyle(.plain)
            .commandlyFont(size: 10, weight: .semibold)
            .disabled(viewModel.selectedPaths.isEmpty || viewModel.isCleaning)
        }
        .padding(.horizontal, density.spacing(.md))
        .padding(.vertical, density.spacing(.sm))
    }

    @ViewBuilder
    private var candidateContent: some View {
        if viewModel.items.isEmpty && viewModel.isScanningLibrary {
            VStack(spacing: 2) {
                ForEach(0..<5, id: \.self) { _ in
                    StorageCleanerPlaceholderRow()
                }
            }
            .padding(.vertical, density.spacing(.xs))
            .redacted(reason: .placeholder)
        } else if viewModel.filteredItems.isEmpty {
            LauncherApplicationEmptyState(
                systemImage: emptyStateSystemImage,
                title: emptyStateTitle,
                message: emptyStateMessage
            )
        } else {
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(viewModel.filteredItems) { item in
                        StorageCleanerCandidateRow(
                            item: item,
                            isFocused: viewModel.selectedRowPath == item.path,
                            isMarkedForRemoval: viewModel.selectedPaths.contains(item.path),
                            onSelect: {
                                viewModel.selectRow(item)
                            },
                            onToggle: {
                                viewModel.toggleSelection(of: item)
                            }
                        )
                    }
                }
                .padding(.vertical, density.spacing(.xs))
            }
            .overlay(alignment: .topTrailing) {
                if viewModel.isScanningDuplicates {
                    ProgressView()
                        .controlSize(.small)
                        .padding(density.spacing(.sm))
                        .accessibilityLabel("Finding exact duplicates")
                }
            }
        }
    }

    private var categoryExplanation: String {
        switch viewModel.category {
        case .all:
            return "Review every candidate; recommendations are selected, ordinary caches are not."
        case .applicationLeftovers:
            return "Identifier-named user Library data with no matching installed application."
        case .caches:
            return "Third-party user caches; apps can recreate these and none are preselected."
        case .duplicates:
            return "Byte-for-byte matches in your chosen folder; Commandly always keeps one copy."
        }
    }

    private var emptyStateSystemImage: String {
        switch viewModel.category {
        case .duplicates: return "doc.on.doc"
        default: return viewModel.isScanning ? "internaldrive" : "checkmark.circle"
        }
    }

    private var emptyStateTitle: String {
        if viewModel.isScanning { return "Scanning storage" }
        if viewModel.category == .duplicates, viewModel.duplicateScopeName == nil {
            return "Choose a folder to find duplicates"
        }
        return viewModel.query.isEmpty ? "No candidates found" : "No matching candidates"
    }

    private var emptyStateMessage: String {
        if viewModel.isScanning {
            return "Commandly is calculating sizes on this Mac."
        }
        if viewModel.category == .duplicates, viewModel.duplicateScopeName == nil {
            return "Only the folder you choose is read, and the scan is not saved."
        }
        return viewModel.query.isEmpty
            ? "Nothing in this category currently needs review."
            : "Try a different name, path, or bundle identifier."
    }
}

private struct StorageCleanerCandidateRow: View {
    let item: StorageCleanupItem
    let isFocused: Bool
    let isMarkedForRemoval: Bool
    let onSelect: () -> Void
    let onToggle: () -> Void
    @Environment(\.commandlyLayoutDensity) private var density

    var body: some View {
        LauncherApplicationRow(
            isSelected: isFocused,
            onSelect: onSelect,
            onOpen: onToggle,
            onHoverChange: { hovering in
                if hovering {
                    onSelect()
                }
            }
        ) {
            HStack(spacing: density.spacing(.sm)) {
                Image(systemName: categorySystemImage)
                    .commandlyFont(size: 13, weight: .semibold)
                    .foregroundStyle(categoryColor)
                    .frame(width: 22)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: density.spacing(.xs)) {
                        Text(item.name)
                            .commandlyFont(size: 11, weight: .semibold)
                            .lineLimit(1)
                        Text(categoryTitle)
                            .commandlyFont(size: 8, weight: .bold)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(
                                Capsule()
                                    .fill(Color.primary.opacity(0.06))
                            )
                    }
                    Text(item.containerPath)
                        .commandlyFont(size: 9, weight: .medium)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }

                Spacer(minLength: density.spacing(.xs))

                Text(
                    ByteCountFormatter.string(
                        fromByteCount: item.byteCount,
                        countStyle: .file
                    )
                )
                .commandlyFont(size: 9, weight: .semibold)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(item.name)
            .accessibilityValue(
                "\(categoryTitle), \(item.containerPath), \(ByteCountFormatter.string(fromByteCount: item.byteCount, countStyle: .file))"
            )
        } accessory: {
            Button(action: onToggle) {
                HStack(spacing: 4) {
                    if item.category == .duplicate {
                        Text(isMarkedForRemoval ? "Remove" : "Keep")
                            .commandlyFont(size: 8, weight: .bold)
                    }
                    Image(
                        systemName: isMarkedForRemoval
                            ? "checkmark.circle.fill"
                            : "circle"
                    )
                    .commandlyFont(size: 14, weight: .semibold)
                }
                .foregroundStyle(
                    isMarkedForRemoval ? BrandPalette.accent : Color.secondary
                )
            }
            .buttonStyle(.plain)
            .disabled(false)
            .accessibilityLabel(
                isMarkedForRemoval ? "Remove \(item.name)" : "Keep \(item.name)"
            )
            .accessibilityValue(isMarkedForRemoval ? "Selected for cleanup" : "Not selected")
            .accessibilityAddTraits(isMarkedForRemoval ? [.isSelected] : [])
        }
    }

    private var categoryTitle: String {
        switch item.category {
        case .applicationLeftover: return "LEFTOVER"
        case .cache: return "CACHE"
        case .duplicate: return "DUPLICATE"
        }
    }

    private var categorySystemImage: String {
        switch item.category {
        case .applicationLeftover: return "app.dashed"
        case .cache: return "arrow.trianglehead.2.clockwise.rotate.90"
        case .duplicate: return "doc.on.doc"
        }
    }

    private var categoryColor: Color {
        switch item.category {
        case .applicationLeftover: return .orange
        case .cache: return .cyan
        case .duplicate: return .purple
        }
    }
}

private struct StorageCleanerPlaceholderRow: View {
    @Environment(\.commandlyLayoutDensity) private var density

    var body: some View {
        HStack(spacing: density.spacing(.sm)) {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.secondary.opacity(0.15))
                .frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 4) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.secondary.opacity(0.15))
                    .frame(width: 150, height: 10)
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.secondary.opacity(0.1))
                    .frame(width: 220, height: 8)
            }
            Spacer()
        }
        .padding(.horizontal, density.spacing(.md))
        .padding(.vertical, 8)
        .accessibilityHidden(true)
    }
}
