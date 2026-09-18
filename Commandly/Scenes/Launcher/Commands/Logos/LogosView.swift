import DesignSystem
import SwiftUI

struct LogosView: View {
    @Bindable var viewModel: LogosViewModel
    @Environment(\.commandlyLayoutDensity) private var density

    var body: some View {
        LauncherApplicationScreen(
            query: $viewModel.query,
            searchPlaceholder: "Search logos and categories…",
            searchAccessibilityIdentifier: "logos-query",
            sidebarWidth: 372,
            onBack: viewModel.goBack,
            onSubmit: { viewModel.perform(LogosActionID.copySVG) },
            onMoveSelection: viewModel.moveSelection,
            onEscape: {
                if viewModel.handleEscape() == false {
                    viewModel.goBack()
                }
            }
        ) {
            CommandlyOptionMenu(
                items: viewModel.filterOptions.map {
                    CommandlyOptionItem(id: $0.id, title: "\($0.title)  \($0.count)")
                },
                selectionID: viewModel.filterID,
                searchPrompt: "Search categories…",
                accessibilityLabelText: "Filter logos"
            ) { option in
                viewModel.filterID = option.id
            }
        } sidebar: {
            sidebar
        } detail: {
            detail
        }
        .task {
            viewModel.load()
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Logos")
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            HStack(spacing: density.spacing(.xs)) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(viewModel.activeFilterTitle.uppercased())
                        .commandlyFont(size: 9.5, weight: .bold)
                        .tracking(0.6)
                        .foregroundStyle(.secondary)
                    Text(resultSummary)
                        .commandlyFont(size: 9.5)
                        .foregroundStyle(.tertiary)
                }
                Spacer(minLength: 0)
                Text("SVGL")
                    .commandlyFont(size: 9, weight: .semibold)
                    .foregroundStyle(.tertiary)
                    .accessibilityLabel("Powered by SVGL")
            }
            .padding(.horizontal, density.spacing(.sm))
            .padding(.vertical, density.spacing(.xs))

            Divider().opacity(0.3)

            sidebarContent
        }
    }

    private var resultSummary: String {
        let count = viewModel.filteredLogos.count
        return count == 1 ? "1 logo" : "\(count) logos"
    }

    @ViewBuilder
    private var sidebarContent: some View {
        switch viewModel.loadState {
        case .idle, .loading:
            LogoGridPlaceholder()
        case .empty:
            LauncherApplicationEmptyState(
                systemImage: "square.grid.3x3.square",
                title: "No logos available",
                message: "Refresh to try loading the SVGL catalog again."
            )
        case .failed(let error):
            VStack(spacing: density.spacing(.sm)) {
                LauncherApplicationEmptyState(
                    systemImage: "wifi.exclamationmark",
                    title: "Catalog unavailable",
                    message: error.errorDescription ?? "The catalog could not be loaded."
                )
                Button("Try Again") {
                    viewModel.load(forceRefresh: true)
                }
                .buttonStyle(.bordered)
                .padding(.bottom, density.spacing(.md))
            }
        case .loaded:
            if viewModel.filteredLogos.isEmpty {
                LauncherApplicationEmptyState(
                    systemImage: viewModel.filterID == LogoFilterOption.favoritesID
                        ? "star"
                        : "magnifyingglass",
                    title: viewModel.filterID == LogoFilterOption.favoritesID
                        ? "No favorite logos"
                        : "No matching logos",
                    message: viewModel.filterID == LogoFilterOption.favoritesID
                        ? "Use the star on a logo to keep it close."
                        : "Try a different search or category."
                )
            } else {
                logoGrid
            }
        }
    }

    private var logoGrid: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(minimum: 130), spacing: density.spacing(.xs)),
                        GridItem(.flexible(minimum: 130), spacing: density.spacing(.xs))
                    ],
                    spacing: density.spacing(.xs)
                ) {
                    ForEach(viewModel.filteredLogos) { logo in
                        LogoGridCard(
                            logo: logo,
                            isSelected: viewModel.selectedLogo?.id == logo.id,
                            isFavorite: viewModel.favoriteIDs.contains(logo.id),
                            service: viewModel.artworkService,
                            select: { viewModel.select(logo.id) },
                            copy: {
                                viewModel.select(logo.id)
                                viewModel.perform(LogosActionID.copySVG)
                            },
                            toggleFavorite: {
                                viewModel.select(logo.id)
                                viewModel.perform(LogosActionID.toggleFavorite)
                            }
                        )
                        .id(logo.id)
                    }
                }
                .padding(density.spacing(.xs))
            }
            .onChange(of: viewModel.selectedID) { _, id in
                guard viewModel.shouldScrollToSelection, let id else { return }
                withAnimation(.easeOut(duration: MotionDuration.fast.rawValue)) {
                    proxy.scrollTo(id, anchor: .center)
                }
            }
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let logo = viewModel.selectedLogo {
            LogoDetailPane(viewModel: viewModel, logo: logo)
        } else if viewModel.loadState == .loading {
            ProgressView("Loading logo catalog…")
                .controlSize(.small)
        } else {
            LauncherApplicationEmptyState(
                systemImage: "rectangle.and.text.magnifyingglass",
                title: "Select a logo",
                message: "Preview, copy, favorite, or download it here."
            )
        }
    }
}

