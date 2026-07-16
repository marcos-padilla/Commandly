import AppCore
import DesignSystem
import SwiftUI

struct AboutSettingsPage: View {
    @Bindable var viewModel: SettingsViewModel

    var body: some View {
        SettingsPageLayout(maxWidth: 640) {
            VStack(spacing: Spacing.md.rawValue) {
                CommandlyApplicationIcon(size: 72)

                VStack(spacing: 4) {
                    Text(viewModel.metadata.name)
                        .commandlyFont(size: 17, weight: .semibold)
                        .accessibilityAddTraits(.isHeader)

                    Text("Version \(viewModel.metadata.version) (\(viewModel.metadata.build))")
                        .commandlyFont(size: 11)
                        .foregroundStyle(.secondary)

                    Text(viewModel.metadata.bundleIdentifier)
                        .commandlyFont(size: 10, design: .monospaced)
                        .foregroundStyle(.tertiary)
                        .textSelection(.enabled)
                }

                Divider()
                    .overlay(SettingsVisualStyle.separator)
                    .frame(maxWidth: 320)
                    .padding(.vertical, Spacing.xs.rawValue)

                Text("A keyboard-first productivity launcher for macOS.")
                    .commandlyFont(size: 11)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, Spacing.lg.rawValue)
            .accessibilityElement(children: .contain)
        }
    }
}
