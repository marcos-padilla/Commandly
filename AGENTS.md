# AGENTS.md

Guidance for humans and AI agents working on Commandly.

## Project mission

Commandly is a native macOS, keyboard-first productivity launcher. It should feel fast, private, and dependable.

Commandly must remain **original**. Do not copy Raycast, Alfred, or Spotlight source code, branding, assets, icons, marketing copy, or exact UI layouts. General category inspiration is fine; cloning is not.

This repository is currently a **foundation**. Do not pretend launcher features exist when only contracts or placeholders are present.

## Required first steps

Every future agent must:

1. Read this file (`AGENTS.md`).
2. Read relevant documentation under `docs/` for the task.
3. Inspect Git status (`git status --short`) before editing.
4. Understand the requested scope and refuse drive-by refactors.
5. Run the current verification command when practical (`make doctor` / `make verify`).
6. Identify the module that owns the change.
7. Avoid modifying unrelated files.
8. Run targeted tests for the change.
9. Run `make verify` before claiming completion.
10. Report exactly what changed and what was tested.

## Source-of-truth order

1. User instructions for the current task
2. `AGENTS.md`
3. Accepted ADRs in `docs/decisions/`
4. Architecture documentation (`docs/ARCHITECTURE.md` and related)
5. Tests
6. Existing implementation
7. Reasonable defaults

## Folder ownership

| Concern | Location |
|---------|----------|
| App entry, AppKit delegate, app state | `Commandly/Application` |
| Dependency assembly | `Commandly/Composition` |
| Built-in feature module registration (one line per module) | `Commandly/Composition/BuiltInModules.swift` |
| Module settings schema projection | `Commandly/Composition/ModuleSettingsProjection.swift` |
| AI bridge dispatch over the shared executor | `Commandly/Composition/SharedCommandModuleDispatcher.swift` |
| Navigation / routing | `Commandly/Navigation` |
| SwiftUI scenes and feature UI | `Commandly/Scenes` |
| Launcher application contract, sessions, and shared application screens | `Commandly/Scenes/Launcher/Applications` |
| Launcher application registry | `Commandly/Composition/LauncherApplicationRegistry.swift` |
| Menu bar status item menu | `Commandly/Scenes/StatusBar` |
| Settings window (sidebar + pages) | `Commandly/Scenes/Settings` |
| First-run onboarding UI | `Commandly/Scenes/Onboarding` |
| Shared launcher chrome (back, option menu) | `Commandly/Scenes/Shared` |
| App preference helpers (e.g. onboarding completion) | `Commandly/Services` |
| Assets / strings | `Commandly/Resources` |
| Info.plist / entitlements | `Commandly/Configuration` |
| Domain-neutral primitives | `Packages/Sources/AppCore` |
| Command contracts | `Packages/Sources/CommandKit` |
| Search contracts | `Packages/Sources/SearchKit` |
| UI tokens | `Packages/Sources/DesignSystem` |
| macOS / system integration protocols | `Packages/Sources/Infrastructure` |
| Login item registration (`SMAppService`) | `Packages/Sources/Infrastructure` |
| Persistence contracts | `Packages/Sources/Persistence` |
| Secure storage / permissions contracts | `Packages/Sources/SecurityKit` |
| AI provider/model/tool contracts and adapters | `Packages/Sources/AIKit` |
| BYOK connection storage, Keychain, and Finder AI filesystem boundary | `Commandly/Services/AI` |
| AI provider setup UI | `Commandly/Scenes/Settings` |
| Finder AI launcher application and conversation UI | `Commandly/Scenes/Launcher/Commands/FinderAI` |
| Slack custom emoji session, connection UI, and result UI | `Commandly/Scenes/Launcher/Commands/SlackEmoji` |
| Slack custom emoji credentials, HTTP, decoding, and export adapters | `Commandly/Services/SlackEmoji` |
| Notion workspace browsing UI and session | `Commandly/Scenes/Launcher/Commands/Notion` |
| Notion read-only API, credentials, and parsing | `Commandly/Services/Notion` |
| Hermes/OpenClaw agent connections and streaming | `Commandly/Services/AI/ExternalAgents` |
| Hermes/OpenClaw launcher chat UI | `Commandly/Scenes/Launcher/Commands/ExternalAgents` |
| Experimental extension models | `Packages/Sources/ExtensionKit` |
| Markdown rendering, preview configuration, and format identifiers | `Packages/Sources/MarkdownPreviewKit` |
| Markdown Preview launcher application, model, and UI | `Commandly/Scenes/Launcher/Commands/MarkdownPreview` |
| Markdown Preview file, watcher, rendering, and reading-state adapters | `Commandly/Services/MarkdownPreview` |
| Finder Markdown Quick Look app extension | `CommandlyMarkdownQuickLook` |
| Logging | `Packages/Sources/Observability` |
| Module metadata and contribution contracts | `Packages/Sources/ModuleKit` |
| Generic module host (activation, catalog, cleanup) | `Packages/Sources/ModuleRuntime` |
| AI tool projection and call adaptation | `Packages/Sources/AICommandBridge` |
| Feature modules | `Packages/Modules/<Feature>/Sources/<Feature>Module` |
| Feature module tests | `Packages/Modules/<Feature>/Tests/<Feature>ModuleTests` |
| Timers & Focus domain, commands, settings, documentation | `Packages/Modules/Timers` |
| App target tests | `CommandlyTests` |
| Package tests | `Packages/Tests` |
| Reusable test doubles | package test targets or a future TestSupport module |

Domain modules must never import the Commandly app target.

