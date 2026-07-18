# ADR-0007: Command Wheel as a shared-command presentation layer

- Status: Accepted
- Date: 2026-07-16

## Context

Commandly's launcher application registry already owned registered feature definitions and their
presentation implementations, while CommandKit's `CommandRegistry` held metadata only. Root search
could launch a registered feature through `LauncherViewModel`, and installed-application rows called
an `ApplicationOpening` adapter directly. There was no reusable typed invocation, resolution,
execution, or cross-surface history path for a radial interface to join.

Implementing action switches in Command Wheel would create a second launcher and make behavior,
permissions, errors, and history diverge from search. Treating saved wheel slots as executable
closures would also make profiles unsafe to persist and impossible to migrate.

## Decision

Command Wheel is a presentation and interaction layer over one shared command pipeline.

- CommandKit owns typed, Codable command arguments and references, invocation context/source,
  resolution, availability, execution result, and privacy-safe usage-history contracts.
- The existing `CommandRegistry` remains the single metadata resolver. The app composition root
  atomically synchronizes all known launchable manifests plus shared non-surface commands with an
  immutable availability snapshot. Disabled commands remain resolvable as unavailable.
- A shared app-layer coordinator resolves a reference, validates availability, calls one executor,
  and records the result category. Search, application hotkeys, and Command Wheel call that
  coordinator with different invocation sources.
- Registered Commandly applications continue to use the existing
  `LauncherApplicationRegistry` implementation and session presentation boundary. The executor
  reaches it through a narrow main-actor presentation protocol rather than duplicating feature
  construction.
- Installed macOS applications use one parameterized `applications.open-installed` command whose
  bundle identifier is a typed argument. Search results and wheel assignments therefore reach the
  same `ApplicationOpening` adapter and ranking update. Availability for this manifest is evaluated
  per reference against the existing installed-application query.
- Wheel persistence stores profiles, pages, stable slots, and `CommandReference` values only. It
  never stores closures, AppKit actions, resolved sessions, provider output, or usage history.
- The profile graph uses focused versioned JSON storage in Application Support with atomic writes,
  matching the repository's precedent for complex user-authored data. A bounded privacy-safe
  command history uses the existing preferences system.
- Global shortcuts share one Carbon registration owner. Carbon press and release events provide
  hold lifecycle without Accessibility permission; the wheel does not install a global key logger.

## Consequences

- A command added correctly to the shared engine becomes resolvable from every presentation
  surface without wheel-specific execution code.
- Saved references can become unavailable when commands are disabled or removed; the editor and
  runtime must preserve and clearly mark them rather than substitute another command.
- Registered feature presentation remains main-actor work, while resolution, history, persistence,
  and dynamic-provider preparation can remain off the main actor.
- Search and wheel regression tests can inject one executor and prove identity of the called
  implementation while checking distinct invocation sources.
- Wheel rendering, geometry, panel lifecycle, profile editing, and input state remain app-target
  concerns. Domain packages do not import Commandly.
- Command arguments may contain private values and must never be logged. Durable usage history is
  deliberately restricted to command ID, source, outcome, record ID, and timestamp.

## Rejected alternatives

- A wheel command registry or action enum: duplicates the existing registry and drifts as commands
  change.
- Direct `NSWorkspace`, file, URL, clipboard, or automation calls from wheel code: bypasses shared
  validation, permissions, errors, and history.
- Persist resolved command implementations or closures: not safely serializable or migratable.
- A global keyboard event tap for the default gesture: requests broader permission than Carbon
  hot-key press/release and active-session pointer sampling require.
- Raw global display pixels for fixed placement: break when display arrangement or scaling changes;
  normalized usable-frame coordinates have deterministic fallback behavior.
