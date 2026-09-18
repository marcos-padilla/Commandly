import DesignSystem
import Infrastructure
import SwiftUI

struct SystemIntegrationSettingsPage: View {
    @Bindable var model: SystemIntegrationSettingsModel
    var keyboardTriggers: KeyboardTriggerSettingsModel? = nil
    var body: some View {
        SettingsPageLayout(maxWidth: 720) {
            SettingsSection("Optional System Companion",
                footer: "The main Commandly app stays sandboxed. This optional companion runs as your user, outside that sandbox. Enabling it does not grant Accessibility, Input Monitoring, or screen capture access.") {
                VStack(alignment: .leading, spacing: 12) {
                    Label(model.stateTitle, systemImage: model.snapshot.state == .ready ? "checkmark.shield" : "link")
                        .commandlyFont(size: 15, weight: .semibold)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("systemIntegration.status")
                    Text("Enable or disable the background service in Companion Setup. Opening setup does not enable it. Check Connection verifies the signed companion channel. Each available capability stays off until you enable it below.")
                        .commandlyFont(size: 12)
                        .foregroundStyle(.secondary)
                    if model.isFixture {
                        Label("Generated setup fixture — no helper registration or native connection", systemImage: "testtube.2")
                            .commandlyFont(size: 11).foregroundStyle(.secondary)
                    }
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 12) { controls }
                        VStack(alignment: .leading, spacing: 8) { controls }
                    }
                    if model.isBusy { ProgressView().controlSize(.small).accessibilityLabel("Updating companion status") }
                    if let message = model.message {
                        Text(message).commandlyFont(size: 12).foregroundStyle(.secondary)
                            .accessibilityIdentifier("systemIntegration.message")
                    }
                }.padding(14)
            }
            if let keyboardTriggers { KeyboardTriggerSettingsSection(model: keyboardTriggers) }
            SettingsSection("Capability Access",
                footer: "Window Layouts remembers only an external app identity while enabled. Apply reads and changes its currently focused window. Other capabilities remain unavailable.") {
                VStack(alignment: .leading, spacing: 10) {
                    capability("Connection metadata", detail: model.snapshot.state == .ready ? "Verified in the last connection check" : "Available after an authenticated connection check", icon: "info.circle")
                    Toggle(isOn: Binding(get: { model.windowLayoutsEnabled }, set: { model.setWindowLayoutsEnabled($0) })) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Window Layouts").commandlyFont(size: 12, weight: .medium)
                            Text(model.canChangeWindowLayouts ? "Off by default for every connection. Requires Accessibility for Commandly System Companion when applying a layout." : "Unavailable in this build or connection. The companion capability must pass review before it can be enabled.")
                                .commandlyFont(size: 11).foregroundStyle(.secondary)
                        }
                    }
                    .toggleStyle(.switch)
                    .disabled(model.isBusy || model.canChangeWindowLayouts == false)
                    .accessibilityIdentifier("systemIntegration.windowLayouts")
                    .accessibilityHint("Explicitly enables window layouts for the current companion connection")
                    Button("Accessibility Settings") { model.openWindowAccessibilitySettings() }
                        .accessibilityIdentifier("systemIntegration.windowAccessibility")
                    Toggle("App Menus", isOn: Binding(get: { model.appMenusEnabled }, set: model.setAppMenusEnabled))
                        .disabled(model.isBusy || !model.canChangeAppMenus)
                        .accessibilityIdentifier("systemIntegration.appMenus")
                        .help("Enable current-app menu search for this companion connection")
                    Text("Read menu commands only when you open App Menus or choose Read Menus. Invoking a command can change the target app’s data. Accessibility permission is checked without prompting.")
                        .commandlyFont(size: 11).foregroundStyle(.secondary)
                    capability("Selected text", detail: "Not implemented", icon: "text.cursor")
                    capability("Configured keyboard triggers", detail: "Optional — configure bindings and enable explicitly above", icon: "keyboard")
                }.padding(14)
            }
            Text("Disconnect closes only this app’s channel; it does not stop the background service or revoke permissions. To stop or uninstall it, open Companion Setup and choose Disable Background Service. macOS privacy permissions are managed separately in System Settings.")
                .commandlyFont(size: 11).foregroundStyle(.secondary)
        }
        .task { model.refresh() }
    }
    @ViewBuilder private var controls: some View {
        Button("Companion Setup") { model.openSetup() }
            .accessibilityIdentifier("systemIntegration.setup")
            .disabled(model.isBusy)
        Button("Check Connection") { model.checkConnection() }
            .accessibilityIdentifier("systemIntegration.check")
            .disabled(model.isBusy)
        if model.snapshot.state == .ready {
            Button("Disconnect") { model.disconnect() }
                .accessibilityIdentifier("systemIntegration.disconnect")
                .disabled(model.isBusy)
        }
        Button("Refresh") { model.refresh() }.disabled(model.isBusy)
            .accessibilityIdentifier("systemIntegration.refresh")
        Button("Login Items Settings") { model.openApprovalSettings() }.disabled(model.isBusy)
            .accessibilityIdentifier("systemIntegration.loginItems")
    }
    private func capability(_ title: String, detail: String, icon: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon).frame(width: 22).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).commandlyFont(size: 12, weight: .medium)
                Text(detail).commandlyFont(size: 11).foregroundStyle(.secondary)
            }
        }.accessibilityElement(children: .combine)
    }
}
