import SwiftUI
import DesignSystem
import SecurityKit

struct PermissionsSettingsPage: View {
    @Bindable var viewModel: SettingsViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.sm.rawValue) {
                SettingsPageHeader(title: viewModel.selectedPane.title, subtitle: viewModel.selectedPane.subtitle)

                permissionCard(
                    kind: .calendar,
                    icon: "calendar",
                    color: .red,
                    title: "Calendar",
                    subtitle: "Surface upcoming meetings from the launcher."
                )

                permissionCard(
                    kind: .contacts,
                    icon: "person.crop.circle",
                    color: .orange,
                    title: "Contacts",
                    subtitle: "Find people quickly without leaving the keyboard."
                )

                permissionCard(
                    kind: .files,
                    icon: "folder.fill",
                    color: .blue,
                    title: "Files and Folders",
                    subtitle: "Search folders you explicitly allow Commandly to use."
                )

                permissionCard(
                    kind: .accessibility,
                    icon: "accessibility",
                    color: .purple,
                    title: "Accessibility",
                    subtitle: "Enable window layouts and deeper keyboard automation."
                )
            }
            .padding(Spacing.lg.rawValue)
        }
    }

    private func permissionCard(
        kind: PermissionKind,
        icon: String,
        color: Color,
        title: String,
        subtitle: String
    ) -> some View {
        let state = viewModel.state(for: kind)
        return SettingsCard {
            SettingsActionRow(
                icon: icon,
                iconColor: color,
                title: title,
                subtitle: subtitle,
                actionTitle: actionTitle(for: state),
                actionDisabled: state == .authorized,
                action: { viewModel.requestPermission(kind) }
            )
        }
    }

    private func actionTitle(for state: PermissionState) -> String {
        switch state {
        case .authorized:
            return "Granted"
        case .denied, .restricted:
            return "Open Settings"
        case .notDetermined:
            return "Grant Access"
        }
    }
}
