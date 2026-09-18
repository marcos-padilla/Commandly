import Foundation

extension RegisteredApplicationDocumentation {
    static let externalAgents = LauncherApplicationDocumentation(category: .productivity,
        overview: "Connect your own Hermes or OpenClaw API server and chat with its configured agents.", sections: [
            DocumentationSection(id: "external.connect", title: "Connect an agent server", blocks: [
                .paragraph("external.connect.1", "Enable the server's documented Chat Completions API first. Enter its API base URL ending in /v1 and its bearer token or password. Check & Connect requests the available agent list, then saves the verified connection in Keychain. HTTP is accepted only for loopback; remote connections require HTTPS."),
                .paragraph("external.connect.2", "Select an agent from the server's list. Refresh Agents explicitly reloads that list. Hermes supports a profile prefix in its base URL; OpenClaw returns agent targets such as openclaw/default. Connections are separate from ordinary AI-provider settings.")]),
            DocumentationSection(id: "external.chat", title: "Conversations and tools", blocks: [
                .paragraph("external.chat.1", "Send starts an agent run on your server and streams its text into Commandly. Server tools can run under the agent's own permissions. Commandly advertises no local tools and never approves an external approval request. Use the server's own interface for approvals and tool details."),
                .paragraph("external.chat.2", "Use Conversations to switch between up to eight conversations in the current window. Changing agents starts a separate conversation. Closing the window clears local transcripts. Removing a conversation or connection does not delete remote history."),
                .paragraph("external.chat.3", "Stop cancels the HTTP request. It cannot undo completed remote actions. Interrupted turns are labeled incomplete and are never automatically retried; review server outcomes before starting a new conversation.")])
        ])
}
