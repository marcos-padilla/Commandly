# ADR-0004: Registered launcher applications and reusable screen composition

- Status: Accepted
- Date: 2026-07-13

## Context

The launcher catalog described Clipboard History and File Search, but presentation bypassed that
catalog. `LauncherViewModel` created concrete feature models with identifier checks and
`LauncherRootView` repeated those checks to choose concrete views. Adding another view capability
therefore required edits across registration, routing, state, keyboard actions, footer actions, and
root presentation. Clipboard History and File Search also duplicated their search/filter header,
split-pane layout, selection chrome, empty states, and metadata rows.

## Decision

Treat each built-in launcher capability as a `LauncherApplication` registered in one
`LauncherApplicationRegistry`.

- A manifest remains the CommandKit discovery contract.
- Launching a view application constructs a strongly typed model and view.
- `LauncherApplicationSession` type-erases only the shell-facing surface and controls required for
  dynamic hosting.
- `LauncherRootView` hosts the active session without concrete feature branches.
- `LauncherApplicationScreen` and its companion components provide opt-in composition for the
  existing search/filter/sidebar/detail design.
- Applications with different layouts remain free to provide their own surfaces and internal screen
  navigation.
- Application-specific dependencies use focused groups and initializer injection.

## Consequences

- Adding an application requires a feature implementation, one application registration type, one
  registry entry, and tests; root routing and presentation do not change.
- Clipboard History and File Search share structural UI behavior without sharing domain state.
- Dynamic hosting requires type erasure, but it is isolated to one session boundary.
- The app target still uses `CommandManifest` and CommandKit search terminology; this avoids a broad
  package migration while clarifying the app-layer concept.
- Installed macOS applications and registered Commandly applications remain separate concepts.

## Rejected alternatives

- A route enum case per feature: preserves compile-time routing but repeats launcher-shell changes for
  every application.
- One generic feature view model: forces unrelated domains into a large protocol and makes specialized
  screens harder to express.
- `AnyView` throughout feature code: weakens type checking beyond the single dynamic boundary.
- Moving concrete SwiftUI views into CommandKit: violates the package/app-target boundary and couples
  discovery contracts to presentation.
