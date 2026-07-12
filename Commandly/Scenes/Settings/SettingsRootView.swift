import SwiftUI
import DesignSystem

struct SettingsRootView: View {
    var body: some View {
        Form {
            Section {
                Text("Commandly settings will appear here once feature development begins.")
                    .foregroundStyle(SemanticColors.color(for: .secondaryText))
            } header: {
                Text("Foundation")
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: LayoutConstants.settingsMinWidth, minHeight: 280)
        .padding(Spacing.md.rawValue)
    }
}

#Preview {
    SettingsRootView()
}
