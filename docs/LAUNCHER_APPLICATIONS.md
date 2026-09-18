# Launcher Applications

Commandly treats each built-in capability as a launcher application. Clipboard History, File Search,
local productivity tools, system utilities, and action-only entries such as Open Settings all use the
same registration boundary without forcing their internal screens or domain behavior into a common
feature model. Applications may expose stable child tools for focused entry points while retaining
their own internal, state-dependent actions.

## Current built-ins

`LauncherApplicationRegistry.makeBuiltIn()` currently assembles these application surfaces:

- **Clipboard History** — browse, search, copy, create, edit, append, delete, and clear captured
  pasteboard entries. Text editing writes the result back to the pasteboard without logging content.
  Custom names, pins, and collections organize entries without changing their payloads; see
  [Clipboard History](CLIPBOARD_HISTORY.md).
- **File Search** — search authorized folders, preview files, and run native open, sharing, Finder,
  clipboard, duplicate, copy, move, trash, and shortcut actions.
- **File Browser** — navigate authorized folders inside Commandly, filter their immediate children,
  move to the parent folder, and explicitly open a file. Directory reads are bounded and links/aliases
  stay closed; choose the destination folder directly to browse it.
- **Recent Downloads** — list the newest top-level files in Downloads and explicitly open, reveal,
  or copy the selected file through a read-only sandbox entitlement.
- **Logos** — browse the public SVGL catalog with local search and category filtering, keep local
  favorites, copy SVG source or asset URLs, and explicitly download a selected light or dark SVG.
  Catalog responses are cached for ten minutes so typing never sends search queries to SVGL.
- **Background Remover** — choose or drop one image, separate its foreground with Apple Vision on
  device, compare the original and transparent previews, and explicitly export a PNG. Source bytes,
  masks, and results remain in memory for the active launcher session and are never uploaded.
- **Image Tools** — convert a picked or dropped still image to PNG, JPEG, HEIC, or TIFF where supported
  by macOS, optionally resize and rotate, review a preview, and save a separate result. Extract Text
  and Decode QR run local Vision, with editable text and explicit QR destination review. See
  [Image Tools](IMAGE_TOOLS.md).
- **My Schedule** — read upcoming Calendar events after explicit access, filter by date/calendar,
  review and join meeting links, and optionally arm automatic joining for one exact occurrence.
  Calendar data and armed occurrences are never persisted or uploaded. See [Schedule](SCHEDULE.md).
- **Camera Preview** — explicitly start a video-only camera preview, choose mirroring, take a photo,
  then review, copy, or save a PNG. Capture stops before photo review and when leaving. See
  [Camera](CAMERA.md).
- **Confetti** — play a brief original celebration inside the launcher, replay with Return, and
  dismiss with Escape. Reduce Motion uses a still arrangement. See [Confetti](CELEBRATION.md).
- **Screenshot** — choose a region, window, or display, then review a local PNG before copying or
  saving. Window and display selection use the macOS picker. See [Screenshot](SCREENSHOT.md).
- **Screen Recording** — open independent recording controls, explicitly choose a window/display
  and optional system audio, then stop into playable review and save MP4/MOV. Opening a tool never
  begins capture. See [Screen Recording](SCREEN_RECORDING.md).
- **Quick AI** — stream text replies through configured BYOK providers, follow up with conversation
  context, stop or retry a response, and explicitly change the configured provider/model pair.
  Conversations remain in memory. See [Quick AI](QUICK_AI.md).
- **Spelling & Grammar** — explicitly check entered text, review native suggestions, edit and copy
  the result. Its companion macOS Service corrects selected text in supporting editors after an
  explicit Services invocation. See [Writing tools](WRITING_TOOLS.md).
- **Translate** — detect or choose the source language, select a target from the native catalog,
  and explicitly translate text or a word. Apple's language-download flow runs only after an explicit
  request. See [Native Translation](TRANSLATION.md).
- **Menu Bar Shortcuts** — search and pin up to eight registered tools as independent native
  menu-bar icons. Open or remove each through its native menu. See [Menu Bar Shortcuts](MENU_BAR_SHORTCUTS.md).
- **Display Resolution** — inspect exact native modes, preview a supported mode with a 15-second
  automatic revert, and explicitly keep it for the login session. See [Display Resolution](DISPLAY_RESOLUTION.md).
