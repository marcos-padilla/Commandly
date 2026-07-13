import DesignSystem
import SecurityKit
import SwiftUI

struct PermissionsSettingsPage: View {
    @Bindable var viewModel: SettingsViewModel

    var body: some View {
        ScrollView {
            GlassEffectContainer(spacing: Spacing.sm.rawValue) {
                VStack(alignment: .leading, spacing: Spacing.sm.rawValue) {
                    SettingsPageHeader(
                        title: viewModel.selectedPane.title,
                        subtitle: viewModel.selectedPane.subtitle
                    )

                    SettingsCard {
                        permissionRow(
                            kind: .calendar,
                            icon: "calendar",
                            title: "Calendar",
                            subtitle: "Upcoming meetings in the launcher."
                        )

                        SettingsDivider()

                        permissionRow(
                            kind: .contacts,
                            icon: "person",
                            title: "Contacts",
                            subtitle: "Find people from the keyboard."
                        )

                        SettingsDivider()

                        permissionRow(
                            kind: .files,
                            icon: "folder",
                            title: "Files and Folders",
                            subtitle: "Search and manage folders you allow."
                        )

                        SettingsDivider()

                        permissionRow(
                            kind: .accessibility,
                            icon: "accessibility",
                            title: "Accessibility",
                            subtitle: "Window layouts and automation."
                        )
                    }
                }
            }
            .padding(.horizontal, Spacing.md.rawValue)
            .padding(.vertical, Spacing.md.rawValue)
        }
    }

    private func permissionRow(
        kind: PermissionKind,
        icon: String,
        title: String,
        subtitle: String
    ) -> some View {
        let state = viewModel.state(for: kind)
        return SettingsActionRow(
            icon: icon,
            title: title,
            subtitle: subtitle,
            actionTitle: actionTitle(for: state, kind: kind),
            actionDisabled: state == .authorized && kind != .files,
            action: { viewModel.requestPermission(kind) }
        )
        .animation(.easeInOut(duration: MotionDuration.normal.rawValue), value: state)
    }

    private func actionTitle(for state: PermissionState, kind: PermissionKind) -> String {
        switch state {
        case .authorized:
            return kind == .files ? "Manage Folders" : "Granted"
        case .denied, .restricted:
            return "Open Settings"
        case .notDetermined:
            return "Grant Access"
        }
    }
}
