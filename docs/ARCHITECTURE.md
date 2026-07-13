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
- After onboarding, Commandly runs as a **menu bar agent** (`MenuBarExtra` + `LSUIElement` / accessory activation policy): no persistent center-screen window, Dock icon hidden. Settings open via the standard Settings scene; Quit is available from the status item menu. Opening Settings activates the app and orders the Settings window front (above other Commandly windows such as onboarding) without using a permanent floating window level.
- The **launcher** is a floating, draggable SwiftUI `Window` (`AppWindowID.launcher`) opened by ⌥Space (`OptionSpaceHotkeyMonitor` via Carbon) or **Open Commandly** in the status item menu. Every built-in capability has a typed `LauncherApplicationDefinition` registered once in `LauncherApplicationRegistry`; launchable definitions attach a `LauncherApplication` implementation that creates a strongly typed session. Definitions form a hierarchy and declare kind, hotkey/enablement defaults, discovery metadata, and optional non-secret configuration fields. `LauncherApplicationPreferencesStoring` persists user aliases and other overrides; aliases begin empty and feed command search only after the user sets them. Effective enablement inherits from groups, and `ApplicationHotkeyMonitor` registers conflict-safe Carbon shortcuts without an Accessibility prompt. `LauncherRootView` hosts the active session without feature-specific branches. Root search uses SearchKit providers (`CommandSearchProvider`, `ApplicationSearchProvider`, placeholders) merged by `CompositeSearchService` with cancellation on query change. **CalculatorKit** evaluates calculator-shaped queries in parallel and pins a Calculator section above other results. Installed macOS apps open through `ApplicationOpening` and remain distinct from Commandly's registered launcher applications. Root search shows a footer with an app menu (Settings / Quit) and Actions; right-clicking an installed application (or Actions / ⌘K) opens a searchable application-actions panel (open, Finder, copy, favorites, ranking, auto-quit, disable, uninstall review with related files). Active application sessions expose footer actions through `CommandActionDescriptor`. **Clipboard History** is a fully implemented registered application (`ClipboardHistoryStore` + surface UI). Pasteboard monitoring runs headlessly after launch; image/file entries are enriched once at capture time via on-device Vision/PDFKit (OCR, labels, readable file text) so search never re-indexes while typing. Store updates must not activate the app or order the launcher front — only explicit open paths may call `NSApp.activate` / `BringHostingWindowToFront`.
- **File Search** is a registered launcher application backed by `FileSearching` contracts in SearchKit and a persistent local SQLite FTS5 index in the app target. A direct filesystem snapshot makes names, paths, types, dates, sizes, and Finder tags searchable in bounded batches; a second phase adds bounded text/PDF extraction, optional Spotlight metadata, and on-device image OCR. FSEvents refresh changed paths without querying the disk on each keystroke. Search remains limited to security-scoped folders selected by the user and supports UTType-based filters. Native file actions are isolated behind `FileActionServicing`; they include Open With, sharing services, Finder integration, clipboard export, duplicate/copy/move/trash, and Commandly `.webloc` shortcuts. See `docs/FILE_SEARCH.md` and ADR-0003.
- `LauncherApplicationScreen` is an opt-in reusable search/filter/sidebar/detail composition. It centralizes focus, keyboard handling, semantic chrome, selection-row styling, empty states, and metadata rows for browser-style applications such as Clipboard History and File Search. Applications with different interaction models provide their own surface. See `docs/LAUNCHER_APPLICATIONS.md` and ADR-0004.
- Settings use a collapsible quiet sidebar, persistent top navigation chrome, and card pages under `Commandly/Scenes/Settings`, backed by `AppSettingsStoring` and permission/login-item services. The Applications pane renders the registry hierarchy and each definition's configuration schema; it contains no feature-specific settings branches.

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

`Persistence` defines store/repository contracts and ships an in-memory implementation for tests. The durable backend (SwiftData, Core Data, SQLite, or files) is intentionally undecided. See `docs/decisions/OPEN_QUESTIONS.md`.

## System integration boundary

`Infrastructure` exposes protocols for opening apps/URLs, filesystem checks, pasteboard, notifications, and workspace introspection. Implementations must live behind these protocols and must not execute arbitrary shell strings.

## Extension boundary

`ExtensionKit` contains experimental models only. No extension loading, JS runtime, marketplace, or remote code execution exists. Any future design must address signing, permissions, sandboxing, and crash isolation. See `docs/EXTENSIONS.md`.

## Testing strategy

- Package tests cover contracts and pure logic with Swift Testing.
- App tests cover composition and navigation wiring.
- UI tests exist but are skipped by default in the shared scheme because they require GUI automation.
- Tests must not touch real clipboard, Keychain, network, user files, or macOS permission prompts.