- **Calculation History** — browse, filter, copy, delete, and clear successful results recorded during
  the current calculator session.
- **Timers & Focus** — run multiple named timers, including 25-minute focus and 5-minute break
  presets, with pause, resume, reset, delete, and an optional local completion sound.
- **Finance** — track subscriptions in a private local ledger; review monthly and yearly recurring
  spend, active plans, seven-day alerts, category totals, a renewal calendar, and category budgets.
- **Shelf** — one temporary floating board opened from the launcher, menu bar, or its two
  tool-owned default global shortcuts on the display/Space active at request time. It supports file/folder drag-in,
  multi-item drag-out, clipboard file/folder URLs plus privately materialized text/images, native
  previews and file actions, whole-surface movement that yields to item drags, direct
  AirDrop/Messages/Mail drop targets, persistent cross-Space visibility, and schema-driven
  empty-close, placement, and sound settings. Boards are not persisted or restored, and owned
  clipboard files are deleted on cleanup.
- **Productivity Library** — persistent local snippets, quick notes, Quicklinks, and emoji keywords.
  Quick Notes can open in independent floating windows with explicit Save, native editing, and
  safe close/quit decisions. Concurrent item saves preserve other editors' work; conflicts retain
  the draft and offer a separate copy. See [Floating Quick Notes](FLOATING_NOTES.md).
  Tags support search and filtering. Snippets expand clipboard/date/time/UUID and named inputs on
  explicit copy; Quicklinks validate web, file, folder, and application deep-link targets before
  opening. Native sharing is available for saved items.
- **System Activity** — inspect aggregate CPU, memory, storage, uptime, and thermal state; switch to,
  quit, force quit, or safely quit multiple regular GUI applications.
- **Port Manager** — inspect local TCP and UDP listeners visible to the current user, filter by
  port/process/protocol, and explicitly request graceful termination of the process that owns a
  revalidated selected listener. Listener metadata remains local and is never persisted or logged.
- **Storage Cleaner** — review bounded identifier-based app leftovers and third-party user caches,
  or explicitly choose one ephemeral folder for exact SHA-256 duplicate discovery. Recommendations
  stay editable, one duplicate copy always remains, and only a confirmed batch moves to Trash.
- **Microphone Control** — show whether the default input device is muted and change its public Core
  Audio mute state across apps that use that device. It captures no audio and reports devices that
  do not expose a writable mute property.
- **Highlight Mode** — draw click rings, ephemeral typing and shortcut feedback, and a cursor
  spotlight above presentations or recordings. Its assigned application hotkey toggles the mode
  without opening Commandly; Accessibility is requested only when the user turns it on.
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

## Current application tools and commands

Every non-command application receives one searchable Open tool by default. An application replaces
that default when it declares a more specific stable tool catalog. The current specialized catalogs
are:

- **Shelf** — New Shelf and New Shelf from Clipboard. Each tool owns its existing default shortcut,
  which the user can replace or clear in Settings.
- **Color Tools** — Open Color Tools and Pick Screen Color; the picker samples one screen pixel and
  copies its Hex value without presenting a Color Tools session.
- **Recent Downloads** — Open Recent Downloads, Open Newest Download, and Copy Newest Download.
  Each tool can receive its own shortcut. The two Newest tools first load the same bounded,
  top-level Downloads list used by the application; Open uses the existing local URL-opening path,
  while Copy writes the newest file URL through the existing local pasteboard path.
- **Finance** — Open Finance and New Subscription. New Subscription opens Finance directly in its
  blank subscription editor; the user must still complete and save the form.
- **Background Remover** — Open Background Remover and Choose Image. Choose Image presents the
  normal single-image picker; processing begins only after the user chooses a file, and saving the
  transparent PNG remains explicit.
- **Timers & Focus** — Open Timers and New Timer. New Timer opens a blank countdown draft; the user
  must still enter valid details and start it.
- **Markdown Preview** — Open Markdown Preview and Choose Markdown File. Choose Markdown File
  presents the normal supported-document picker rather than selecting or reading a file
  automatically.
- **Productivity Library** — Open Productivity Library, New Snippet, New Quick Note, New Floating Note, New Quicklink,
  and New Emoji Keyword. Each New tool opens the matching blank editor; validation and Save remain
  part of the workflow.
