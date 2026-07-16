import DesignSystem
import SwiftUI

/// Compact, transparent Settings header aligned with the sidebar search region.
struct SettingsTopBar: View {
    static let height: CGFloat = 58

    let selectedPane: SettingsPane

    var body: some View {
        HStack {
            Text(selectedPane.title)
                .commandlyFont(size: 17, weight: .semibold)
                .foregroundStyle(.primary)
                .contentTransition(.opacity)
                .accessibilityAddTraits(.isHeader)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, Spacing.lg.rawValue + Spacing.xs.rawValue)
        .frame(height: Self.height)
        .background(Color.clear)
        .accessibilityElement(children: .contain)
    }
}

#Preview {
    SettingsTopBar(selectedPane: .applications)
        .frame(width: 760, height: SettingsTopBar.height)
        .background(SettingsVisualStyle.detailBackground)
}