private struct LogoGridCard: View {
    let logo: LogoAsset
    let isSelected: Bool
    let isFavorite: Bool
    let service: any SVGLServicing
    let select: () -> Void
    let copy: () -> Void
    let toggleFavorite: () -> Void
    @Environment(\.commandlyLayoutDensity) private var density

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Button(action: select) {
                VStack(spacing: density.spacing(.xs)) {
                    LogoSVGArtwork(
                        url: logo.routes.url(for: .light),
                        title: logo.title,
                        service: service
                    )
                    .frame(height: density.spacingScale < 1 ? 54 : 64)
                    .padding(.horizontal, density.spacing(.xs))

                    Text(logo.title)
                        .commandlyFont(size: 10.5, weight: .semibold)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(density.spacing(.xs))
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(logo.title)
            .accessibilityValue(isSelected ? "Selected" : "")
            .accessibilityHint("Selects the logo. Double-click copies its SVG.")
            .accessibilityAddTraits(isSelected ? .isSelected : [])

            Button(action: toggleFavorite) {
                Image(systemName: isFavorite ? "star.fill" : "star")
                    .commandlyFont(size: 10, weight: .semibold)
                    .foregroundStyle(isFavorite ? Color.accentColor : .secondary)
                    .frame(width: 24, height: 24)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .buttonStyle(.plain)
            .padding(5)
            .help(isFavorite ? "Remove from favorites" : "Add to favorites")
            .accessibilityLabel(isFavorite ? "Remove from favorites" : "Add to favorites")
        }
        .background {
            RoundedRectangle(cornerRadius: CornerRadius.md.rawValue, style: .continuous)
                .fill(isSelected ? Color.primary.opacity(0.105) : Color.primary.opacity(0.025))
        }
        .overlay {
            RoundedRectangle(cornerRadius: CornerRadius.md.rawValue, style: .continuous)
                .strokeBorder(
                    isSelected ? Color.accentColor.opacity(0.55) : LauncherPalette.separator,
                    lineWidth: isSelected ? 1.5 : 1
                )
        }
        .simultaneousGesture(TapGesture(count: 2).onEnded(copy))
        .onHover { hovering in
            if hovering { select() }
        }
    }
}

private struct LogoDetailPane: View {
    @Bindable var viewModel: LogosViewModel
    let logo: LogoAsset
    @Environment(\.commandlyLayoutDensity) private var density

