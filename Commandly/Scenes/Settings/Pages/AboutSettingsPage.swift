import SwiftUI
import DesignSystem
import AppCore

struct AboutSettingsPage: View {
    @Bindable var viewModel: SettingsViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.sm.rawValue) {
                SettingsPageHeader(title: viewModel.selectedPane.title, subtitle: viewModel.selectedPane.subtitle)

                SettingsCard {
                    HStack(spacing: Spacing.md.rawValue) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(BrandPalette.accent.gradient)
                                .frame(width: 52, height: 52)
                            Image(systemName: "command")
                                .font(.system(size: 22, weight: .bold))
                                .foregroundStyle(.white)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text(viewModel.metadata.name)
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                            Text("Version \(viewModel.metadata.version) (\(viewModel.metadata.build))")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                            Text(viewModel.metadata.bundleIdentifier)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.tertiary)
                        }

                        Spacer()
                    }
                }

                SettingsCard {
                    VStack(alignment: .leading, spacing: Spacing.xs.rawValue) {
                        Text("A keyboard-first productivity launcher for macOS.")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                        Text("Private by design. Built to feel fast and dependable.")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(Spacing.lg.rawValue)
        }
    }
}
