import DesignSystem
import SwiftUI

struct DocumentationSidebar: View {
    @Bindable var viewModel: DocumentationViewModel
    var isSearchFocused: FocusState<Bool>.Binding

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            identity

            DocumentationSearchField(
                text: $viewModel.query,
                isFocused: isSearchFocused,
                onMove: viewModel.moveSelection
            )
            .padding(.horizontal, 12)

            HStack {
                Text(viewModel.resultSummary)
                Spacer()
                Text("⌘F")
                    .accessibilityLabel("Command F")
            }
            .commandlyFont(size: 9.5, weight: .medium)
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 15)
            .padding(.top, 7)
            .padding(.bottom, 5)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 13, pinnedViews: []) {
                    ForEach(viewModel.groupedArticles, id: \.category.id) { group in
                        DocumentationSidebarSection(
                            category: group.category,
                            articles: group.articles,
                            selectedArticleID: viewModel.selectedArticleID,
                            onSelect: viewModel.select
                        )
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 16)
            }
            .scrollIndicators(.hidden)

            Divider()
                .overlay(SettingsPalette.border)

            HStack(spacing: 6) {
                Image(systemName: "lock.shield")
                Text("Local, private help")
                Spacer()
            }
            .commandlyFont(size: 9.5, weight: .medium)
            .foregroundStyle(.quaternary)
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
        }
        .background(SettingsPalette.sidebar)
        .overlay(alignment: .trailing) {
            Rectangle().fill(SettingsPalette.border).frame(width: 1)
        }
        .accessibilityIdentifier("documentation.sidebar")
    }

    private var identity: some View {
        HStack(spacing: 10) {
            CommandlyApplicationIcon(size: 34)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text("Commandly")
                    .commandlyFont(size: 13, weight: .semibold)
                Text("Documentation")
                    .commandlyFont(size: 10, weight: .medium)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 42)
        .padding(.bottom, 14)
    }
}

private struct DocumentationSearchField: View {
    @Binding var text: String
    var isFocused: FocusState<Bool>.Binding
    let onMove: (Int) -> Void

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .commandlyFont(size: 10.5, weight: .semibold)
                .foregroundStyle(
                    isFocused.wrappedValue
                        ? BrandPalette.accentSoft
                        : Color.secondary.opacity(0.68)
                )

            TextField("Search documentation", text: $text)
                .textFieldStyle(.plain)
                .commandlyFont(size: 11)
                .focused(isFocused)
                .onKeyPress(.upArrow) {
                    onMove(-1)
                    return .handled
                }
                .onKeyPress(.downArrow) {
                    onMove(1)
                    return .handled
                }
                .onKeyPress(.escape) {
                    guard text.isEmpty == false else { return .ignored }
                    text = ""
                    return .handled
                }

            if text.isEmpty == false {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help("Clear search")
                .accessibilityLabel("Clear documentation search")
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 31)
        .background {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.primary.opacity(0.045))
        }
        .glassEffect(
            .regular.tint(BrandPalette.accent.opacity(isFocused.wrappedValue ? 0.07 : 0.02)),
            in: .rect(cornerRadius: 9)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(
                    isFocused.wrappedValue ? BrandPalette.accent.opacity(0.38) : SettingsPalette.border,
                    lineWidth: 1
                )
        }
        .accessibilityIdentifier("documentation.search")
    }
}

private struct DocumentationSidebarSection: View {
    let category: DocumentationCategory
    let articles: [DocumentationArticle]
    let selectedArticleID: String?
    let onSelect: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Label(category.title.uppercased(), systemImage: category.systemImage)
                .commandlyFont(size: 8.5, weight: .semibold)
                .tracking(0.8)
                .foregroundStyle(.quaternary)
                .padding(.horizontal, 8)
                .accessibilityAddTraits(.isHeader)

            ForEach(articles) { article in
                DocumentationSidebarRow(
                    article: article,
                    isSelected: article.id == selectedArticleID,
                    onSelect: { onSelect(article.id) }
                )
            }
        }
    }
}

private struct DocumentationSidebarRow: View {
    let article: DocumentationArticle
    let isSelected: Bool
    let onSelect: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 8) {
                Image(systemName: article.systemImage)
                    .symbolVariant(.fill)
                    .commandlyFont(size: 10, weight: .semibold)
                    .foregroundStyle(
                        isSelected ? BrandPalette.accentSoft : Color.secondary
                    )
                    .frame(width: 23, height: 23)
                    .background {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(isSelected ? BrandPalette.accent.opacity(0.15) : Color.primary.opacity(0.04))
                    }

                Text(article.title)
                    .commandlyFont(size: 11, weight: isSelected ? .semibold : .regular)
                    .lineLimit(1)

                Spacer(minLength: 0)

                if article.isEnabled == false {
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 5, height: 5)
                        .accessibilityLabel("Disabled")
                }
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(
                        isSelected
                            ? Color.primary.opacity(0.085)
                            : Color.primary.opacity(isHovered ? 0.04 : 0)
                    )
            }
            .overlay {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(isSelected ? SettingsPalette.border : .clear, lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityLabel(article.title)
        .accessibilityValue(article.isEnabled ? "Available" : "Disabled")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
