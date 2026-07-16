import DesignSystem
import SwiftUI

/// A flat Documentation header aligned with the sidebar search region.
///
/// Navigation controls live in AppKit's native titlebar lane so this content header
/// remains quiet and visually consistent with Settings.
struct DocumentationTopBar: View {
    static let height: CGFloat = 58

    var body: some View {
        HStack {
            Text("Documentation")
                .commandlyFont(size: 17, weight: .semibold)
                .foregroundStyle(.primary)
                .accessibilityAddTraits(.isHeader)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, Spacing.lg.rawValue + Spacing.xs.rawValue)
        .frame(height: Self.height)
        .background(Color.clear)
        .accessibilityElement(children: .contain)
    }
}
