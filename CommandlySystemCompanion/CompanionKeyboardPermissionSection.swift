import Infrastructure
import SwiftUI
import SystemCompanionKit

/// The sole keyboard permission prompt is behind this visible explanatory action in companion setup.
struct CompanionKeyboardPermissionSection: View {
    @State private var showsExplanation = false
    var body: some View {
        if CompanionKeyboardTriggerReleaseGate.reviewed {
            GroupBox("Keyboard Trigger Access") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Configured keyboard triggers need Input Monitoring and Accessibility. The companion sees subscribed events before filtering, passes unrelated keys through, and stores no typing history. Granting access does not enable triggers; choose your bindings and Enable in Commandly Settings.")
                        .font(.callout).foregroundStyle(.secondary)
                    Button("Review Keyboard Access…") { showsExplanation = true }
                        .accessibilityIdentifier("companionSetup.keyboardAccess")
                }.padding(8)
            }
            .alert("Review keyboard access?", isPresented: $showsExplanation) {
                Button("Continue to macOS Access") { CompanionKeyboardPermissions.requestFromVisibleSetup() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("macOS will request access for this companion. Enable only if you want configured key remapping or automatic expansion. You can revoke access in System Settings → Privacy & Security at any time.")
            }
        }
    }
}
