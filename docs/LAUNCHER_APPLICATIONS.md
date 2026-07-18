# Launcher Applications

Commandly treats each built-in capability as a launcher application. Clipboard History, File Search,
local productivity tools, system utilities, and action-only entries such as Open Settings all use the
same registration boundary without forcing their internal screens or domain behavior into a common
feature model.

## Current built-ins

`LauncherApplicationRegistry.makeBuiltIn()` currently assembles these application surfaces:

- **Clipboard History** — browse, search, copy, create, edit, append, delete, and clear captured
  pasteboard entries. Text editing writes the result back to the pasteboard without logging content.
- **File Search** — search authorized folders, preview files, and run native open, sharing, Finder,
  clipboard, duplicate, copy, move, trash, and shortcut actions.
- **Recent Downloads** — list the newest top-level files in Downloads and explicitly open, reveal,
  or copy the selected file through a read-only sandbox entitlement.
- **Calculation History** — browse, filter, copy, delete, and clear successful results recorded during
  the current calculator session.
- **Timers & Focus** — run multiple named timers, including 25-minute focus and 5-minute break
  presets, with pause, resume, reset, delete, and an optional local completion sound.
- **Shelf** — one temporary floating board opened from the launcher, menu bar, or two fixed global
  shortcuts on the display/Space active at request time. It supports file/folder drag-in,
  multi-item drag-out, clipboard file/folder URLs plus privately materialized text/images, native
  previews and file actions, whole-surface movement that yields to item drags, direct
  AirDrop/Messages/Mail drop targets, persistent cross-Space visibility, and schema-driven
  empty-close, placement, and sound settings. Boards are not persisted or restored, and owned
  clipboard files are deleted on cleanup.
- **Productivity Library** — persistent local snippets, quick notes, Quicklinks, and emoji keywords.
  Snippets can expand `{{clipboard}}`; Quicklinks validate web, file, folder, and application deep-link
  targets before opening; native sharing is available for saved items.
- **System Activity** — inspect aggregate CPU, memory, storage, uptime, and thermal state; switch to,
  quit, force quit, or safely quit multiple regular GUI applications.
- **Window Layouts** — apply 58 native presets to the active window or save custom normalized layouts.
  Accessibility is requested only when the user applies a layout.
- **Emoji Search**, **Convert Text Case**, **Color Tools**, **Dictionary**, **Search Fonts**, and
  **Typing Practice** — focused, offline utilities backed by macOS frameworks and local data.
- **AI Extensions / Finder AI (vertical slice in progress)** — a built-in native conversation
  surface for questions about authorized files and exact, locally approved Finder operations. It
  uses the provider/model selected in the dedicated AI settings pane, keeps conversation state only
  for the launcher session, and uses conversation-scoped opaque file handles. The reviewed initial
  provider runtime is non-streaming across OpenAI, Anthropic, Gemini, Mistral, Groq, xAI,
  OpenRouter, and loopback Ollama.
- **Open Settings** — action-only navigation into Commandly settings.

These names and workflows are Commandly's own. The registry does not load or imitate another
launcher's source code, assets, branding, or exact interface.

## Architecture

The application path has five layers:

1. `LauncherApplicationDefinition` declares identity, type, hierarchy, defaults, discovery metadata,
   an optional configuration schema, and typed user documentation for launchable entries.
2. `LauncherApplication` attaches launch behavior to a launchable definition.
3. `LauncherApplicationRegistry` is the single source of truth for hierarchy, resolved settings,
   discovery, enablement, and launch lookup.
4. A view application constructs its own strongly typed model and wraps it once in a
   `LauncherApplicationSession`.
5. `LauncherRootView` hosts the active session dynamically. It never switches on a concrete
   application identifier.

Type erasure is limited to `LauncherApplicationSession`, where dynamic registration requires it.
Feature models and SwiftUI views remain concrete and testable. The session contract intentionally
contains only shell concerns: status, footer/menu actions, selection movement, action dispatch, and
lifecycle cleanup.

## Adding an application

1. Add the feature model, services, and views under the owning launcher feature folder.
2. Conform the model to `LauncherApplicationModel`. Keep domain behavior in services/models and keep
   the conformance limited to shell coordination.
3. Add a small `LauncherApplication` type under `Commandly/Scenes/Launcher/Applications`. Declare its
   typed `definition`, including its parent, configuration fields, and a focused
   `LauncherApplicationDocumentation` contribution. The manifest initializer requires
   documentation. Its
   `launch(in:)` reads resolved configuration from the context, creates the model with
   initializer-injected dependencies, and returns a session.
4. Register that application in `LauncherApplicationRegistry.makeBuiltIn()`.
5. Add a registry/session test and focused model tests. Resolve and execute its manifest through
   `SharedCommandExecutionCoordinator`; include search/Command Wheel parity coverage when the
   command can be assigned to a profile. No `LauncherRootView`, Command Wheel executor,
   documentation-screen, or route switch change should be necessary. The live documentation
   catalog includes the new application automatically.

See `docs/DOCUMENTATION.md` for the structured content contract, validation rules, and article
maintenance checklist.

Dependencies shared by one application are grouped in a focused service value such as
`FileSearchApplicationServices` and injected when the application is registered. The launch context
contains only shell navigation, so adding a feature does not grow a cross-application service
locator. Add a focused group rather than expanding unrelated initializers or reaching into global
state.

## Definitions and hierarchy