- **Storage Cleaner** — Review App Leftovers and Caches and Find Exact Duplicates. The first opens
  the bounded Library review, while the second presents the one-folder picker before scanning.
  Both retain editable selection, cleanup review, and the final Move to Trash confirmation.
- **Port Manager** — Inspect Ports and Kill Port. The typed forms `kill port <number>` and
  `stop port <number>` resolve to the Kill Port tool with an integer argument.
- **Microphone Control** — Open Microphone Control and Toggle Microphone.
- **Highlight Mode** — Configure Highlight Mode and Toggle Highlight Mode.

These are declared entry points, not an automatic export of every application action. A dynamic
action that depends on the active session's selection remains inside that session until the owning
application intentionally promotes it to a stable tool.

Typing `kill port 3000`, for example, does not immediately terminate a process. It opens Port
Manager filtered to port 3000. One matching listener opens the existing confirmation, multiple
matches require a choice, and the service revalidates the selected listener immediately before a
confirmed graceful termination request.

## Root inline local results

The root query runs the normal registered-command, installed-application, placeholder, and
calculator providers together with three app-target sources:

- Exact application-owned typed-command matches appear in **Commands**.
- Up to six Clipboard History entries appear in **Clipboard History**, ranked from data stored or
  enriched at capture time. Return copies the exact stored entry.
- Up to ten File Search items appear in **Files** after an 80 ms cancellable debounce. Return opens
  the indexed URL; opening the full File Search application remains the route to previews, filters,
  and file actions.

The launcher rejects stale work after a query change. Missing File Search access produces a
non-private recovery row that opens Permissions, while an unavailable index offers the full File
Search application. Neither case broadens scope or scans outside the existing index. Clipboard and
file rows intentionally do not contribute autocomplete text because their titles may contain
private user content.

## Foundation not registered in production

