import Foundation

extension RegisteredApplicationDocumentation {
    static let quickAI = LauncherApplicationDocumentation(category: .productivity,
        overview: "Ask questions, refine ideas, and draft text with your own configured provider. Responses arrive incrementally, and follow-up messages retain completed conversation context within this launcher session.",
        sections: [
            DocumentationSection(id: "quick-ai.start", title: "Start a Conversation", blocks: [
                .steps("quick-ai.start.steps", [
                    "Open Quick AI or Open AI Chat. If no provider is configured, use Open AI Settings to validate a connection and save a model.",
                    "Choose a configured provider in the header. Opening chat and Reload Saved Connections read only saved metadata. Refresh Models explicitly contacts the selected provider with its saved key to discover compatible text models.",
                    "Write a message and press Return. Your message and completed conversation context go to the displayed provider. Shift-Return adds a line.",
                    "Follow up with another message. Stop Reply or Escape cancels receiving; partial failed or stopped replies are kept visibly labeled but are not included in later context."
                ]),
                .paragraph("quick-ai.start.models", "The searchable picker initially shows each provider's saved model. Refresh Models adds compatible choices returned by its supported adapter; catalogs stay in this session. Choosing another model or provider starts a new conversation after confirmation and leaves AI Settings unchanged. Failed or canceled refreshes preserve your draft and conversation.")
            ]),
            DocumentationSection(id: "quick-ai.recovery", title: "Control and Recovery", blocks: [
                .paragraph("quick-ai.recovery.retry", "Retry Last Message repeats only the last failed or stopped message. New Chat clears session content. Connection or credential changes invalidate an in-flight reply and require a new chat; responses from a prior account cannot enter its follow-up context."),
                .paragraph("quick-ai.recovery.stream", "Streaming uses the provider's incremental protocol. Missing terminal frames, unexpected tool calls, malformed output, or service failures leave the reply incomplete. Provider response limits and refusals are labeled. Stopping cancels the local request, but provider-side processing and billing depend on that provider.")
            ]),
            DocumentationSection(id: "quick-ai.privacy", title: "Privacy and Limits", blocks: [
                .callout("quick-ai.privacy.local", DocumentationCallout(kind: .privacy, title: "Your own provider", text: "Chat accesses no files, clipboard, screen, calendar, or tools. Only typed messages and completed text context are sent after you choose Send. Keys stay behind the existing Keychain boundary. Conversation content is held in memory and cleared when the session ends.")),
                .callout("quick-ai.privacy.bounds", DocumentationCallout(kind: .limitation, title: "Text conversations", text: "This application provides text chat with streaming and follow-ups. It does not browse the web, run agents, upload documents/images, search or persist conversations, sync across devices, or provide voice interaction. Messages, context, and responses are bounded."))
            ])
        ], keywords: ["AI", "chat", "streaming", "follow up", "BYOK", "provider"])
}
