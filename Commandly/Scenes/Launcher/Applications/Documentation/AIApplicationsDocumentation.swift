import Foundation

extension RegisteredApplicationDocumentation {
    static let finderAI = LauncherApplicationDocumentation(
        category: .coreFeatures,
        overview: "Ask a configured AI model about files in user-authorized folders, let it use bounded Finder tools, and review exact one-time plans before Commandly reads file contents or changes anything.",
        sections: [
            DocumentationSection(
                id: "finder-ai.setup",
                title: "Connect a Provider",
                blocks: [
                    .steps("finder-ai.setup.steps", [
                        "Open Settings → AI and choose a supported provider.",
                        "Enter the provider API key, or use a loopback Ollama endpoint.",
                        "Validate the connection, choose an available tool-capable model, and save it.",
                        "In Settings → Permissions, choose the folders Finder AI may access."
                    ]),
                    .callout(
                        "finder-ai.setup.keychain",
                        DocumentationCallout(
                            kind: .privacy,
                            title: "Bring your own key",
                            text: "Cloud API keys are stored in macOS Keychain. Provider and model identifiers are stored separately as non-secret preferences. Commandly does not proxy provider traffic."
                        )
                    )
                ]
            ),
            DocumentationSection(
                id: "finder-ai.tools",
                title: "Ask and Use Finder Tools",
                blocks: [
                    .bullets("finder-ai.tools.items", [
                        "Finder AI can list authorized roots, search the existing local index, list one directory level, inspect metadata, and reveal items in Finder.",
                        "It can propose creating folders, renaming, duplicating, copying, moving, or moving items to Trash.",
                        "The model receives random session handles and root-relative display locations, never raw absolute paths as tool arguments.",
                        "A bounded agent loop stops after eight provider rounds or 24 tool calls."
                    ]),
                    .callout(
                        "finder-ai.tools.scope",
                        DocumentationCallout(
                            kind: .permission,
                            title: "Authorized folders only",
                            text: "Every handle is resolved again inside the folders selected in Permissions. Symlinks and packages are treated as leaves, and the extension cannot run shell commands, AppleScript, or permanent deletion."
                        )
                    )
                ]
            ),
            DocumentationSection(
                id: "finder-ai.approvals",
                title: "Review Before Sharing or Changing",
                blocks: [
                    .bullets("finder-ai.approvals.items", [
                        "Search, folder listing, metadata, and reveal are bounded read-only tools.",
                        "Reading file contents pauses on a list of the exact files and maximum byte count before any content is sent to a cloud provider.",
                        "Every file mutation pauses on an immutable preview with destinations, resulting names, risk, and warnings.",
                        "Approval applies once, expires after two minutes, and is invalid if the item changes before execution.",
                        "Trash is the only destructive primitive; there is no permanent-delete fallback."
                    ]),
                    .callout(
                        "finder-ai.approvals.cloud",
                        DocumentationCallout(
                            kind: .privacy,
                            title: "Provider disclosure",
                            text: "Your prompt and bounded metadata tool results are sent to the active provider. File contents are sent only after the separate content approval. Conversations remain in memory for the active Finder AI session and are not logged or persisted by Commandly."
                        )
                    )
                ]
            ),
            DocumentationSection(
                id: "finder-ai.limits",
                title: "Current Limitations",
                blocks: [
                    .bullets("finder-ai.limits.items", [
                        "The first release uses non-streaming provider responses.",
                        "The reviewed runtime supports OpenAI, Anthropic, Gemini, Mistral, Groq, xAI, OpenRouter, and loopback Ollama.",
                        "Search coverage depends on Commandly's current local file index and the folders you selected.",
                        "File actions are not an atomic transaction; a multi-item operation can partially complete and reports each result."
                    ])
                ]
            )
        ],
        keywords: [
            "AI", "BYOK", "Keychain", "Finder", "tools", "approval", "model", "OpenAI",
            "Anthropic", "Gemini", "Mistral", "Groq", "xAI", "OpenRouter", "Ollama", "Trash"
        ]
    )
}
