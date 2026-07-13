import DesignSystem
import SwiftUI

struct DocumentationTopBar: View {
    static let titlebarInset: CGFloat = 28
    static let height: CGFloat = 38

    let article: DocumentationArticle?
    let isSidebarVisible: Bool
    let onToggleSidebar: () -> Void
    let onFocusSearch: () -> Void

    var body: some View {
        HStack(spacing: 9) {
            Button(action: onToggleSidebar) {
                Image(systemName: "sidebar.left")
                    .symbolVariant(isSidebarVisible ? .fill : .none)
                    .commandlyFont(size: 11, weight: .semibold)
                    .frame(width: 26, height: 24)
            }
            .buttonStyle(.glass)
            .controlSize(.small)
            .help(isSidebarVisible ? "Hide Sidebar" : "Show Sidebar")
            .accessibilityIdentifier("documentation.sidebar.toggle")
            .accessibilityLabel(isSidebarVisible ? "Hide sidebar" : "Show sidebar")

            Rectangle()
                .fill(SettingsPalette.border)
                .frame(width: 1, height: 16)

            if let article {
                Image(systemName: article.systemImage)
                    .symbolVariant(.fill)
                    .commandlyFont(size: 9.5, weight: .semibold)
                    .foregroundStyle(BrandPalette.accentSoft)
                    .frame(width: 15)

                Text(article.title)
                    .commandlyFont(size: 10.5, weight: .semibold)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .contentTransition(.opacity)
            }

            Spacer(minLength: 0)

            Button(action: onFocusSearch) {
                Label("Find", systemImage: "magnifyingglass")
                    .labelStyle(.titleAndIcon)
                    .commandlyFont(size: 10, weight: .medium)
            }
            .buttonStyle(.glass)
            .controlSize(.small)
            .keyboardShortcut("f", modifiers: .command)
            .help("Search Documentation (Command F)")
        }
        .padding(.horizontal, 10)
        .frame(height: Self.height)
        .background {
            ZStack {
                SettingsPalette.card.opacity(0.72)
                LinearGradient(
                    colors: [Color.white.opacity(0.035), BrandPalette.accent.opacity(0.025)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            }
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(SettingsPalette.border).frame(height: 1)
        }
        .accessibilityElement(children: .contain)
    }
}

