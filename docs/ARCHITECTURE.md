# Architecture

## Overview

Commandly uses a thin macOS app target and a local Swift package of focused modules. The app target owns lifecycle, composition, and UI. Packages own reusable contracts and domain types.

## Modules

| Module | Responsibility | May depend on |
|--------|----------------|---------------|
| AppCore | Environment, metadata, typed errors, date/UUID/clock | — |
| CommandKit | Command descriptors, typed references/invocations, registry resolution, execution results, and usage-history contracts | AppCore |
| SearchKit | Search query/result/provider contracts | AppCore |
| CalculatorKit | Calculator classify/parse/evaluate engine | AppCore |
| AIKit | Provider/model contracts, normalized conversations and tools, HTTP transport, and reviewed provider adapters | — |
| MarkdownPreviewKit | Safe Markdown rendering, shared preview configuration, outlines, and supported format identifiers | — |
| DesignSystem | Spacing, radius, typography roles, colors, motion | — (SwiftUI/AppKit for tokens) |
| Infrastructure | System integration protocols | AppCore |
| Persistence | Store/repository contracts + in-memory store | AppCore |
| SecurityKit | Secure storage and permission contracts | AppCore |
| ExtensionKit | Experimental extension manifests (no loading) | AppCore |
| Observability | OSLog-based structured logging | AppCore |

## Dependency graph

```text
Commandly App
├── AppCore
├── CommandKit
├── SearchKit
├── CalculatorKit
├── AIKit
├── MarkdownPreviewKit
├── DesignSystem
├── Infrastructure
├── Persistence
├── SecurityKit
├── ExtensionKit
└── Observability
```

Rules:

- AppCore depends on nothing else in Commandly.
- Domain modules do not import the app target.
- No circular dependencies.
- Production modules do not depend on test code.
- Concrete services are assembled only in the composition root.

## Composition root

Slack custom emoji is a registered launcher application backed by injected Infrastructure contracts.
Its retained service owns explicit workspace connections, bounded HTTP requests, and session-only
catalogs; app adapters own Keychain storage and original-image export. See [Slack Emoji](SLACK_EMOJI.md).

`Commandly/Composition` is the only place that wires implementations:

- `AppBootstrapper` creates metadata and default services
- `AppDependencies` holds the dependency graph values
- `AppContainer` owns `AppState`, `AppRouter`, and factory helpers
- `LauncherApplicationRegistry` is the single source of truth for discoverable applications, their
  explicitly declared tools, built-in/user tags, and typed query parsers
- `SharedCommandExecutionCoordinator` resolves and executes search, application/tool-hotkey, and
  Command Wheel invocations through one CommandKit registry and records bounded privacy-safe outcomes
- `AppRuntime` owns the unified Carbon shortcut plan, one cached Command Wheel profile store, and
  the active radial-panel coordinator

Prefer initializer injection. Do not introduce a DI framework.

## App state ownership

- `AppState` is `@MainActor` and `@Observable`.
- Navigation mutations go through `AppRouter`.
- Views receive focused view models; they do not reach into global mutable state.
- First-run onboarding lives under `Commandly/Scenes/Onboarding` and opens when `OnboardingStatusStoring` reports incomplete. Completion persists via a non-secret preference store and routes to `.root`.
- Onboarding permissions use `PermissionServicing` (mocked in tests; `SystemPermissionService` in production) and never block finishing the flow.
- After onboarding, Commandly runs as a **menu bar agent** (`MenuBarExtra` + `LSUIElement` / accessory activation policy): no persistent center-screen window, Dock icon hidden. An ordered-out, one-pixel scene-action host keeps SwiftUI's launcher/Shelf `openWindow` actions registered even when the optional menu-bar item is disabled; owner-scoped registration prevents a stale disappearing bridge from clearing a replacement. Settings open via the standard Settings scene; Documentation opens in its own resizable standard window; Quit is available from the status item menu. Opening either utility window activates the app and orders that window front without using a permanent floating window level.
- The **launcher** is a floating, draggable SwiftUI `Window` (`AppWindowID.launcher`) opened by
  ⌥Space (registered through the unified Carbon `GlobalShortcutMonitor`) or **Open Commandly** in
  the status item menu. Every built-in capability has one typed `LauncherApplicationDefinition`
  registered in `LauncherApplicationRegistry`; launchable definitions attach a
  `LauncherApplication` implementation that creates a strongly typed session. An application may
  also declare stable child definitions with kind `Tool`. Each tool has its own discovery metadata,
  effective enablement, and optional global shortcut while delegating implementation to its owning
  application. Application-owned typed-command parsers resolve exact phrases to a tool's
  `CommandReference` with typed arguments; commands do not become separate shortcut targets.
  Definitions declare built-in tags, and `LauncherApplicationPreferencesStoring` persists bounded
  user tags plus existing non-secret overrides. Legacy aliases remain discovery inputs for
  compatibility. Effective enablement inherits through `Group → Application → Tool`, and the unified
  shortcut plan registers conflict-safe launcher, registered application/tool, and Command
  Wheel shortcuts without an Accessibility prompt. See ADR-0010.
