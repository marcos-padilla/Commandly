import SwiftUI
import DesignSystem
import AppCore

struct AboutSettingsPage: View {
    @Bindable var viewModel: SettingsViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.sm.rawValue) {
                SettingsPageHeader(
                    title: viewModel.selectedPane.title,
                    subtitle: viewModel.selectedPane.subtitle
                )

                SettingsCard {
                    VStack(alignment: .leading, spacing: Spacing.xs.rawValue) {
                        Text(viewModel.metadata.name)
                            .commandlyFont(size: 14, weight: .semibold)
                        Text("Version \(viewModel.metadata.version) (\(viewModel.metadata.build))")
                            .commandlyFont(size: 11)
                            .foregroundStyle(.secondary)
                        Text(viewModel.metadata.bundleIdentifier)
                            .commandlyFont(size: 10, design: .monospaced)
                            .foregroundStyle(.tertiary)
                            .padding(.top, 2)

                        Text("A keyboard-first productivity launcher for macOS.")
                            .commandlyFont(size: 11)
                            .foregroundStyle(.tertiary)
                            .padding(.top, Spacing.xs.rawValue)
                    }
                    .padding(.vertical, 6)
                }
            }
            .padding(.horizontal, Spacing.md.rawValue)
            .padding(.vertical, Spacing.md.rawValue)
        }
    }
}
