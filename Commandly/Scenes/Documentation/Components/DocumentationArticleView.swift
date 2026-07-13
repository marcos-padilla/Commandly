import CommandKit
import DesignSystem
import SwiftUI

struct DocumentationArticleView: View {
    let article: DocumentationArticle
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                GlassEffectContainer(spacing: 18) {
                    LazyVStack(alignment: .leading, spacing: 18) {
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
                }
                .frame(maxWidth: 840, alignment: .leading)
                .padding(.horizontal, 34)
                .padding(.top, 28)
                .padding(.bottom, 44)
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .scrollIndicators(.automatic)
            .accessibilityIdentifier("documentation.article")
        }
    }

    private var articleHeader: some View {
        HStack(alignment: .top, spacing: 18) {
            Image(systemName: article.systemImage)
                .symbolVariant(.fill)
                .commandlyFont(size: 25, weight: .semibold)
                .foregroundStyle(BrandPalette.accentSoft)
                .frame(width: 54, height: 54)
                .background {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(BrandPalette.accent.opacity(0.12))
                }
                .glassEffect(
                    .regular.tint(BrandPalette.accent.opacity(0.08)),
                    in: .rect(cornerRadius: 16)
                )
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                Text(article.category.title.uppercased())
                    .commandlyFont(size: 9, weight: .semibold)
                    .foregroundStyle(BrandPalette.accentSoft)
                    .tracking(1.05)

                HStack(alignment: .firstTextBaseline, spacing: 9) {
                    Text(article.title)
                        .commandlyFont(size: 25, weight: .semibold)
                        .accessibilityAddTraits(.isHeader)

                    if let statusLabel = article.statusLabel {
                        DocumentationBadge(
                            label: statusLabel,
                            color: article.isEnabled ? .green : .orange
                        )
                    }
                }

                if let subtitle = article.subtitle {
                    Text(subtitle)
                        .commandlyFont(size: 12.5, weight: .medium)
                        .foregroundStyle(.secondary)
                }

                Text(article.documentation.overview)
                    .commandlyFont(size: 12)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func sectionNavigation(proxy: ScrollViewProxy) -> some View {
        ScrollView(.horizontal) {
            HStack(spacing: 7) {
                ForEach(article.documentation.sections) { section in
                    Button(section.title) {
                        withAnimation(
                            reduceMotion
                                ? nil
                                : .easeInOut(duration: MotionDuration.normal.rawValue)
                        ) {
                            proxy.scrollTo(section.id, anchor: .top)
                        }
                    }
                    .buttonStyle(.glass)
                    .controlSize(.small)
                }
            }
            .padding(.vertical, 2)
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
        DocumentationGlassCard {
            VStack(alignment: .leading, spacing: 13) {
                DocumentationSectionHeading(icon: "slider.horizontal.3", title: "Your setup")

                if article.isEnabled == false {
                    DocumentationInlineNotice(
                        icon: "pause.circle.fill",
                        title: "This application is disabled",
                        text: "Enable it from Settings → Applications before launching it."
                    )
                }

                if article.alias != nil || article.globalHotKey != nil {
                    HStack(spacing: 10) {
                        if let alias = article.alias {
                            DocumentationMetadataPill(icon: "text.cursor", label: "Alias", value: alias)
                        }
                        if let hotKey = article.globalHotKey {
                            DocumentationMetadataPill(icon: "keyboard", label: "Global shortcut", value: hotKey)
                        }
                    }
                }

                if article.defaultActions.isEmpty == false {
                    VStack(alignment: .leading, spacing: 8) {
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
                    VStack(alignment: .leading, spacing: 8) {
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