- `LauncherRootView` hosts the active session without feature-specific branches. Root search uses
  SearchKit providers (`CommandSearchProvider`, `ApplicationSearchProvider`, placeholders) merged
  by `CompositeSearchService` with cancellation on query change. It supplements those providers
  with application-owned typed-command matches, at most six capture-time Clipboard History matches,
  and at most ten authorized File Search index matches after a short cancellable debounce.
  Clipboard rows copy their stored entry and file rows open the indexed URL; neither private result
  kind feeds autocomplete. **CalculatorKit** evaluates calculator-shaped queries in parallel and
  pins a Calculator section above other results. Installed macOS apps open through
  `ApplicationOpening` and remain distinct from Commandly's registered launcher applications.
  Root search keeps contextual Actions on the footer's left and one persistent Settings gear menu
  on the right for Documentation, Settings, and Quit; right-clicking an installed application (or
  Actions / ⌘K) opens a searchable application-actions panel (open, Finder, copy, favorites,
  ranking, auto-quit, disable, uninstall review with related files). Active application sessions
  expose footer actions through `CommandActionDescriptor`.
- **Clipboard History** is a fully implemented registered application (`ClipboardHistoryStore` +
  surface UI). Pasteboard monitoring runs headlessly after launch; image/file entries are enriched
  once at capture time via on-device Vision/PDFKit (OCR, labels, readable file text). Root and
  in-application search use that stored enrichment and never re-index while typing. Store updates
  must not activate the app or order the launcher front. Each explicit launcher presentation
  captures the active display before focus changes, applies the shared cross-application overlay role
  and captured geometry, and only then orders and activates the window so it joins the user's
  current desktop or full-screen Space. The same live launcher follows keyboard-only Space changes
  with its query, route, selection, and active application state intact; clicking outside, pressing
  Escape through the current navigation stack, or toggling the hotkey dismisses it.
- **Command Wheel** is a cursor-centered radial presentation over the same CommandKit registry and
  app-level executor used by launcher search and registered application/tool hotkeys. Profiles persist
  stable `CommandReference` values, pages, slot positions, typed reusable arguments, shortcuts,
  context rules, placement, and appearance/interaction preferences. The feature owns pure radial
  geometry, session state, a cached profile snapshot, active-invocation pointer/click/keyboard
  input, and a borderless AppKit panel; it never owns command implementations. Installed apps use
  the shared parameterized open-application command. Recent/frequent wheel providers freeze a
  bounded view of shared successful-command history per session. See
  `docs/COMMAND_WHEEL_ARCHITECTURE.md` and ADR-0007.
- **File Search** is a registered launcher application backed by `FileSearching` contracts in
  SearchKit and a persistent local SQLite FTS5 index in the app target. The same service provides a
  bounded file-result section directly in root search; opening the full application remains
  available for previews, filters, and file actions. A direct filesystem snapshot makes names,
  paths, types, dates, sizes, and Finder tags searchable in bounded batches; a second phase adds
  bounded text/PDF extraction, optional Spotlight metadata, and on-device image OCR. FSEvents
  refresh changed paths without querying the disk on each keystroke. Search remains limited to
  security-scoped folders selected by the user and supports UTType-based filters. Native file
  actions are isolated behind `FileActionServicing`; they include Open With, sharing services,
  Finder integration, clipboard export, duplicate/copy/move/trash, and Commandly `.webloc`
  shortcuts. See `docs/FILE_SEARCH.md`, ADR-0003, and ADR-0010.
