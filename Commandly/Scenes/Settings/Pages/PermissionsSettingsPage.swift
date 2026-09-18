import DesignSystem
import SecurityKit
import SwiftUI

struct PermissionsSettingsPage: View {
    @Bindable var viewModel: SettingsViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        SettingsPageLayout(maxWidth: 720) {
            SettingsSection(
                "System Access",
                footer: "Commandly asks only when you use a feature that needs access. You can review or revoke access in System Settings at any time."
            ) {
                permissionRow(
                    kind: .calendar,
                    icon: "calendar",
                    title: "Calendar",
                    subtitle: "Upcoming meetings in the launcher."
                )

                SettingsDivider()

                permissionRow(
                    kind: .camera,
                    icon: "camera",
                    title: "Camera",
                    subtitle: "Preview your camera and capture a selfie when you start Camera."
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
                    subtitle: viewModel.windowSwitcherIsAvailable
                        ? "Window layouts, switching, and explicitly enabled input highlighting."
                        : "Window layouts and explicitly enabled input highlighting."
                )

                SettingsDivider()

                permissionRow(
                    kind: .screenRecording,
                    icon: "record.circle",
                    title: "Screen Recording",
                    subtitle: viewModel.windowSwitcherIsAvailable
                        ? "Selected screenshot regions and live Window Switcher previews."
                        : "Capture a region you select. Window and display screenshots use the macOS picker."
                )
            }
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
        .animation(
            reduceMotion ? nil : .easeInOut(duration: MotionDuration.normal.rawValue),
            value: state
        )
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
