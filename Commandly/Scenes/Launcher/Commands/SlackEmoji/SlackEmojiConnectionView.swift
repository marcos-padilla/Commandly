import DesignSystem
import Infrastructure
import SwiftUI

struct SlackEmojiConnectionView: View {
    @Bindable var model: SlackEmojiViewModel
    @FocusState private var tokenFocused: Bool
    @State private var replacing = false
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Slack Workspaces").commandlyFont(size: 18, weight: .semibold).accessibilityAddTraits(.isHeader)
                Spacer(); Button(model.isCancellingConnection ? "Finishing…" : model.isChangingConnection ? "Cancel Checking" : "Done", action: model.closeConnections)
                    .disabled(model.isCancellingConnection).keyboardShortcut(.cancelAction)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let fixture = model.fixtureLabel { Label(fixture, systemImage: "testtube.2").foregroundStyle(.orange).commandlyFont(size: 11) }
                    Text("Use a dedicated internal Slack app that you own or are authorized to install in this workspace.").commandlyFont(size: 13, weight: .medium)
                    Text("Create the app in your Slack dashboard. Add only the emoji:read bot token scope, have the workspace owner approve installation if required, and paste its Bot User OAuth Token below. User tokens, browser session tokens, and app-level tokens are refused.")
                        .commandlyFont(size: 12).foregroundStyle(.secondary)
                    HStack { Button("Open Slack App Dashboard", action: model.openSetup); Button("Slack API Terms", action: model.openTerms) }.controlSize(.small)
                    Text("Check & Connect sends the token directly to Slack's identity and emoji-list APIs. Commandly verifies a bot identity and exactly emoji:read before saving it in Keychain. There is no message, channel, user-profile, or file access. No account, app, approval, or token is created for you.")
                        .commandlyFont(size: 11).foregroundStyle(.secondary)
                    if !model.workspaces.isEmpty {
                        Divider()
                        Picker("Saved workspace", selection: $model.workspaceID) { ForEach(model.workspaces) { Text($0.name).tag(Optional($0.id)) } }
                            .disabled(model.isChangingConnection)
                        if let workspace = model.workspace {
                            Text(workspace.name + " · " + workspace.id).commandlyFont(size: 11).foregroundStyle(.secondary)
                        }
                        HStack {
                            Button("Reload Saved Connections", action: model.loadConnections).disabled(model.isLoading || model.isChangingConnection)
                            Button("Remove Connection", action: model.disconnect).disabled(model.workspace == nil || model.isLoading || model.isChangingConnection)
                        }.controlSize(.small)
                        Text("Remove deletes this Mac's saved token and releases its emoji data. It does not uninstall or revoke the Slack app. Use your Slack dashboard to manage the app itself.").commandlyFont(size: 11).foregroundStyle(.secondary)
                    }
                    Picker("Connection action", selection: $replacing) {
                        Text("Add Workspace").tag(false); Text("Replace Token").tag(true)
                    }.pickerStyle(.segmented).labelsHidden().accessibilityLabel("Add a workspace or replace the selected workspace token")
                    SecureField("Internal app bot access token", text: $model.tokenInput).textFieldStyle(.roundedBorder).focused($tokenFocused)
                        .accessibilityLabel("Slack bot access token").disabled(model.isLoading || model.isChangingConnection)
                        .onSubmit { model.connect(replacing: replacing) }
                    HStack {
                        if model.isLoading || model.isChangingConnection { ProgressView().controlSize(.small) }
                        Text(model.fixtureLabel == nil ? "Saved tokens are never shown here." : "Generated connection only; no Keychain or Slack request.").commandlyFont(size: 10).foregroundStyle(.secondary)
                        Spacer()
                        Button(replacing ? "Check & Replace" : "Check & Connect") { model.connect(replacing: replacing) }
                            .buttonStyle(.borderedProminent).disabled(model.tokenInput.isEmpty || model.isLoading || model.isChangingConnection || replacing && model.workspace == nil)
                    }
                    if let error = model.errorMessage { Text(error).commandlyFont(size: 11).foregroundStyle(.orange) }
                    if let status = model.statusMessage { Text(status).commandlyFont(size: 11).foregroundStyle(.secondary) }
                    Text("Refresh is explicit. Names, aliases, and previews stay in memory and are cleared when you leave. Search text never leaves this Mac. Selected media requests reach Slack's image hosts without the bot token. Copy and Save are separate user actions; nothing is posted to Slack. Rotating access tokens must be replaced when they expire.")
                        .commandlyFont(size: 11).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
            }
        }.padding(22).frame(width: 600).frame(maxHeight: 560)
            .onAppear { DispatchQueue.main.async { tokenFocused = true } }
            .accessibilityElement(children: .contain).accessibilityLabel("Internal Slack workspace connections")
    }
}