- The **BYOK AI vertical slice** introduces a dependency-free `AIKit` package and a dedicated app
  boundary for provider connections. The explicit initial catalog is OpenAI, Anthropic, Google
  Gemini, Mistral AI, Groq, xAI, OpenRouter, and loopback-only Ollama; provider authentication,
  discovery, capability evidence, errors, and native conversation context remain adapter-specific.
  Every listed adapter supports the initial non-streaming text/client-tool runtime. Cloud keys are
  revision-bound generic-password Keychain items through `SecureStoring`; UserDefaults receives
  only versioned non-secret provider/model metadata.
- **Finder AI** is the first built-in AI extension. Its in-memory launcher session gives the model
  declarative tools with conversation-scoped opaque handles, never raw path authority, AppleScript,
  a process API, or a shell. Read-only metadata work is bounded; content disclosure and every
  filesystem mutation require an exact local approval. Natural-language deletion means Move to
  Trash only, and permanent deletion is not a tool. Finder AI is limited to current user-selected
  folder scopes, reports partial failures honestly, and clears its conversation when the launcher
  session ends. See `docs/AI.md` and ADR-0006.
- **Shelf** owns one temporary floating board of external file/folder URL references and board-owned
  files materialized from explicit clipboard text/image imports. Each presentation request captures
  the active display before Commandly activates, increments a generation even when its entry mode is
  unchanged, and is reachable through launcher/menu commands or two tool-owned default Carbon
  shortcuts. Shelf and
  the launcher share the same configure-before-activate presentation policy and keep the same live
  window and feature state visible across Spaces until explicitly closed. While it remains open,
  Shelf observes active-Space/frontmost-application and display-configuration changes, preserves
  the board's relative manual position when work moves to another display, and clamps it back into
  a reachable visible frame after display geometry changes or disconnects.
  `ShelfBoardModel` keeps selection and security-scoped resource lifetime on the main actor; a
  per-board actor writes clipboard payloads beneath a private temporary directory and deletes owned
  files as items leave or the board is torn down. Focused Infrastructure contracts provide
  actor-confined metadata and batch file operations plus native Open With, sharing, Finder, Quick
  Look, pasteboard, and sound adapters. SwiftUI drag destinations accept concrete file URLs; drag
  sources offer copy only outside Commandly and always preserve staged references. A lower-priority
  whole-surface window drag gesture yields to controls and item drag sources and is disabled during
  outgoing item drags. On-disk moves and deletion remain separate explicit actions. No staged path,
  clipboard payload, or content is persisted or logged. See `docs/SHELF.md`.
- **Recent Downloads** uses an actor-confined, top-level metadata scan of the user's Downloads folder.
  Its narrow read-only sandbox entitlement permits listing and opening; the application exposes no
  mutation action and never logs filenames or paths.
- **Background Remover** owns a focused `BackgroundRemoving` Infrastructure contract and a native
  Apple Vision adapter. It reads only an explicitly picked or dropped image, runs foreground-instance
  segmentation away from the main actor, and returns an in-memory transparent PNG. Source bytes,
  masks, and output are not persisted, logged, or sent to an AI provider; export occurs only after the
  user chooses Save PNG and a destination.
- **Image Tools** uses the `ImageConverting` Infrastructure contract and an actor-confined ImageIO /
  CoreGraphics adapter. Its typed launcher session owns format/size/rotation options, bounded in-memory
  previews, stale-result cancellation, and explicit file export. It reads only picked/dropped images
  and writes fresh pixels without propagating source EXIF/GPS metadata. See `docs/IMAGE_TOOLS.md`.
  A separate `ImageRecognizing` contract and Vision actor extract text/QR payloads through the same
  bounded decoder. The inspection model owns editable OCR, QR selection, and explicit link review.
- **My Schedule** uses `ScheduleReading` Infrastructure value snapshots and an EventKit actor.
  Launcher sessions own agenda/filter/review state; AppRuntime retains the separately injected
  autojoin coordinator so one explicitly armed occurrence survives launcher dismissal. It rechecks
  access and the exact event/link/time before native handoff and clears in-memory state at teardown.
  Loading never prompts or opens a link. See `docs/SCHEDULE.md`.