Feature modules must additionally never import `ModuleRuntime`, `AICommandBridge`, or another
feature module. `ModuleRuntime` and `AICommandBridge` must never import a feature module.
`scripts/check-module-boundaries.sh` enforces this and runs inside `make verify`.

## Coding standards

- Use initializer-based dependency injection.
- Keep UI state on `@MainActor`.
- Prefer structured concurrency and respect cancellation.
- Use typed errors (`CommandlyError` or module-specific errors).
- Keep files small and focused.
- Document public package APIs with doc comments.
- Keep business logic out of SwiftUI views; use view models / services.
- Never log secrets, tokens, clipboard contents, private URLs, credentials, file contents, or full search history.
- Do not add third-party dependencies without following the dependency policy below.
- Treat Swift concurrency warnings as defects.

## Forbidden patterns

- Force unwraps (`!`) in production code
- Force casts (`as!`) in production code
- `try!` in production code
- Mutable global state / giant singletons
- Blocking I/O on the main thread / main actor
- Automatic permission prompts at launch
- Secrets in source control, plists, logs, or UserDefaults
- Arbitrary shell execution or unsafe string interpolation into commands
- Empty `catch` blocks / swallowed errors
- Arbitrary `Task.sleep` used as synchronization
- Dependency cycles between modules
- A feature module importing the app target, the module host, the AI bridge, or another feature
- Constructing services, prompting for permissions, or reading private data in module metadata
- Reporting `.success` for a command that only opened a window or started long-running work
- Exposing a command to AI without an explicit `.reviewed` decision
- Production code depending on test-support modules
- `@unchecked Sendable` without a documented justification
- Copying competitor branding or UI

## Concurrency rules

- UI state and view models run on `@MainActor`.
- Do not perform blocking I/O on the main actor.
- Prefer structured concurrency (`async let`, task groups, actors).
- Support cancellation in search and long-running work.
- Avoid detached tasks unless clearly justified and documented.
- Do not use arbitrary delays as synchronization.
- Do not add `@unchecked Sendable` without a detailed explanation in code comments and, for public types, documentation.

## Adding features

1. Define expected user behavior.
2. Identify the owning module. If the feature needs a new one, scaffold it:
   `./scripts/new-module.sh <Name>` (see `docs/ARCHITECTURE.md`).
3. Add or extend domain contracts first.
4. Author canonical command definitions in the module. Give a command that opens a surface
   `executionMode: .requiresUserInterface`; add a `direct` operation when a caller should be able
   to do the work without opening a window.
5. Implement system adapters behind protocols in Infrastructure / Persistence / SecurityKit.
6. Register the module with **one line** in `Commandly/Composition/BuiltInModules.swift`. Do not
   add a feature branch to `AppRuntime`, `SettingsRootView`, launcher search, the documentation
   catalog, or the AI executor.
7. Add tests that do not touch real clipboard, Keychain, network, or permissions.
8. Update documentation when behavior or architecture changes.
9. Review accessibility (VoiceOver labels, keyboard, Dynamic Type where applicable).
10. Review privacy and permissions.
11. Measure critical-path performance when touching launch or search paths.

### AI exposure is default-deny

A command is never offered to an AI model unless its module explicitly declares
`aiExposure: .reviewed`. Changing a command to `.reviewed` is a reviewed decision, not a
convenience:

- It must be completable without native UI. `requiresUserInterface` commands are never exposed.
- Record the review in the module's `Docs/README.md`: what it does, what it can disclose, and why a
  model may call it.
- `CommandlyTests/ModuleCompositionTests.swift` asserts the exact exposed tool set. Extending it is
  a deliberate change that must be justified in the pull request.

## Adding dependencies

Before adding any dependency:

1. State a clear reason.
2. Check for a native Apple alternative.
3. Review maintenance status.
4. Review licensing.
5. Review security implications.
6. Add the dependency only to the module that needs it.
7. Document the decision (ADR when non-trivial).

This foundation phase intentionally has **zero** third-party packages.

## Adding permissions

Before requesting a new macOS permission:

1. Document the user benefit in `docs/PERMISSIONS.md`.
2. Prompt only when the user activates the feature.
3. Explain why before the system prompt when possible.
4. Handle denial and provide Settings recovery steps.
5. Complete a privacy review.
6. Update entitlements / Info usage strings only as needed.
7. Add tests that mock permission state — never require the real permission in CI.

## Definition of done

A task is complete only when:

- The requested behavior works
- Architecture boundaries are preserved
- The app compiles
- Relevant tests pass
- `make verify` passes
- Documentation is updated when needed
- Privacy was reviewed for the change
- Accessibility was reviewed for UI changes
- No secret was introduced
- Limitations are reported honestly

## No false claims

Agents must never claim:

- A build passed without running it
- Tests passed without running them
- Signing works without checking it
- A scaffolded feature is complete
- A permission works without testing it
- A file was changed when it was not

## Tooling notes

- Project format requires **Xcode 27+**.
- Scripts resolve a compatible `DEVELOPER_DIR` automatically; override with `COMMANDLY_DEVELOPER_DIR` if needed.
- SwiftLint / SwiftFormat are optional; missing tools must not fail bootstrap/build, but `make verify` fails if an installed tool reports violations.
- `make boundaries` runs the module boundary check on its own; `make verify` runs it as step 2.
- `make new-module NAME=<Name>` scaffolds a feature module.
- `swift test --package-path Packages` needs `DEVELOPER_DIR` pointing at Xcode 27. The
  default Command Line Tools toolchain cannot build the package. `scripts/verify.sh` exports
  the correct one via `scripts/common.sh`.