- **Window Switcher** — contracts, in-memory adapters, an original presentation model, settings
  schema, prototype app-target adapters, and deterministic tests exist, but the application and its
  app-lifetime input/Dock coordinator must remain unregistered and disabled in sandboxed production
  Commandly. Apple's
  [App Sandbox guidance](https://developer.apple.com/documentation/security/protecting-user-data-with-app-sandbox)
  lists the cross-application assistive Accessibility and termination behaviors it needs as
  incompatible. Option-Tab suppression, Command-Tab replacement,
  Dock Accessibility traversal, window enumeration/control, and Screen Recording thumbnails are not
  currently usable product workflows. A privileged companion or a non-sandboxed direct-distribution
  build requires a separate accepted ADR. See [Window Switcher](WINDOW_SWITCHER.md).

These names and workflows are Commandly's own. The registry does not load or imitate another
launcher's source code, assets, branding, or exact interface.

## Architecture

The application path has five layers:

1. `LauncherApplicationDefinition` declares identity, type, hierarchy, defaults, built-in tags,
   optional non-secret configuration, and typed user documentation for application entries. Tool
   definitions reuse this type without requiring their own application article.
2. `LauncherApplication` attaches launch behavior to an application definition and declares its
   stable tools and optional typed-command parsers.
3. `LauncherApplicationRegistry` is the single source of truth for hierarchy, resolved settings,
   discovery, effective enablement, application/tool ownership, and typed-command matching.
4. A view application constructs its own strongly typed model and wraps it once in a
   `LauncherApplicationSession`.
5. `LauncherRootView` hosts the active session dynamically. It never switches on a concrete
   application identifier.

Type erasure is limited to `LauncherApplicationSession`, where dynamic registration requires it.
Feature models and SwiftUI views remain concrete and testable. The session contract intentionally
contains only shell concerns: status, footer/menu actions, selection movement, action dispatch, and
lifecycle cleanup.

Applications that must act without covering the current presentation may opt into
`LauncherApplicationBackgroundInvoking`. The shared command executor still resolves availability,
executes once, and records privacy-safe outcome metadata; only the feature action bypasses launcher
presentation for the application-hotkey invocation source.

An application may separately opt its safe focused tools into
`LauncherApplicationToolBackgroundInvoking`. Only the declared tool IDs use that path; every other
tool presents its owning application. Both forms receive the owning application's resolved settings,
and tool invocation also receives the complete typed arguments.

## Adding an application

1. Add the feature model, services, and views under the owning launcher feature folder.
2. Conform the model to `LauncherApplicationModel`. Keep domain behavior in services/models and keep
   the conformance limited to shell coordination.
3. Add a small `LauncherApplication` type under `Commandly/Scenes/Launcher/Applications`. Declare its
   typed `definition`, including its parent, maintained discovery tags, configuration fields, and a
   focused `LauncherApplicationDocumentation` contribution. Registry validation requires that
   application documentation. Its `launch(in:)` reads resolved configuration from the context,
   creates the model with initializer-injected dependencies, and returns a session.
4. Accept the default Open tool or declare a focused `toolDefinitions` list. A tool ID must be unique,
   have the application ID as its parent, and use a typed action manifest. Implement
   `launch(toolID:arguments:in:)` for custom entry behavior.
5. If a phrase needs structured arguments, add an exact `commandDefinitions` parser that returns a
   `CommandReference` to one of those owned tools. Do not give the parser separate availability,
   execution, or shortcut behavior.
6. Register the application in `LauncherApplicationRegistry.makeBuiltIn()`.
7. Add registry/session, tag discovery, tool ownership/argument, and focused model tests. Resolve and
   execute application and tool manifests through `SharedCommandExecutionCoordinator`; include
   search/shortcut/Command Wheel parity coverage for assignable tools. Test typed-command matching
   and rejection separately. No `LauncherRootView`, Command Wheel executor, documentation-screen,
   or route switch change should be necessary. The live documentation catalog includes the new
   application automatically.

See `docs/DOCUMENTATION.md` for the structured content contract, validation rules, and article
maintenance checklist.

Dependencies shared by one application are grouped in a focused service value such as
`FileSearchApplicationServices` and injected when the application is registered. The launch context
contains only shell navigation, so adding a feature does not grow a cross-application service
locator. Add a focused group rather than expanding unrelated initializers or reaching into global
state.

## Definitions and hierarchy

Every registered node has one of these roles: Group, AI Extension, Extension, Command, Application,
or Tool. A group is definition-only. A tool is always a launchable child of the application that
implements it; it is not a second `LauncherApplication` instance. `parentID` creates an
arbitrary-depth tree, with application tools currently occupying the third level beneath their
group. Parents must be registered before children, identifiers and field variables must be unique,
selection defaults must reference declared options, and a launchable application must contribute
valid non-empty documentation. Definition-only groups and application-owned tools may omit it.

The generic Applications settings page derives its entire hierarchy and inspector from these
definitions. Groups begin expanded; applications with tools have a disclosure control and begin
collapsed. The selected definition's inspector owns enablement, discovery tags, its optional global
shortcut, typed-command syntax on application rows, and schema-defined configuration. Adding an
application or tool must not require another settings-page branch.

Supported non-secret configuration field kinds are text, toggle, integer, decimal, and selection.
Each field declares a stable variable, title, optional description and placeholder, default value,
and selection options when applicable. Resolved values are supplied through
`LauncherApplicationContext.settings`; application behavior must consume any field it declares.

Built-in tags derive from reviewed definition/manifest metadata, appear as locked capsules in
Settings, and cannot be erased by user preferences. Users may add up to 32 normalized tags of at
most 64 characters to an application or tool; comparisons are case- and diacritic-insensitive for
deduplication. Existing aliases remain resolved search metadata for compatibility and appear as the
initial custom tag when no tag override exists.

Installed macOS applications use their result Actions menu to set or edit one optional search
nickname. They retain their original title and bundle identity. This is separate from the registered
application/tool discovery tags above; see [Installed application aliases](APPLICATION_ALIASES.md)
for validation, persistence, ranking, and keyboard behavior.

Per-application/tool custom tags, global hotkeys, enablement overrides, and configuration values
persist in `LauncherApplicationPreferencesStoring`. Disabling a group effectively disables all
descendants; disabling an application disables its tools. Disabled descendants are excluded from
discovery and global shortcut registration. Carbon global shortcuts do not request Accessibility
access; reserved and duplicate shortcuts remain unregistered and surface an issue in Settings.
Typed commands do not persist or register a shortcut of their own.

Only non-secret values belong in this schema or UserDefaults store. AI credentials deliberately do
not add a credential field: they use the dedicated AI settings flow and Keychain-backed
`SecureStoring`, while only provider/model selection metadata is persisted as a non-secret
preference.

## Shared command execution and Command Wheel

`LauncherApplicationRegistry` continues to own feature definitions and implementations. The
composition root atomically synchronizes effectively enabled application and tool manifests into the
existing CommandKit `CommandRegistry`; it does not create a wheel registry. Launcher search,
registered application/tool hotkeys, parsed commands, and Command Wheel submit a typed
`CommandReference` plus a distinct invocation source to `SharedCommandExecutionCoordinator`. That
actor resolves availability and arguments, invokes the shared executor once, and records only a
bounded privacy-safe result summary. The full reference reaches application presentation so a parsed
or saved tool argument is not discarded at the session boundary.

A saved wheel assignment remains a reference even when its definition is disabled, removed, or no
longer accepts its stored argument shape. Settings and presentation mark it unavailable rather than
silently deleting or replacing it. Adding a normal registered application or tool should require no
wheel execution branch; expose reusable metadata in its manifest and keep behavior in the existing
`LauncherApplication` implementation. A typed-command parser is intentionally absent from the wheel
because the parser is query syntax, while its target tool is already assignable. Installed macOS apps
are the deliberate exception to the surface model: both search and wheel use the shared parameterized
`applications.open-installed` manifest with a typed bundle-identifier argument and the existing
`ApplicationOpening` adapter.

See [Command Wheel Architecture](COMMAND_WHEEL_ARCHITECTURE.md),
[Extending Command Wheel](COMMAND_WHEEL_EXTENDING.md), ADR-0007, and ADR-0010.

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

Markdown Preview is an example of a custom document surface. The registered application owns the
picker/drop, file-watch, search, outline, source, export, and WebKit lifecycle, while the reusable
`MarkdownPreviewKit` package owns only dependency-free configuration and safe rendering. The Finder
Quick Look target imports that package directly; it does not launch or import the Commandly app
target. App settings are mirrored to the extension as non-secret App Group configuration.

## Boundaries

Command-surface Actions and Command-K share the active model's `showsActionsMenu` state. The
launcher shell renders a searchable keyboard panel by default; applications with their own richer
panels declare `presentsOwnActionsMenu` (File Search and Markdown Preview). An action is revalidated
against the current enabled menu before dispatch, and the menu closes before the action can open a
new editor or confirmation. The panel restores its prior attached input field before dispatch or
on dismissal. Native footer menus remain for the root application menu, not command-surface actions.

- A registered Commandly application is not an installed macOS application. Installed apps remain
  search results opened through `ApplicationOpening`.
- `CommandManifest` remains the discovery contract from CommandKit; app-target presentation stays in
  the launcher application layer.
- A tool must have one registered owning application. Typed commands may target only tools declared
  by that same application.
- Typed commands must return typed arguments and reuse the target tool's validation, permission,
  confirmation, and execution path. They must never interpolate launcher text into a shell.
- Command Wheel stores `CommandReference` values and presentation configuration only; it must not
  switch on application IDs, create sessions directly, or call native feature services.
- Registration must reject duplicate identifiers.
- Closing or leaving an application session must call its lifecycle cleanup.
- Applications must not log queries, clipboard contents, file paths, previews, or indexed contents.
- Inline Clipboard History and File Search rows must not feed autocomplete or command history.
  Clipboard matching uses capture-time values only; file matching uses the existing authorized
  index and must not trigger a filesystem scan for each keystroke.
- Markdown Preview must additionally escape document HTML, block implicit web loads, bound source
  and local images, and keep file/query/scroll history out of the shared Quick Look preferences.
- Window Switcher must remain outside the production registry while Commandly is sandboxed. Its
  prototype must keep titles, thumbnails, application/window ordering, pointer locations, and input
  state in memory only. Any future authorized runtime must still treat Current-Space and Dock/
  Command-Tab integration as best effort and keep private Dock, Spaces, media, and blur APIs outside
  the registry contract.
- AI applications must additionally avoid logging credentials, prompts, provider bodies, tool
  arguments/results, file metadata, and disclosed content. Cloud disclosure must identify the
  active provider and remain within the approved bounded payload.
- New permission behavior still requires the documented contextual permission flow.