- **Camera Preview** uses `CameraCapturing` and immutable Infrastructure frames/photos. Its native
  capture actor and serial video delegate keep AVFoundation objects and raster work off the main
  actor; the session model owns explicit permission, preview, review, cancellation, and export state.
  Camera permission is separate from activating a device. See `docs/CAMERA.md`.
- **File Browser** uses `FileBrowsing` over the existing selected-folder grants. An actor resolves
  current bookmarks per operation, traverses no-follow directory descriptors, and balances scoped
  access. Its model owns parent/child navigation and rejects stale requests without altering File Search.
- **Confetti** is session-local presentation with one finite SwiftUI Canvas schedule and a still
  Reduce Motion path. It has no persistence, system permission, or background service.
- **Screenshot** uses `ScreenshotCapturing` and immutable in-memory PNG artifacts. Native scoped
  picker or region selection feeds ScreenCaptureKit, then a dedicated actor renders bounded output.
  The launcher model owns review, explicit copy/export, and cancellation. See `docs/SCREENSHOT.md`.
- **Quick AI** reuses AIKit's provider adapters with an incremental, bounded HTTP transport. Its
  service pins connection and credential revisions; the session model owns ephemeral text context,
  reply cancellation, retry, and confirmed provider changes. It has no Finder AI tool or filesystem
  authority. See `docs/QUICK_AI.md`.
- **Screen Recording** retains an independent coordinator/window and a scoped ScreenCaptureKit
  stream/output worker. Video stays in actor-owned private temporary storage until explicit export.
  AppDelegate's `ApplicationTerminationCoordinator` stops recording and obtains its Save/Discard
  decision before the floating-note close sequence, then commits cleanup only for that exact
  approved recording state. Cancelled quit retains stopped review; new work invalidates approval.
  See `docs/SCREEN_RECORDING.md`.
- **Spelling & Grammar** uses bounded `WritingChecking` reports and asynchronous `NSSpellChecker`
  requests. A separate runtime-retained Services provider returns corrections only through the
  requestor's exact pasteboard transaction, with cancellable progress and an eight-second deadline.
  The app delegate installs that provider after launch; no automatic clipboard or AX input capture
  occurs. See `docs/WRITING_TOOLS.md`.
- **Translate** uses Apple's actual supported-language catalog and a fresh view-bound native
  session bridge per launcher session. A stable operation-specific configuration owns exactly one
  native translation/preparation call; cancellation retires the continuation and ignores stale
  results. Input/results stay in memory, with explicit system model-download consent and copy.
  See `docs/TRANSLATION.md`.
- **Menu Bar Shortcuts** retains up to eight explicit native status items behind a presenter port.
  Bounded ID-only preferences and the registered-command catalog feed an observable controller;
  each selected Open action revalidates the exact pin and dispatches through shared command execution
  with menu-bar provenance. See `docs/MENU_BAR_SHORTCUTS.md`.
- **Display Resolution** uses an actor-owned exact CoreGraphics configuration transaction and a
  retained independent confirmation window. A continuous 15-second deadline governs temporary preview;
  Keep requests login-session scope. The app termination gate restores a pending preview after stopping
  screen recording and before reviewing notes, then rechecks current state before replying to AppKit.
  See `docs/DISPLAY_RESOLUTION.md`.
- **Markdown Preview** is a registered application plus an embedded Finder Quick Look extension over
  one dependency-free `MarkdownPreviewKit` renderer. The app target owns explicit file selection,
  bounded image collection, observation, WebKit presentation, and export; the separately sandboxed
  extension receives only Finder's selected file URL. Raw document HTML/scripts and implicit network
  resources are blocked, local images require canonical in-directory containment and byte/count
  bounds, and no content/path/query is logged. Non-secret rendering settings cross the process
  boundary through the signed Commandly App Group. See `docs/MARKDOWN_PREVIEW.md` and
  [ADR-0009](decisions/ADR-0009-markdown-preview-quick-look-boundary.md).
