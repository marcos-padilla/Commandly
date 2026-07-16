import DesignSystem
import Foundation
import SwiftUI

struct DocumentationSidebar: View {
    @Bindable var viewModel: DocumentationViewModel
    var isSearchFocused: FocusState<Bool>.Binding

    private var listSelection: Binding<String?> {
        Binding(
            get: { viewModel.selectedArticleID },
            set: { newValue in
                if let newValue {
                    viewModel.select(newValue)
                }
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DocumentationSearchField(
                text: $viewModel.query,
                isFocused: isSearchFocused,
                onMove: viewModel.moveSelection
            )
            .padding(.horizontal, Spacing.sm.rawValue)
            .frame(height: DocumentationTopBar.height)

            if viewModel.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
                Text(viewModel.resultSummary)
                    .commandlyFont(size: 9.5, weight: .medium)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, Spacing.md.rawValue)
                    .padding(.bottom, Spacing.xxs.rawValue)
                    .accessibilityLabel(viewModel.resultSummary)
            }

            List(selection: listSelection) {
                ForEach(viewModel.groupedArticles, id: \.category.id) { group in
                    Section {
                        ForEach(group.articles) { article in
                            DocumentationSidebarRow(
                                article: article,
                                isSelected: article.id == viewModel.selectedArticleID
                            )
                            .tag(article.id)
                            .listRowInsets(
                                EdgeInsets(top: 2, leading: 8, bottom: 2, trailing: 8)
                            )
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                        }
                    } header: {
                        Text(group.category.title)
                            .commandlyFont(size: 9, weight: .semibold)
                            .foregroundStyle(.tertiary)
                            .accessibilityAddTraits(.isHeader)
                    }
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .environment(\.defaultMinListRowHeight, 34)

            Label("Local, private help", systemImage: "lock.fill")
                .commandlyFont(size: 9.5, weight: .medium)
                .foregroundStyle(.quaternary)
                .padding(.horizontal, Spacing.md.rawValue)
                .padding(.bottom, Spacing.sm.rawValue)
                .accessibilityElement(children: .combine)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DocumentationVisualStyle.sidebar)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(DocumentationVisualStyle.separator)
                .frame(width: 1)
                .accessibilityHidden(true)
        }
        .accessibilityIdentifier("documentation.sidebar")
    }
}

private struct DocumentationSearchField: View {
    @Binding var text: String
    var isFocused: FocusState<Bool>.Binding
    let onMove: (Int) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .commandlyFont(size: 11, weight: .medium)
                .foregroundStyle(isFocused.wrappedValue ? Color.primary : Color.secondary)
                .accessibilityHidden(true)

            TextField("Search Documentation", text: $text)
                .textFieldStyle(.plain)
                .commandlyFont(size: 11.5)
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
                .accessibilityLabel("Search Documentation articles")

            if text.isEmpty == false {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .commandlyFont(size: 10.5)
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help("Clear search")
                .accessibilityLabel("Clear Documentation search")
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 30)
        .overlay {
            RoundedRectangle(cornerRadius: CornerRadius.md.rawValue, style: .continuous)
                .strokeBorder(
                    isFocused.wrappedValue
                        ? DocumentationVisualStyle.focusRing
                        : DocumentationVisualStyle.separator,
                    lineWidth: 1
                )
        }
        .glassEffect(
            .regular.interactive(),
            in: .rect(cornerRadius: CornerRadius.md.rawValue)
        )
        .animation(
            reduceMotion ? nil : CommandlyMotion.hover,
            value: isFocused.wrappedValue
        )
        .accessibilityIdentifier("documentation.search")
    }
}

private struct DocumentationSidebarRow: View {
    let article: DocumentationArticle
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 9) {
            DocumentationGlyph(
                systemImage: article.systemImage,
                emphasized: isSelected,
                size: 21,
                symbolSize: 11
            )
            .accessibilityHidden(true)

            Text(article.title)
                .commandlyFont(size: 11.5, weight: isSelected ? .semibold : .regular)
                .foregroundStyle(.primary)
                .lineLimit(1)

            Spacer(minLength: 0)

            if article.isEnabled == false {
                Image(systemName: "pause.circle.fill")
                    .commandlyFont(size: 9.5, weight: .medium)
                    .foregroundStyle(CommandlyTint.orange.color)
                    .accessibilityLabel("Disabled")
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .accessibilityLabel(article.title)
        .accessibilityValue(article.isEnabled ? "Available" : "Disabled")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("documentation.article-row.\(article.id)")
    }
}