Every registered node has one of these roles: Group, AI Extension, Extension, Command, or
Application. A group is definition-only; other roles may attach a launch implementation. `parentID`
creates an arbitrary-depth tree. Parents must be registered before children, identifiers and field
variables must be unique, selection defaults must reference declared options, and a launchable
application must contribute valid non-empty documentation. Definition-only groups may omit it.

The generic Applications settings page derives its entire hierarchy and inspector from these
definitions. Aliases and global shortcuts are editable directly in the hierarchy table; the
selected application's inspector is reserved for enablement and schema-defined configuration.
Adding an application must not require another settings-page branch.

Supported non-secret configuration field kinds are text, toggle, integer, decimal, and selection.
Each field declares a stable variable, title, optional description and placeholder, default value,
and selection options when applicable. Resolved values are supplied through
`LauncherApplicationContext.settings`; application behavior must consume any field it declares.

Per-application aliases, global hotkeys, enablement overrides, and configuration values persist in
`LauncherApplicationPreferencesStoring`. Disabling a group effectively disables all descendants.
Disabled descendants are excluded from discovery and global shortcut registration. Aliases are
empty until the user enters them in Settings, then are added to command search keywords. Carbon
global shortcuts do not request Accessibility access;
reserved and duplicate shortcuts remain unregistered and surface an issue in Settings.

Only non-secret values belong in this schema or UserDefaults store. AI credentials deliberately do
not add a credential field: they use the dedicated AI settings flow and Keychain-backed
`SecureStoring`, while only provider/model selection metadata is persisted as a non-secret
preference.

## Shared command execution and Command Wheel

`LauncherApplicationRegistry` continues to own feature definitions and implementations. The
composition root atomically synchronizes effectively enabled manifests into the existing CommandKit
`CommandRegistry`; it does not create a wheel registry. Launcher search, registered-application
hotkeys, and Command Wheel submit a typed `CommandReference` plus a distinct invocation source to
`SharedCommandExecutionCoordinator`. That actor resolves availability and arguments, invokes the
shared executor once, and records only a bounded privacy-safe result summary.

A saved wheel assignment remains a reference even when its definition is disabled, removed, or no
longer accepts its stored argument shape. Settings and presentation mark it unavailable rather than
silently deleting or replacing it. Adding a normal registered application should require no wheel
execution branch; expose reusable metadata in its manifest and keep behavior in the existing
`LauncherApplication` implementation. Installed macOS apps are the deliberate exception to the
surface model: both search and wheel use the shared parameterized `applications.open-installed`
manifest with a typed bundle-identifier argument and the existing `ApplicationOpening` adapter.

See [Command Wheel Architecture](COMMAND_WHEEL_ARCHITECTURE.md),
[Extending Command Wheel](COMMAND_WHEEL_EXTENDING.md), and ADR-0007.

## Built-in AI extensions

`AI Extension` is a launcher-definition role for native, reviewed Commandly applications. It does
not load code through `ExtensionKit`, install provider responses, or create a marketplace/runtime
for external extensions. Finder AI is placed beneath a built-in **AI Extensions** group and follows
the same branch-free session hosting and lifecycle cleanup as other registered applications.

Finder AI supplies its own chat/approval surface rather than forcing the browser-style
`LauncherApplicationScreen`. Its focused service group injects the active provider connection,
bounded agent loop, authorized Finder workspace, and local approval coordinator. Leaving the
application calls session cleanup, which cancels provider/tool work and clears the ephemeral
conversation.

The model receives declarative tools whose arguments contain opaque session handles, not paths or
security-scoped bookmarks. Read-only metadata calls are bounded. File-content disclosure and exact
create, rename, duplicate, copy, move, or Trash plans require local approval. Permanent deletion,
overwrite/merge, arbitrary sharing, AppleScript, process launch, and shell execution are outside the
application contract. See `docs/AI.md` and ADR-0006.

## Reusing screens

Browser-style applications may use `LauncherApplicationScreen`, which supplies the established
Commandly search/filter/sidebar/detail structure. Search is embedded directly into the transparent
top canvas without its own card, outline, or fill; compact native Liquid Glass is reserved for the
Back and filter/sort controls. Its companion components provide shared selection rows, empty states,
and metadata rows. The application supplies feature-specific list, preview, filter, and action
content.

An application with a different layout should provide its own SwiftUI surface. Reuse is opt-in;
the registry does not require every application to look alike.

An application may own internal navigation and multiple feature screens inside its concrete model
and root surface. That internal routing remains private to the application session unless the
launcher shell genuinely needs to coordinate it.

## Boundaries

- A registered Commandly application is not an installed macOS application. Installed apps remain
  search results opened through `ApplicationOpening`.
- `CommandManifest` remains the discovery contract from CommandKit; app-target presentation stays in
  the launcher application layer.
- Command Wheel stores `CommandReference` values and presentation configuration only; it must not
  switch on application IDs, create sessions directly, or call native feature services.
- Registration must reject duplicate identifiers.
- Closing or leaving an application session must call its lifecycle cleanup.
- Applications must not log queries, clipboard contents, file paths, previews, or indexed contents.
- AI applications must additionally avoid logging credentials, prompts, provider bodies, tool
  arguments/results, file metadata, and disclosed content. Cloud disclosure must identify the
  active provider and remain within the approved bounded payload.
- New permission behavior still requires the documented contextual permission flow.