- **Timers & Focus** retains a single `TimerStore` through the registered application instance. It derives remaining time from absolute dates so UI refresh cadence cannot introduce countdown drift; leaving the launcher does not stop active timers.
- **Finance** keeps Decimal subscription records and category budgets behind an actor-backed `FinancePersisting` boundary. Calendar-safe recurrence helpers derive monthly/yearly commitments, seven-day alerts, category summaries, and calendar occurrences without a network service or bank permission. See `docs/FINANCE.md`.
- **Productivity Library** stores user-authored snippets, quick notes, Quicklinks, and emoji keywords as versioned JSON under Application Support. Its actor-backed persistence contract is injected, content is never logged, and mutations publish to UI only after a successful save.
  All interactive editors share one persistence actor and use expected-version item transactions.
  AppRuntime retains `FloatingNoteCoordinator` independently of launcher sessions; AppDelegate
  defers termination while unsaved note windows resolve their close decisions. Idle library views
  refresh on saved-note revisions, while active drafts keep their original conflict baseline.
  See `docs/FLOATING_NOTES.md`.
- **System Activity** samples aggregate host resources in an actor and uses short `NSWorkspace` / `NSRunningApplication` hops on the main actor for GUI application discovery and explicit activation or termination. Quit-all protects Commandly, Finder, and the frontmost app and reports partial failures.
- **Storage Cleaner** is a registered review-first application over Infrastructure discovery and
  folder-picking contracts. Its actor scans bounded direct children of reviewed real-user Library
  locations for identifier-based app leftovers and third-party caches. Exact duplicate discovery is
  separately limited to one user-selected ephemeral folder, groups by size, and confirms identity
  with incremental SHA-256 hashing while retaining one copy per group. Recommendations, paths,
  sizes, hashes, and selections remain in memory; only explicitly confirmed items move through the
  existing native Trash adapter. See `docs/STORAGE_CLEANER.md`.
- **Microphone Control** reads and writes the public Core Audio mute property for the current default
  input device through an actor-confined Infrastructure contract. It does not capture samples,
  request Microphone permission, or fall back to lossy gain changes when a device lacks mute support.
- **Window Switcher** is non-shipping foundation/prototype work over focused Infrastructure
  contracts, in-memory adapters, presentation models, settings schema, and deterministic tests. Its
  prototype app-target adapters model public Accessibility enumeration/control, an active event tap,
  and optional ScreenCaptureKit thumbnails, but production composition must not register the
  application or start its coordinator while Commandly is sandboxed. Current-Space filtering,
  Command-Tab replacement, and Dock-hover behavior would remain best effort even in a future
  privileged runtime. See `docs/WINDOW_SWITCHER.md` and rejected
  [ADR-0008](decisions/ADR-0008-window-switcher-public-api-boundary.md).
- **Window Layouts** keeps layout geometry and custom-layout persistence separate from the Accessibility adapter. The adapter asks for Accessibility only from an explicit Apply action, then resizes the focused window against its display's visible work area. The built-in catalog contains 58 original normalized presets.
- **Offline Tools** groups small, focused application surfaces around injected pasteboard, dictionary, color-sampling, and font-catalog boundaries. Text conversion, color conversion, installed font discovery, dictionary lookup, and typing practice do not call network services.
- **Emoji Search** preserves its existing command IDs with a dedicated application and a lazy,
  immutable Unicode 17 catalog. Name, CLDR keyword, exact-sequence, category, and variant searches
  run locally. An explicit optional AI description uses the existing credential-pinned Quick AI
  service and accepts only validated catalog sequences. See [Emoji Search](EMOJI_SEARCH.md).
- `LauncherApplicationScreen` is an opt-in reusable search/filter/sidebar/detail composition. It centralizes focus, keyboard handling, semantic chrome, selection-row styling, empty states, and metadata rows for browser-style applications such as Clipboard History and File Search. Applications with different interaction models provide their own surface. See `docs/LAUNCHER_APPLICATIONS.md` and ADR-0004.
- Settings use a collapsible searchable sidebar, an integrated transparent titlebar, and flat
  section-based detail content under `Commandly/Scenes/Settings`, backed by `AppSettingsStoring` and
  permission/login-item services. AppKit owns the standard traffic-light controls and positions the
  Settings-owned sidebar toggle as a leading titlebar accessory, keeping it stable as the custom
  sidebar opens and closes. Liquid Glass is limited to genuinely elevated navigation or transient
  controls; ordinary settings rows use native controls, spacing, and hairlines. The Applications
  pane renders the registry's expandable group/application/tool hierarchy, locked built-in tags,
  removable user tags, per-application/tool shortcuts, typed-command syntax, and each definition's
  non-secret configuration schema; it contains no feature-specific settings branches. AI provider
  connection and active-model selection use a dedicated AI pane because credentials must never
  enter launcher configuration.
