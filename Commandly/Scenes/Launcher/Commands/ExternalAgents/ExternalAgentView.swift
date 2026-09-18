import AIKit
import DesignSystem
import SwiftUI

struct ExternalAgentView: View {
    @Bindable var model: ExternalAgentViewModel
    @FocusState private var focused: Bool
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                CommandlyBackButton(action: model.goBack)
                Image(systemName: "point.3.connected.trianglepath.dotted").foregroundStyle(BrandPalette.accentSoft)
                Text(model.kind.title + " Agent").commandlyFont(size: 14, weight: .semibold)
                Spacer()
                Button("Connection") { model.showsConnection = true }.disabled(model.busy)
                Button { model.newConversation(); focused = true } label: { Image(systemName: "square.and.pencil") }
                    .accessibilityLabel("New agent conversation").disabled(model.busy || model.target.isEmpty)
            }.padding(14).background(LauncherPalette.chrome)
            Divider()
            if model.showsConnection || model.connection == nil { connectionForm }
            else { chat }
        }
        .onAppear { model.start(); focused = true }
        .onDisappear { model.stop() }
        .accessibilityElement(children: .contain).accessibilityLabel(model.kind.title + " agent chat")
    }
    private var connectionForm: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Bring your agent into Commandly").commandlyFont(size: 21, weight: .semibold)
                Text("Connect your own \(model.kind.title) API server. Check & Connect reads its available agents; it does not start an agent run.")
                    .commandlyFont(size: 12).foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 6) {
                    Text("API base URL").commandlyFont(size: 11, weight: .semibold)
                    TextField(model.kind.suggestedEndpoint, text: $model.endpoint).textFieldStyle(.roundedBorder)
                        .accessibilityLabel("Agent API base URL")
                    Text("Use HTTPS for a private remote server, or HTTP on this Mac. Include /v1 and any configured profile prefix.")
                        .commandlyFont(size: 10).foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Bearer token or password").commandlyFont(size: 11, weight: .semibold)
                    SecureField("Stored in Keychain after verification", text: $model.token).textFieldStyle(.roundedBorder)
                        .onSubmit(model.connect).accessibilityLabel("Agent server credential")
                }
                Text("Sending a message can run tools on your agent server under its permissions. Review its tool and approval policy before connecting. Commandly never supplies local tools or approves requests for you.")
                    .commandlyFont(size: 11).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if let url = model.kind.setupURL { Link("API server setup guide", destination: url) }
                HStack {
                    Button("Check & Connect", action: model.connect).buttonStyle(.borderedProminent)
                        .disabled(model.busy || model.token.isEmpty)
                    if model.busy { ProgressView().controlSize(.small); Button("Cancel", action: model.cancel) }
                    else {
                        Button("Reload Saved Connection", action: model.reload)
                        if model.connection != nil { Button("Done", action: model.closeConnection) }
                    }
                }
                if model.connection != nil {
                    Button("Remove Local Connection", role: .destructive, action: model.disconnect).disabled(model.busy)
                }
                status
            }.padding(24).frame(maxWidth: 590, alignment: .leading).frame(maxWidth: .infinity)
        }.background(LauncherPalette.detail)
    }
    private var chat: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                CommandlyOptionMenu(items: model.targets.map { .init(id: $0, title: $0) }, selectionID: model.target,
                    placeholderTitle: "Choose an agent", searchPrompt: "Find an agent…", accessibilityLabelText: "External agent") {
                    model.chooseTarget($0.id)
                }.disabled(model.busy)
                Button("Refresh Agents", action: model.refreshTargets).disabled(model.busy)
                Spacer()
                Menu("Conversations") {
                    ForEach(model.conversations) { conversation in
                        Button(conversation.title) { model.chooseConversation(conversation.id) }
                    }
                    Divider()
                    Button("New Conversation", action: model.newConversation)
                    Button("Remove Current Conversation", role: .destructive, action: model.removeConversation)
                        .disabled(model.conversation == nil)
                }.disabled(model.busy)
            }.padding(.horizontal, 14).padding(.bottom, 10).padding(.top, 8).background(LauncherPalette.chrome)
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 20) {
                        if model.entries.isEmpty {
                            Text("What should your agent work on?").commandlyFont(size: 21, weight: .semibold).padding(.top, 14)
                            Text("Messages go to your configured \(model.kind.title) server. Its agent may use tools, memory and connected services according to its own configuration.")
                                .commandlyFont(size: 12).foregroundStyle(.secondary)
                        }
                        ForEach(model.entries) { entry in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Label(entry.isUser ? "You" : model.kind.title, systemImage: entry.isUser ? "person.crop.circle" : "sparkle")
                                        .commandlyFont(size: 10, weight: .semibold)
                                    if entry.state == .streaming { ProgressView().controlSize(.mini) }
                                    if entry.state == .failed || entry.state == .stopped {
                                        Text("Incomplete").commandlyFont(size: 10).foregroundStyle(.secondary)
                                    }
                                }.foregroundStyle(entry.isUser ? Color.secondary : BrandPalette.accentSoft)
                                Text(entry.text.isEmpty ? "Waiting for your agent…" : entry.text)
                                    .commandlyFont(size: 13).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                                .padding(entry.isUser ? 12 : 0)
                                .background(entry.isUser ? Color.primary.opacity(0.04) : .clear, in: RoundedRectangle(cornerRadius: 10))
                        }
                        status
                        if model.conversation?.requiresNewConversation == true {
                            Text("The server may have performed actions before the connection ended. Review the agent's own interface; this incomplete turn will not be resent.")
                                .commandlyFont(size: 11).foregroundStyle(.secondary)
                            Button("Start New Conversation", action: model.newConversation).disabled(model.busy)
                        }
                        Color.clear.frame(height: 1).id("agent-bottom")
                    }.padding(20)
                }.onChange(of: model.entries.last?.text) { _, _ in proxy.scrollTo("agent-bottom", anchor: .bottom) }
            }.background(LauncherPalette.detail)
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                Text("Send to \(model.kind.title) · Server tools may run · Conversations remain here until you close this window")
                    .commandlyFont(size: 10).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                HStack(alignment: .bottom) {
                    TextField("Message your agent…", text: $model.draft, axis: .vertical).textFieldStyle(.plain)
                        .lineLimit(1...5).focused($focused).onSubmit(model.send).disabled(model.busy)
                        .onKeyPress(.escape) { model.handleEscape() ? .handled : .ignored }
                        .accessibilityLabel("Message to external agent")
                    Button(model.responding ? "Stop" : "Send") {
                        if model.responding { model.cancel() } else { model.send() }
                    }.buttonStyle(.borderedProminent).disabled(!model.responding && !model.canSend)
                }.padding(10).background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 9))
            }.padding(14).background(LauncherPalette.chrome)
        }
    }
    @ViewBuilder private var status: some View {
        if let error = model.errorMessage {
            Label(error, systemImage: "exclamationmark.circle").commandlyFont(size: 11).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
        } else if let message = model.statusMessage {
            Text(message).commandlyFont(size: 11).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}
