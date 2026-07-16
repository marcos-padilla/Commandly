import SwiftUI
import DesignSystem
import Infrastructure

/// Review surface for uninstalling an application and related support files.
struct ApplicationUninstallView: View {
    @Bindable var viewModel: ApplicationUninstallViewModel
    @Environment(\.commandlyLayoutDensity) private var density

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.22)
            summary
            content
            if let statusMessage = viewModel.statusMessage {
                Text(statusMessage)
                    .commandlyFont(size: 11, weight: .medium)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, density.spacing(.md))
                    .padding(.bottom, density.spacing(.xs))
            }
            footer
        }
        .onAppear {
            viewModel.load()
        }
        .onKeyPress(.return) {
            viewModel.confirmUninstall()
            return .handled
        }
        .onKeyPress(.escape) {
            viewModel.goBack()
            return .handled
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Uninstall \(viewModel.applicationName)")
    }

    private var header: some View {
        HStack(spacing: density.spacing(.sm)) {
            CommandlyBackButton {
                viewModel.goBack()
            }

            HStack(spacing: density.spacing(.sm)) {
                Image(systemName: "magnifyingglass")
                    .symbolVariant(.none)
                    .commandlyFont(size: 15, weight: .medium)
                    .foregroundStyle(.secondary)
                    .frame(width: density.iconSize, height: density.iconSize)
                    .accessibilityHidden(true)
                TextField("Filter files and folders by name…", text: $viewModel.filterQuery)
                    .textFieldStyle(.plain)
                    .commandlyFont(size: 16, weight: .medium)
                    .accessibilityLabel("Filter related files and folders")
                    .accessibilityValue(viewModel.filterQuery)
                    .accessibilityIdentifier("application-uninstall-query")
            }
            .padding(.vertical, density.searchVerticalPadding)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .layoutPriority(1)

            CommandlyOptionMenu(
                items: ApplicationUninstallSort.allCases.map {
                    CommandlyOptionItem(id: $0.rawValue, title: $0.title)
                },
                selectionID: viewModel.sort.rawValue,
                accessibilityLabelText: "Sort related files",
                onSelect: { item in
                    if let sort = ApplicationUninstallSort(rawValue: item.id) {
                        viewModel.sort = sort
                    }
                }
            )
            .zIndex(30)
        }
        .padding(.horizontal, density.spacing(.md))
        .padding(.top, density.spacing(.xs))
        .padding(.bottom, density.spacing(.xxs))
        .zIndex(20)
    }

    private var summary: some View {
        HStack {
            Text(viewModel.selectedCountLabel)
                .commandlyFont(size: 12, weight: .semibold)
            Text(viewModel.formattedSelectedSize)
                .commandlyFont(size: 12, weight: .medium)
                .foregroundStyle(.secondary)
            Spacer()
            if viewModel.isLoading {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, density.spacing(.md))
        .padding(.vertical, density.spacing(.xs))
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading {
            ProgressView("Finding related files…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if viewModel.filteredItems.isEmpty {
            VStack(spacing: Spacing.xs.rawValue) {
                Image(systemName: "tray")
                    .commandlyFont(size: 22, weight: .medium)
                    .foregroundStyle(.tertiary)
                Text("No matching files")
                    .commandlyFont(size: 13, weight: .semibold)
                Text("Try a different filter.")
                    .commandlyFont(size: 11, weight: .regular)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(viewModel.filteredItems) { item in
                        ApplicationUninstallRow(
                            item: item,
                            isSelected: viewModel.selectedPaths.contains(item.path)
                        ) {
                            viewModel.toggleSelection(item.path)
                        }
                    }
                }
                .padding(.horizontal, density.spacing(.xs))
                .padding(.vertical, density.spacing(.xxs))
            }
            .frame(maxHeight: .infinity)
        }
    }

    private var footer: some View {
        HStack(spacing: density.spacing(.sm)) {
            ApplicationLauncherIcon(path: viewModel.applicationPath, size: density.iconSize - 4)
            Text("Uninstall \(viewModel.applicationName)")
                .commandlyFont(size: 12, weight: .semibold)
                .lineLimit(1)
            Spacer(minLength: density.spacing(.sm))
            Button {
                viewModel.confirmUninstall()
            } label: {
                HStack(spacing: 6) {
                    Text(viewModel.isUninstalling ? "Uninstalling…" : "Uninstall Application")
                        .commandlyFont(size: 12, weight: .semibold)
                    Text("↩")
                        .commandlyFont(size: 10, weight: .semibold, design: .rounded)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(Color.white.opacity(0.18))
                        )
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(viewModel.canUninstall ? Color.red.opacity(0.85) : Color.red.opacity(0.35))
                )
            }
            .buttonStyle(.plain)
            .disabled(viewModel.canUninstall == false)
            .accessibilityLabel("Uninstall Application")
        }
        .padding(.horizontal, density.spacing(.md))
        .padding(.vertical, density.spacing(.sm))
        .background(Color.primary.opacity(0.04))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.primary.opacity(0.06))
                .frame(height: 1)
        }
    }
}

private struct ApplicationUninstallRow: View {
    let item: ApplicationRelatedItem
    let isSelected: Bool
    let toggle: () -> Void
    @Environment(\.commandlyLayoutDensity) private var density

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: density.spacing(.sm)) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .commandlyFont(size: 14, weight: .semibold)
                    .foregroundStyle(isSelected ? BrandPalette.accentSoft : Color.secondary)

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name)
                        .commandlyFont(size: 13, weight: .medium)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(item.containerPath)
                        .commandlyFont(size: 11, weight: .regular)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Text(ByteCountFormatter.string(fromByteCount: item.byteCount, countStyle: .file))
                    .commandlyFont(size: 11, weight: .medium)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()

                Image(systemName: iconName)
                    .commandlyFont(size: 12, weight: .semibold)
                    .foregroundStyle(.tertiary)
                    .frame(width: 18)
            }
            .padding(.horizontal, density.spacing(.sm))
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.md.rawValue, style: .continuous)
                    .fill(isSelected ? Color.primary.opacity(0.06) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.name)
        .accessibilityValue("\(item.containerPath), \(ByteCountFormatter.string(fromByteCount: item.byteCount, countStyle: .file))")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private var iconName: String {
        switch item.kind {
        case .application: return "app.fill"
        case .folder: return "folder.fill"
        case .preferences: return "doc.text"
        case .file: return "doc"
        }
    }
}