- Documentation uses a separate resizable `Window` under `Commandly/Scenes/Documentation`. `DocumentationCatalog` combines static core articles with every documented registry definition and resolves live aliases, shortcuts, actions, configuration, and enablement. The screen renders typed blocks and never parses repository Markdown at runtime. See `docs/DOCUMENTATION.md`.

## Concurrency rules

- UI state runs on `@MainActor`.
- No blocking I/O on the main actor.
- Prefer structured concurrency.
- Search and other long-running work must support cancellation.
- Avoid detached tasks unless justified.
- Do not use sleep as synchronization.
- Avoid `@unchecked Sendable` without explanation.
- Treat concurrency warnings as defects.

## Error handling

- Prefer typed errors (`CommandlyError` or module errors).
- Do not swallow errors silently.
- Map infrastructure failures at adapter boundaries.
- Never include secrets in error messages destined for logs.

## Persistence boundary

`Persistence` defines general store/repository contracts and ships an in-memory implementation for
tests. Its general-purpose durable backend remains intentionally undecided. Feature-owned stores may
choose a reviewed format behind a narrow contract. File Search uses local SQLite FTS5; Productivity
Library and Command Wheel profiles use focused versioned JSON in Application Support. The wheel
repository validates and atomically replaces complete configuration snapshots. A separate bounded
UserDefaults history stores only command ID, invocation source, outcome, record ID, and timestamp so
it can rank recent/frequent commands without retaining queries or arguments. See
`docs/decisions/OPEN_QUESTIONS.md`.

`LauncherApplicationPreferencesStoring` keeps only non-secret application/tool enablement, custom
tags, hotkeys, and schema-declared configuration. Built-in tags remain immutable definition
metadata. Typed-command text, inline file/clipboard queries, arguments, result paths, and clipboard
values are not preferences and do not enter the bounded command history.

Window Switcher contracts and prototype models define non-secret settings, but the sandboxed
production runtime is unregistered and disabled, so it must not write feature preferences. The
shared permission service may persist only content-free booleans recording that Accessibility or
Screen Recording was explicitly requested for an active consumer. If a future privileged runtime is
approved, window snapshots, titles,
queries, thumbnails, ordering, pointer locations, and shortcut key state must remain in memory and
be discarded when the active presentation or owning runtime ends.

AI credentials are outside this general persistence boundary: cloud keys use Keychain through
`SecureStoring`, while provider/model selection is non-secret UserDefaults metadata. Initial AI
conversations, prompts, tool arguments, results, filenames, paths, and disclosed contents are not
persisted.

Markdown Preview mirrors only its declared non-secret rendering configuration to the Commandly App
Group for Quick Look. Markdown text, rendered HTML, image data, paths, links, searches, outlines, and
recent-file state do not enter the shared domain. Optional scroll restoration uses a bounded one-way
path digest in the host process rather than a plaintext path.

## System integration boundary

`Infrastructure` exposes protocols for opening apps/URLs, filesystem checks, pasteboard,
notifications, workspace/frontmost-application introspection, and prototype Window Switcher
enumeration/actions. `SecurityKit.PermissionServicing` can represent Accessibility and Screen
Recording states; prototype app-target adapters model Accessibility, capture, and input behavior.
Implementations must not execute arbitrary shell strings. The app target also owns Carbon shortcut
registration and active-session AppKit window/input adapters; Command Wheel does not install an event
tap or global keyboard monitor.

