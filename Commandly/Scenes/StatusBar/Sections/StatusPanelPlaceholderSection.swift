import DesignSystem
import SwiftUI

/// Body shown for a panel tab whose controls have not been built yet.
///
/// The panel's navigation is complete before its sections are, so this states plainly that the
/// tab is still empty rather than showing controls that do nothing.
struct StatusPanelPlaceholderSection: View {
    let section: StatusPanelSection

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs.rawValue) {
            HStack(spacing: Spacing.xs.rawValue) {
                Image(systemName: section.symbolName)
                    .commandlyFont(size: 15, weight: .medium)
                    .foregroundStyle(.secondary)
                    .frame(width: 22)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(section.title)
                        .commandlyFont(size: 12.5, weight: .semibold)
                    Text(section.summary)
                        .commandlyFont(size: 10.5)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            Divider()

            Text("This section is not built yet. Its tab is here so the panel's navigation stays stable while the controls are added.")
                .commandlyFont(size: 10.5)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .statusPanelCard()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(section.title). Not available yet.")
    }
}
