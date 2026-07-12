# Architecture

## Overview

Commandly uses a thin macOS app target and a local Swift package of focused modules. The app target owns lifecycle, composition, and UI. Packages own reusable contracts and domain types.

## Modules

| Module | Responsibility | May depend on |
|--------|----------------|---------------|
| AppCore | Environment, metadata, typed errors, date/UUID/clock | — |
| CommandKit | Command descriptors and registry contracts | AppCore |
| SearchKit | Search query/result/provider contracts | AppCore |
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

Prefer initializer injection. Do not introduce a DI framework.

## App state ownership

- `AppState` is `@MainActor` and `@Observable`.
- Navigation mutations go through `AppRouter`.
- Views receive focused view models; they do not reach into global mutable state.
- First-run onboarding lives under `Commandly/Scenes/Onboarding` and opens when `OnboardingStatusStoring` reports incomplete. Completion persists via a non-secret preference store and routes to `.root`.
- Onboarding permissions use `PermissionServicing` (mocked in tests; `SystemPermissionService` in production) and never block finishing the flow.
- After onboarding, Commandly runs as a **menu bar agent** (`MenuBarExtra` + `LSUIElement` / accessory activation policy): no persistent center-screen window, Dock icon hidden. Settings open via the standard Settings scene; Quit is available from the status item menu.
- Settings use a glass sidebar + card pages under `Commandly/Scenes/Settings`, backed by `AppSettingsStoring` and permission/login-item services.

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