The Window Switcher prototype must not be registered or started in production composition while
Commandly has App Sandbox enabled. Apple's
[App Sandbox guidance](https://developer.apple.com/documentation/security/protecting-user-data-with-app-sandbox)
lists assistive Accessibility API use and terminating other running apps as incompatible activities.
Its active event tap would receive the subscribed global key-event stream and filter unrelated input
immediately; it cannot truthfully be described as observing only its configured gesture. A passive
listen-only design requires Input Monitoring and cannot suppress or replace system shortcuts. A
separately signed non-sandboxed helper or a non-sandboxed direct-distribution build requires a new
accepted ADR. Any future runtime must still use public AppKit, Accessibility, Core Graphics, and
ScreenCaptureKit surfaces only; private Dock, Spaces, WindowServer, media, and blur APIs remain
forbidden. See rejected
[ADR-0008](decisions/ADR-0008-window-switcher-public-api-boundary.md).

## Extension boundary

`ExtensionKit` contains experimental models for future external extensions only. No extension
loading, JS runtime, marketplace, or remote code execution exists. A registered launcher item with
kind `AI Extension`, such as Finder AI, is reviewed native Commandly code; provider responses do not
install or execute extension code. Any future external-extension design must address signing,
permissions, sandboxing, and crash isolation. See `docs/EXTENSIONS.md`.

The bundled Markdown Quick Look target is an Apple app extension, not an `ExtensionKit` plug-in. It
is reviewed first-party Commandly code, imports only `MarkdownPreviewKit`, remains sandboxed and
read-only, and is embedded/signed with the host. Finder registration and enablement remain controlled
by macOS.

## Testing strategy

The optional System Companion is a separate, per-user app target embedded under the main app's
`Contents/Library/Helpers`, with an inert bundled LaunchAgent. `SystemCompanionKit` depends only on
Infrastructure and native frameworks; runtime construction does not register or connect it. The
System Integration Settings page provides explicit enable, connection check, and disable actions.
The current foundation authenticates metadata only and rejects future action payloads before
connecting. Main-app sandbox entitlements remain unchanged. See [System Companion](SYSTEM_COMPANION.md)
and accepted [ADR-0011](decisions/ADR-0011-optional-system-companion.md).

- Package tests cover contracts and pure logic with Swift Testing.
- App tests cover composition and navigation wiring.
- UI tests exist but are skipped by default in the shared scheme because they require GUI automation.
- Tests must not touch real clipboard, Keychain, network, user files, or macOS permission prompts.
- Command Wheel tests cover typed command parity, profile validation/migration/import, radial and
  multi-display geometry, hysteresis, session tokens, shortcut generations, input teardown,
  execution-once behavior, presentation semantics, and Settings editing with injected adapters.
  The exact automated and manual matrix is in `docs/COMMAND_WHEEL_TESTING.md`.
- Window Switcher tests use permission, enumeration, action, thumbnail, and shortcut doubles. They
  validate foundation logic only and do not prove a registered or sandbox-compatible runtime. Real
  Accessibility, active event filtering, capture, Dock/Command-Tab, Space, full-screen, and multi-
  display behavior belongs to a future authorized helper/direct-distribution acceptance matrix. See
  `docs/WINDOW_SWITCHER.md#verification`.
- Markdown Preview package tests cover sanitization, syntax, rendering configuration, outlines, and
  format identifiers. App tests use isolated temporary files and injected renderer/watcher/WebKit
  doubles. A successful build cannot prove Quick Look registration; signed Finder Space-bar and
  preview-pane behavior follows the manual matrix in `docs/MARKDOWN_PREVIEW.md`.
- AI provider tests use deterministic injected HTTP fixtures and fake credentials. Finder AI tests
  use in-memory secure storage and isolated authorized roots; they must cover opaque-handle scope,
  approval invalidation, cancellation, and prohibited operations without contacting a provider.

### Dictation ownership

Infrastructure's framework-free Dictation contracts separate microphone authorization, supported
languages/assets, capture events, and bounded text snapshots. AppRuntime builds one retained service
bundle for the registered Dictation application; its serial native actor prevents capture/download
overlap across launcher sessions. Speech and AVFoundation stay in app adapters. Session stop cancels
capture and clears draft state. A separate actor stores only explicitly saved text history; optional
writing-style requests reuse Quick AI. No focused-field companion insertion is implemented by this
slice. See [DICTATION.md](DICTATION.md) for limits, lifecycle, and native acceptance requirements.
