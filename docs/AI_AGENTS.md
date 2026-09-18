# Custom AI agents

AI Agents is a local library of user-authored text assistants. Each agent has a name,
instructions, provider/model selection, optional personal profile, selected instruction
skills, and enabled memories. Its stable UUID becomes an individually searchable launcher
tool. Settings → Applications uses the existing tool shortcut, alias, tag, and enablement
preferences. Renaming preserves its tool identity; deletion removes discovery/shortcut
registration and its memories.

## Use

1. Configure a text provider in Settings → AI, then open AI Agents.
2. Choose New Agent, write instructions, select a configured model, and Save Agent.
   Refresh Models explicitly asks that provider for available text models. A saved
   non-default model must be rediscovered after reopening the agent; an unavailable model
   requires an explicit replacement and never silently falls back to a different provider.
3. Search the agent's name or assign its tool a shortcut in Settings → Applications.
4. My Profile is an editable local text document, included only when Use My Profile is
   enabled for that agent. Save an empty profile to remove it.
5. Memory accepts manual text or a reviewed excerpt via Remember beneath a completed chat
   entry. Remember fills a draft; Save Memory is the separate persistence action. Each
   memory records its source (manual, user message, agent reply), creation date, owning agent,
   and enabled state. Edit, disable, and delete are explicit operations.
6. Skills are reusable instructions. Author one or import a `commandly-agent-skill` version 1
   JSON file, review and save it, then enable it per agent. Export shares only the skill's
   name/instructions, never profiles, memories, provider configuration, or credentials.

## Boundaries

- Requests reuse `QuickAIServicing` and its existing provider/model/credential revision
  validation, explicit discovery, streaming limits, cancellation, and typed adapters.
- These agents have text generation only. No tools, shell, filesystem/browser access,
  connector authority, background autonomy, or activity monitoring is provided. Finder AI's
  bounded tools and the separate Hermes/OpenClaw applications remain separate runtimes.
- Opening the library reads local saved metadata only. Refresh Models and Send are the only
  provider operations. The context disclosure identifies the categories that Send includes.
- Chat transcripts stay in the current session and are cleared when the launcher session
  stops. No transcript or activity is automatically turned into memory.
- Any saved-library change invalidates open agent context; the UI requires a new chat before
  using changed instructions/profile/memory. Already transmitted context cannot be withdrawn
  from a provider. A context revision check also terminates later streamed output from stale
  context. No future request should use that obsolete chat.
- Agent requests cannot select an arbitrary endpoint or create credentials. Saved model
  identity is non-secret; discovered choices retain Quick AI's session pin.
- Library persistence is in Application Support/Commandly/AI Agents/library-v1.json within
  the app container. A dedicated utility serial executor performs bounded regular-file I/O,
  private temporary-file writes, and atomic replacement; imported symlinks/nonregular files
  are rejected. Maximum library size is 5 MiB, with 64 agents, 64 skills, and 512 memories.
  Data is local plaintext, not an encrypted vault; credentials remain in existing Keychain
  infrastructure and are never copied into this document.
- Context is bounded to 256 KiB. Individual instructions, profile, skill, memory, and name
  limits reject oversize saves. Errors use fixed messages and never log saved text or paths.
- SwiftUI controls use descriptive labels, keyboard-operable native controls, explicit Save
  actions, and the existing launcher Back/action contract. No new macOS permission is needed.

## Implementation ownership

`AIKit/AIAgentLibrary.swift` owns validated portable values and context assembly.
`Services/AI/Agents` owns local persistence and the scoped Quick AI adapter. `AIAgentsViewModel`
owns editing and request lifecycle, while `AIAgentsView` renders it. `AIAgentsApplication`
owns searchable tools. The generic registry `refreshTools(for:)` transactionally reloads
any registered application's tool/command catalog and preserves preferences; AppRuntime
refreshes existing discovery and hotkey registration after the library publishes a change.

Parity scope: custom text profiles, individual hotkeys, explicit profile, reviewed persistent
memory, and author/import/export instruction skills. Automatic activity memory, autonomous
execution, and agent tools are not claimed.
