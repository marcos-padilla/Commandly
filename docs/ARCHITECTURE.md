# Architecture

## Overview

Commandly uses a thin macOS app target and a local Swift package of focused modules. The app target owns lifecycle, composition, and UI. Packages own reusable contracts and domain types.

## Modules

| Module | Responsibility | May depend on |
|--------|----------------|---------------|
| AppCore | Environment, metadata, typed errors, date/UUID/clock | — |
| CommandKit | Command descriptors and registry contracts | AppCore |
| SearchKit | Search query/result/provider contracts | AppCore |
| CalculatorKit | Calculator classify/parse/evaluate engine | AppCore |
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

`Commandly/Composition` is the only place that wires implementations:

- `AppBootstrapper` creates metadata and default services
- `AppDependencies` holds the dependency graph values
- `AppContainer` owns `AppState`, `AppRouter`, and factory helpers
- `LauncherApplicationRegistry` is the single source of truth for applications discoverable in the launcher

Prefer initializer injection. Do not introduce a DI framework.

## App state ownership

- `AppState` is `@MainActor` and `@Observable`.
- Navigation mutations go through `AppRouter`.
- Views receive focused view models; they do not reach into global mutable state.
- First-run onboarding lives under `Commandly/Scenes/Onboarding` and opens when `OnboardingStatusStoring` reports incomplete. Completion persists via a non-secret preference store and routes to `.root`.
- Onboarding permissions use `PermissionServicing` (mocked in tests; `SystemPermissionService` in production) and never block finishing the flow.
- After onboarding, Commandly runs as a **menu bar agent** (`MenuBarExtra` + `LSUIElement` / accessory activation policy): no persistent center-screen window, Dock icon hidden. Settings open via the standard Settings scene; Documentation opens in its own resizable standard window; Quit is available from the status item menu. Opening either utility window activates the app and orders that window front without using a permanent floating window level.
- The **launcher** is a floating, draggable SwiftUI `Window` (`AppWindowID.launcher`) opened by ⌥Space (`OptionSpaceHotkeyMonitor` via Carbon) or **Open Commandly** in the status item menu. Every built-in capability has a typed `LauncherApplicationDefinition` registered once in `LauncherApplicationRegistry`; launchable definitions attach a `LauncherApplication` implementation that creates a strongly typed session. Definitions form a hierarchy and declare kind, hotkey/enablement defaults, discovery metadata, optional non-secret configuration fields, and required structured documentation. `LauncherApplicationPreferencesStoring` persists user aliases and other overrides; aliases begin empty and feed command search only after the user sets them. Effective enablement inherits from groups, and `ApplicationHotkeyMonitor` registers conflict-safe Carbon shortcuts without an Accessibility prompt. `LauncherRootView` hosts the active session without feature-specific branches. Root search uses SearchKit providers (`CommandSearchProvider`, `ApplicationSearchProvider`, placeholders) merged by `CompositeSearchService` with cancellation on query change. **CalculatorKit** evaluates calculator-shaped queries in parallel and pins a Calculator section above other results. Installed macOS apps open through `ApplicationOpening` and remain distinct from Commandly's registered launcher applications. Root search shows a footer with an app menu (Documentation / Settings / Quit) and Actions; right-clicking an installed application (or Actions / ⌘K) opens a searchable application-actions panel (open, Finder, copy, favorites, ranking, auto-quit, disable, uninstall review with related files). Active application sessions expose footer actions through `CommandActionDescriptor`. **Clipboard History** is a fully implemented registered application (`ClipboardHistoryStore` + surface UI). Pasteboard monitoring runs headlessly after launch; image/file entries are enriched once at capture time via on-device Vision/PDFKit (OCR, labels, readable file text) so search never re-indexes while typing. Store updates must not activate the app or order the launcher front — only explicit open paths may call `NSApp.activate` / `BringHostingWindowToFront`.
- **File Search** is a registered launcher application backed by `FileSearching` contracts in SearchKit and a persistent local SQLite FTS5 index in the app target. A direct filesystem snapshot makes names, paths, types, dates, sizes, and Finder tags searchable in bounded batches; a second phase adds bounded text/PDF extraction, optional Spotlight metadata, and on-device image OCR. FSEvents refresh changed paths without querying the disk on each keystroke. Search remains limited to security-scoped folders selected by the user and supports UTType-based filters. Native file actions are isolated behind `FileActionServicing`; they include Open With, sharing services, Finder integration, clipboard export, duplicate/copy/move/trash, and Commandly `.webloc` shortcuts. See `docs/FILE_SEARCH.md` and ADR-0003.
- **Shelf** owns one temporary floating board of file/folder URL references. `ShelfBoardModel` keeps
  selection and security-scoped resource lifetime on the main actor, while focused Infrastructure
  contracts provide actor-confined metadata and batch file operations plus native Open With,
  sharing, Finder, Quick Look, pasteboard, and sound adapters. SwiftUI drag destinations accept
  concrete file URLs; drag sources offer copy only outside Commandly and always preserve staged
  references. On-disk moves and deletion remain separate explicit actions. No staged path or content
  is persisted or logged. See `docs/SHELF.md`.
