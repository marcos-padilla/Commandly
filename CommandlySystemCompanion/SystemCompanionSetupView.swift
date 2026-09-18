import Infrastructure
import SwiftUI

struct SystemCompanionSetupView: View {
    @Bindable var model: SystemCompanionSetupModel
    let close: () -> Void
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: "link.badge.plus").font(.largeTitle).foregroundStyle(.tint).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Commandly Companion Setup").font(.title2.bold()).accessibilityAddTraits(.isHeader)
                        Text("Manage the optional background service for your login account.").foregroundStyle(.secondary)
                    }
                }
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        Label(model.stateTitle, systemImage: model.snapshot.state == .enabled ? "checkmark.shield" : "gearshape")
                            .font(.headline).accessibilityAddTraits(.isHeader).accessibilityIdentifier("companionSetup.status")
                        Text("The main Commandly app stays sandboxed. This separately signed companion runs outside that sandbox as your user. This build supports connection metadata only.")
                        Text("Enabling the background service does not grant Accessibility, Input Monitoring, microphone, or screen recording access.")
                            .foregroundStyle(.secondary)
                        if model.isBusy { ProgressView().controlSize(.small).accessibilityLabel("Updating background service") }
                        if let message = model.message { Text(message).foregroundStyle(.secondary).accessibilityIdentifier("companionSetup.message") }
                        if let diagnostic = model.snapshot.diagnostic {
                            Text("macOS diagnostic: \(diagnostic.domain.rawValue) / \(diagnostic.code)")
                                .font(.callout.monospaced()).textSelection(.enabled)
                                .accessibilityIdentifier("companionSetup.diagnostic")
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
                }
                CompanionKeyboardPermissionSection()
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) { serviceControls }
                    VStack(alignment: .leading, spacing: 12) { serviceControls }
                }
                HStack(spacing: 12) {
                    Button("Refresh") { model.refresh() }.disabled(model.isBusy)
                        .accessibilityIdentifier("companionSetup.refresh")
                    Button("Login Items Settings") { model.openSettings() }.disabled(model.isBusy)
                        .accessibilityIdentifier("companionSetup.loginItems")
                }
                Text("After enabling, return to Commandly → Settings → System Integration and choose Check Connection. Closing this window keeps the registration. Use Disable Background Service here before uninstalling; privacy grants are managed separately in macOS Settings.")
                    .font(.callout).foregroundStyle(.secondary)
                HStack { Spacer(); Button("Close") { close() }.keyboardShortcut(.cancelAction).disabled(model.isBusy) }
            }.padding(26)
        }
        .frame(minWidth: 490, minHeight: 440)
        .alert("Enable Background Service?", isPresented: $model.showsEnableExplanation) {
            Button("Enable Background Service") { model.confirmEnable() }
                .accessibilityIdentifier("companionSetup.confirmEnable")
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This companion app will register its bundled per-user LaunchAgent. macOS may ask for approval in Login Items. Only metadata connections are implemented; no other app or private field is read. Disable here removes the registration.")
        }
    }
    @ViewBuilder private var serviceControls: some View {
        Button("Enable Background Service") { model.requestEnable() }
            .buttonStyle(.borderedProminent)
            .disabled(model.isBusy || model.snapshot.state == .enabled || model.snapshot.state == .needsApproval)
            .accessibilityIdentifier("companionSetup.enable")
        Button("Disable Background Service") { model.disable() }
            .disabled(model.isBusy || model.snapshot.state == .disabled)
            .accessibilityIdentifier("companionSetup.disable")
    }
}