    var body: some View {
        ScrollView {
            VStack(spacing: density.spacing(.lg)) {
                VStack(spacing: density.spacing(.sm)) {
                    LogoSVGArtwork(
                        url: logo.routes.url(for: viewModel.variant),
                        title: logo.title,
                        service: viewModel.artworkService
                    )
                    .frame(width: 210, height: 150)
                    .padding(density.spacing(.lg))
                    .background(Color.white.opacity(0.94))
                    .clipShape(RoundedRectangle(cornerRadius: CornerRadius.lg.rawValue))
                    .overlay {
                        RoundedRectangle(cornerRadius: CornerRadius.lg.rawValue)
                            .strokeBorder(LauncherPalette.separator, lineWidth: 1)
                    }
                    .shadow(color: .black.opacity(0.07), radius: 18, y: 7)

                    VStack(spacing: 4) {
                        HStack(spacing: 7) {
                            Text(logo.title)
                                .commandlyFont(size: 19, weight: .semibold)
                                .textSelection(.enabled)

                            Button {
                                viewModel.perform(LogosActionID.toggleFavorite)
                            } label: {
                                Image(systemName: viewModel.favoriteIDs.contains(logo.id)
                                    ? "star.fill"
                                    : "star")
                                    .foregroundStyle(viewModel.favoriteIDs.contains(logo.id)
                                        ? Color.accentColor
                                        : .secondary)
                            }
                            .buttonStyle(.plain)
                            .help(viewModel.favoriteIDs.contains(logo.id)
                                ? "Remove from favorites"
                                : "Add to favorites")
                        }

                        Text(logo.categories.joined(separator: "  •  "))
                            .commandlyFont(size: 10, weight: .medium)
                            .foregroundStyle(.secondary)
                    }
                }

                if logo.routes.hasAppearanceVariants {
                    Picker("Logo variant", selection: $viewModel.variant) {
                        ForEach(LogoVariant.allCases) { variant in
                            Text(variant.title).tag(variant)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 210)
                    .accessibilityHint("Changes the SVG used for preview, copy, and download")
                }

                HStack(spacing: density.spacing(.sm)) {
                    Button("Copy SVG", systemImage: "doc.on.doc") {
                        viewModel.perform(LogosActionID.copySVG)
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return, modifiers: [])

                    Button("Download", systemImage: "arrow.down.to.line") {
                        viewModel.perform(LogosActionID.download)
                    }
                    .buttonStyle(.bordered)
                }
                .controlSize(.regular)
                .disabled(viewModel.isPerformingAction)

                VStack(alignment: .leading, spacing: density.spacing(.sm)) {
                    LauncherApplicationMetadataRow(
                        label: "Format",
                        value: "Scalable Vector Graphic (SVG)",
                        labelWidth: 72
                    )
                    LauncherApplicationMetadataRow(
                        label: "Category",
                        value: logo.categories.joined(separator: ", "),
                        labelWidth: 72
                    )
                    LauncherApplicationMetadataRow(
                        label: "Source",
                        value: "SVGL community catalog",
                        labelWidth: 72
                    )
                }
                .frame(maxWidth: 390)
                .padding(density.spacing(.sm))
                .background(Color.primary.opacity(0.03))
                .clipShape(RoundedRectangle(cornerRadius: CornerRadius.md.rawValue))
                .overlay {
                    RoundedRectangle(cornerRadius: CornerRadius.md.rawValue)
                        .strokeBorder(LauncherPalette.separator, lineWidth: 1)
                }

                HStack(spacing: density.spacing(.md)) {
                    if let svglURL = URL(string: "https://svgl.app") {
                        Link(destination: svglURL) {
                            Label("SVGL", systemImage: "arrow.up.right")
                        }
                    }
                    if let websiteURL = logo.websiteURL {
                        Link(destination: websiteURL) {
                            Label("Website", systemImage: "globe")
                        }
                    }
                    if let brandURL = logo.brandURL {
                        Link(destination: brandURL) {
                            Label("Brand guidelines", systemImage: "checkmark.seal")
                        }
                    }
                }
                .commandlyFont(size: 10, weight: .medium)
                .foregroundStyle(.secondary)
            }
            .padding(density.spacing(.lg))
            .frame(maxWidth: .infinity)
        }
        .accessibilityElement(children: .contain)
    }
}

private struct LogoGridPlaceholder: View {
    @Environment(\.commandlyLayoutDensity) private var density

    var body: some View {
        LazyVGrid(
            columns: [GridItem(.flexible()), GridItem(.flexible())],
            spacing: density.spacing(.xs)
        ) {
            ForEach(0 ..< 6, id: \.self) { _ in
                RoundedRectangle(cornerRadius: CornerRadius.md.rawValue)
                    .fill(Color.primary.opacity(0.05))
                    .frame(height: density.spacingScale < 1 ? 82 : 94)
            }
        }
        .padding(density.spacing(.xs))
        .redacted(reason: .placeholder)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading logo catalog")
    }
}
