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
| Navigation / routing | `Commandly/Navigation` |
| SwiftUI scenes and feature UI | `Commandly/Scenes` |
| Assets / strings | `Commandly/Resources` |
| Info.plist / entitlements | `Commandly/Configuration` |
| Domain-neutral primitives | `Packages/Sources/AppCore` |
| Command contracts | `Packages/Sources/CommandKit` |
| Search contracts | `Packages/Sources/SearchKit` |
| UI tokens | `Packages/Sources/DesignSystem` |
| macOS / system integration protocols | `Packages/Sources/Infrastructure` |
| Persistence contracts | `Packages/Sources/Persistence` |
| Secure storage / permissions contracts | `Packages/Sources/SecurityKit` |
| Experimental extension models | `Packages/Sources/ExtensionKit` |
| Logging | `Packages/Sources/Observability` |
| App target tests | `CommandlyTests` |
| Package tests | `Packages/Tests` |
| Reusable test doubles | package test targets or a future TestSupport module |

Domain modules must never import the Commandly app target.

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
2. Identify the owning module.
3. Add or extend domain contracts first.
4. Implement system adapters behind protocols in Infrastructure / Persistence / SecurityKit.
5. Compose dependencies in `Commandly/Composition`.
6. Add tests that do not touch real clipboard, Keychain, network, or permissions.
7. Update documentation when behavior or architecture changes.
8. Review accessibility (VoiceOver labels, keyboard, Dynamic Type where applicable).
9. Review privacy and permissions.
10. Measure critical-path performance when touching launch or search paths.

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
