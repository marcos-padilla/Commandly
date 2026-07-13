# ADR-0005: Typed, configurable launcher application definitions

- Status: Accepted
- Date: 2026-07-13

## Context

ADR-0004 removed feature-specific routing and presentation branches, but the registry still stored
only executable application objects. It could not represent groups, application roles, aliases,
global shortcuts, enablement, or configuration metadata. Implementing those concerns independently
inside each feature would duplicate persistence and Settings UI and make new applications expensive.

## Decision

Separate immutable application definitions from optional launch implementations.

- Every registry node has a stable identifier, kind, optional parent, presentation metadata,
  defaults, and an optional typed configuration schema.
- Groups are definition-only. Launchable nodes attach a `LauncherApplication` implementation.
- The registry validates hierarchy and schema invariants and resolves user overrides.
- Group enablement is inherited by descendants. Only effectively enabled launchable nodes participate
  in search and hotkey registration.
- Aliases are user-owned, begin empty, and augment CommandKit search keywords once configured.
- Global shortcuts use Carbon registration and report duplicate or unavailable combinations without
  requiring Accessibility permission.
- A single generic Settings pane renders hierarchy and field editors from definitions.
- Configuration values are non-secret and persisted through a focused UserDefaults-backed service.
  Declared values are passed to application models at launch.

## Consequences

- New application settings require schema declarations and behavior consumption, not bespoke
  Settings views or persistence keys.
- Arbitrary-depth application trees and new application kinds do not change launcher routing.
- Disabling a group consistently removes all descendants from discovery and shortcut handling.
- Hotkey registration remains a macOS app-target concern behind one adapter.
- Credentials and other secrets are intentionally unsupported by this store and will require a
  SecurityKit-backed design.

## Rejected alternatives

- One settings model per feature: duplicates persistence, validation, and UI.
- Store untyped dictionaries without schemas: makes runtime failures and stale values likely.
- Put app-target configuration in CommandKit: would couple reusable command contracts to macOS UI and
  Carbon concerns.
- Request Accessibility permission for shortcuts: Carbon hotkeys provide the required behavior
  without broad input-monitoring access.