- **Recent Downloads** uses an actor-confined, top-level metadata scan of the user's Downloads folder.
  Its narrow read-only sandbox entitlement permits listing and opening; the application exposes no
  mutation action and never logs filenames or paths.
- **Timers & Focus** retains a single `TimerStore` through the registered application instance. It derives remaining time from absolute dates so UI refresh cadence cannot introduce countdown drift; leaving the launcher does not stop active timers.
- **Productivity Library** stores user-authored snippets, quick notes, Quicklinks, and emoji keywords as versioned JSON under Application Support. Its actor-backed persistence contract is injected, content is never logged, and mutations publish to UI only after a successful save.
- **System Activity** samples aggregate host resources in an actor and uses short `NSWorkspace` / `NSRunningApplication` hops on the main actor for GUI application discovery and explicit activation or termination. Quit-all protects Commandly, Finder, and the frontmost app and reports partial failures.
- **Window Layouts** keeps layout geometry and custom-layout persistence separate from the Accessibility adapter. The adapter asks for Accessibility only from an explicit Apply action, then resizes the focused window against its display's visible work area. The built-in catalog contains 58 original normalized presets.
- **Offline Tools** groups small, focused application surfaces around injected pasteboard, dictionary, color-sampling, and font-catalog boundaries. Emoji data, text conversion, color conversion, installed font discovery, dictionary lookup, and typing practice do not call network services.
- `LauncherApplicationScreen` is an opt-in reusable search/filter/sidebar/detail composition. It centralizes focus, keyboard handling, semantic chrome, selection-row styling, empty states, and metadata rows for browser-style applications such as Clipboard History and File Search. Applications with different interaction models provide their own surface. See `docs/LAUNCHER_APPLICATIONS.md` and ADR-0004.
- Settings use a collapsible quiet sidebar, persistent top navigation chrome, and card pages under `Commandly/Scenes/Settings`, backed by `AppSettingsStoring` and permission/login-item services. The Applications pane renders the registry hierarchy and each definition's configuration schema; it contains no feature-specific settings branches.
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
choose a reviewed format behind a narrow contract: File Search uses local SQLite FTS5, while
Productivity Library uses versioned JSON in Application Support. See
`docs/decisions/OPEN_QUESTIONS.md`.

## System integration boundary

`Infrastructure` exposes protocols for opening apps/URLs, filesystem checks, pasteboard, notifications, and workspace introspection. Implementations must live behind these protocols and must not execute arbitrary shell strings.

## Extension boundary

`ExtensionKit` contains experimental models only. No extension loading, JS runtime, marketplace, or remote code execution exists. Any future design must address signing, permissions, sandboxing, and crash isolation. See `docs/EXTENSIONS.md`.

## Testing strategy

- Package tests cover contracts and pure logic with Swift Testing.
- App tests cover composition and navigation wiring.
- UI tests exist but are skipped by default in the shared scheme because they require GUI automation.
- Tests must not touch real clipboard, Keychain, network, user files, or macOS permission prompts.
