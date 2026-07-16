import DesignSystem
import SwiftUI

/// Neutral presentation roles shared by the Documentation sidebar and reading canvas.
///
/// Documentation follows Settings: system accent is reserved for selection and focus,
/// while semantic color appears only when a status or callout needs it.
enum DocumentationVisualStyle {
    static let canvas = SettingsPalette.canvas
    static let sidebar = SettingsPalette.sidebar
    static let detail = SettingsPalette.detail
    static let field = SettingsPalette.field
    static let separator = SettingsPalette.border
    static let hover = SettingsPalette.hover
    static let focusRing = SettingsPalette.focusRing
}

extension DocumentationCalloutKind {
    var documentationTint: CommandlyTint {
        switch self {
        case .tip: .yellow
        case .privacy: .green
        case .permission: .orange
        case .limitation: .indigo
        case .important: .red
        }
    }
}

/// A compact, monochrome filled symbol shared by Documentation navigation and headings.
struct DocumentationGlyph: View {
    let systemImage: String
    var emphasized = false
    var size: CGFloat = 22
    var symbolSize: CGFloat = 11

    var body: some View {
        Image(systemName: systemImage)
            .symbolVariant(.fill)
            .symbolRenderingMode(.hierarchical)
            .commandlyFont(size: symbolSize, weight: .medium)
            .foregroundStyle(emphasized ? Color.primary : Color.secondary)
            .frame(width: size, height: size)
    }
}
