import CommandKit
import DesignSystem
import SwiftUI

struct DocumentationArticleView: View {
    let article: DocumentationArticle
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Spacing.xl.rawValue) {
                    articleHeader

                    if article.documentation.sections.count > 1 {
                        sectionNavigation(proxy: proxy)
                    }

                    if showsApplicationMetadata {
                        applicationMetadata
                    }

                    ForEach(article.documentation.sections) { section in
                        DocumentationSectionCard(section: section)
                            .id(section.id)
                    }
                }
                .frame(maxWidth: 720, alignment: .leading)
                .padding(.horizontal, Spacing.xl.rawValue + Spacing.xxs.rawValue)
                .padding(.top, Spacing.md.rawValue)
                .padding(.bottom, Spacing.xxl.rawValue)
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .scrollIndicators(.automatic)
            .accessibilityIdentifier("documentation.article")
        }
    }

    private var articleHeader: some View {
        VStack(alignment: .leading, spacing: Spacing.xs.rawValue) {
            HStack(spacing: Spacing.xs.rawValue) {
                DocumentationGlyph(
                    systemImage: article.systemImage,
                    size: 20,
                    symbolSize: 12
                )
                .accessibilityHidden(true)

                Text(article.category.title.uppercased())
                    .commandlyFont(size: 9, weight: .semibold)
                    .foregroundStyle(.tertiary)
                    .tracking(0.9)

                if let statusLabel = article.statusLabel {
                    Spacer(minLength: Spacing.xs.rawValue)
                    DocumentationBadge(
                        label: statusLabel,
                        color: article.isEnabled
                            ? Color.secondary
                            : CommandlyTint.orange.color
                    )
                }
            }

            Text(article.title)
                .commandlyFont(size: 27, weight: .semibold)
                .foregroundStyle(.primary)
                .accessibilityAddTraits(.isHeader)

            if let subtitle = article.subtitle {
                Text(subtitle)
                    .commandlyFont(size: 12.5, weight: .medium)
                    .foregroundStyle(.secondary)
            }

            Text(article.documentation.overview)
                .commandlyFont(size: 12.5)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(3)
                .padding(.top, Spacing.xxs.rawValue)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func sectionNavigation(proxy: ScrollViewProxy) -> some View {
        ScrollView(.horizontal) {
            HStack(spacing: Spacing.xxs.rawValue) {
                ForEach(article.documentation.sections) { section in
                    Button {
                        withAnimation(reduceMotion ? nil : CommandlyMotion.navigation) {
                            proxy.scrollTo(section.id, anchor: .top)
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Text(section.title)
                            Image(systemName: "arrow.down")
                                .commandlyFont(size: 8, weight: .semibold)
                                .accessibilityHidden(true)
                        }
                        .commandlyFont(size: 10.5, weight: .medium)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, Spacing.xs.rawValue)
                        .frame(height: 26)
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .help("Jump to \(section.title)")
                }
            }
            .padding(.vertical, Spacing.xxs.rawValue)
        }
        .scrollIndicators(.hidden)
        .accessibilityLabel("Article sections")
    }

    private var showsApplicationMetadata: Bool {
        article.applicationID != nil
            && (article.alias != nil
                || article.globalHotKey != nil
                || article.defaultActions.isEmpty == false
                || article.configurationFields.isEmpty == false
                || article.isEnabled == false)
    }

    private var applicationMetadata: some View {
        DocumentationSurfaceCard {
            VStack(alignment: .leading, spacing: Spacing.md.rawValue) {
                DocumentationSectionHeading(icon: "slider.horizontal.3", title: "Your setup")

                if article.isEnabled == false {
                    DocumentationInlineNotice(
                        icon: "pause.circle.fill",
                        title: "This application is disabled",
                        text: "Enable it from Settings → Applications before launching it."
                    )
                }

                if article.alias != nil || article.globalHotKey != nil {
                    HStack(spacing: Spacing.xl.rawValue) {
                        if let alias = article.alias {
                            DocumentationMetadataPill(icon: "text.cursor", label: "Alias", value: alias)
                        }
                        if let hotKey = article.globalHotKey {
                            DocumentationMetadataPill(icon: "keyboard", label: "Global shortcut", value: hotKey)
                        }
                    }
                }

                if article.defaultActions.isEmpty == false {
                    VStack(alignment: .leading, spacing: Spacing.xs.rawValue) {
                        Text("DEFAULT ACTIONS")
                            .commandlyFont(size: 8.5, weight: .semibold)
                            .tracking(0.8)
                            .foregroundStyle(.quaternary)
                            .accessibilityAddTraits(.isHeader)
                        ForEach(article.defaultActions) { action in
                            DocumentationShortcutRow(
                                title: action.title,
                                keys: action.keyHint?.symbols ?? [],
                                detail: action.isPrimary ? "Primary action" : nil
                            )
                        }
                    }
                }

                if article.configurationFields.isEmpty == false {
                    VStack(alignment: .leading, spacing: Spacing.xs.rawValue) {
                        Text("CONFIGURATION")
                            .commandlyFont(size: 8.5, weight: .semibold)
                            .tracking(0.8)
                            .foregroundStyle(.quaternary)
                            .accessibilityAddTraits(.isHeader)
                        ForEach(article.configurationFields) { field in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(field.title)
                                    .commandlyFont(size: 11.5, weight: .semibold)
                                if let description = field.description {
                                    Text(description)
                                        .commandlyFont(size: 10.5)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
