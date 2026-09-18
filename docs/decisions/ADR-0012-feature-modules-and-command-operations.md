# ADR-0012: Feature modules, command operations, and default-deny AI exposure

- Status: Accepted — implemented for the Timers reference module on 2026-09-18
- Date: 2026-09-18
- Related: [ADR-0001](ADR-0001-modular-architecture.md), [ADR-0004](ADR-0004-registered-launcher-applications.md),
  [ADR-0005](ADR-0005-configurable-application-definitions.md), [ADR-0006](ADR-0006-byok-ai-and-finder-tool-safety.md),
  [ADR-0007](ADR-0007-command-wheel-shared-execution.md), [ADR-0010](ADR-0010-application-tools-tags-and-inline-discovery.md),
  [migration ledger](../MODULARIZATION_PROGRESS.md)

## Context

Commandly is one native macOS application with ~50 shipped features. ADR-0004 and ADR-0005 already
gave the launcher a generic registry with typed application definitions, and ADR-0007 gave every
invocation surface one shared execution coordinator. Those decisions hold.

What did not scale is **composition**. Every built-in feature is constructed in one factory,
`LauncherApplicationRegistry.makeBuiltIn(...)`, which by the baseline commit took roughly fifty
parameters and performed forty-eight registrations. That factory also became the place where
unrelated features borrow each other's services: File Search's pasteboard and URL opener are
threaded into Downloads, Logos, Offline Tools, Emoji Search and Dictation, and Quick AI's chat
service is threaded into Emoji Search and Dictation. Feature ownership is therefore not visible in
the code; it is implied by a parameter list.

Two further gaps motivated this decision:

1. **Operations versus presentation.** Several commands only open a surface. `timers.new` opens a
   countdown draft. There was no way for a caller to start a countdown without presenting the
   launcher, and no way for a result to say "I opened a form" rather than "I did the thing".
2. **AI exposure.** `AIKit` has tool contracts, but nothing decided *which* commands may be offered
   to a model. Absent an explicit rule, the default drifts toward "whatever exists".

## Decision

### 1. A module is the unit of feature ownership

A **module** owns a feature's implementation, commands, settings schema, documentation, lifecycle
and tests. It is distinct from:

- an **application / surface** — a user-facing entry point a module contributes; one module may
  contribute several, or none;
- a **command** — an executable operation with stable identity, validated input and a typed result;
- an **AI tool** — an authorized *projection* of a command, never a second implementation;
- a **group / category** — a discovery hierarchy, not a code dependency.

The existing Group → Application → Tool enablement inheritance is unchanged. A module's effective
enablement is derived from the launcher applications it owns, so there is still exactly one
enablement store.

### 2. Three new contract targets, no second command engine

| Target | Owns | Must not |
|--------|------|----------|
| `ModuleKit` | Data-only module metadata; command, settings, documentation, lifecycle and availability contracts | Import SwiftUI, AppKit, AIKit, or any feature |
| `ModuleRuntime` | The generic host: validation, deterministic catalog projection, lazy exactly-once activation, ownership-scoped tokens, teardown | Import any feature target or SwiftUI |
| `AICommandBridge` | Provider-neutral tool projection and call adaptation over `AIKit` | Import any feature target, or call a feature service |

`SharedCommandExecutionCoordinator` remains **the** execution engine. The module host resolves
*handlers*; it does not execute commands on its own behalf, and the AI bridge reaches a command only
through `ModuleCommandDispatching`, which the app implements over the shared coordinator.

`ModuleHost` is deliberately not a service locator. It exposes handlers for commands a module
*declared*, and has no API for fetching a module's internal services.

### 3. Metadata discovery has no side effects

An assembly's `manifest`, `commandDefinitions`, `settings` and `documentation` are metadata.
Reading them must not construct a service, request a permission, open a connection, start capture,
or begin indexing. Services are created only in `activate()`, which the host calls at most once per
registration generation even under concurrent requests.

This is what lets Settings and Documentation list every module — including disabled and
unavailable ones — without waking the application up.

### 4. Commands distinguish operations from presentation

`ModuleCommandPolicy` records an execution mode (`direct`, `requiresUserInterface`, `longRunning`),
an effect (`readOnly`, `localMutation`, `filesystemMutation`, `externalAction`), a disclosure class,
and an idempotency flag.

`ModuleCommandOutcome` is richer than `CommandResult` and projects onto it:

| Outcome | `CommandResult` | History outcome |
|---------|-----------------|-----------------|
| `succeeded` | `.success` | `succeeded` |
| `accepted` (long-running started) | `.success` | `succeeded` |
| `failed` | `.failure` | `failed` |
| `denied` | `.failure` | `failed` |
| `unavailable` | `.failure` | `failed` |
| `interactionRequired` | `.failure` | `failed` |
| `cancelled` | `.cancelled` | `cancelled` |

Message-only consumers and persisted history therefore keep working unchanged. Crucially,
`interactionRequired` is not success: opening a draft or a window never reports that the underlying
mutation happened, and `accepted` never reports that long-running work finished.

Authority is carried by `ModuleCallerGrants`, supplied by the host from trusted invocation
provenance. **Model-supplied arguments can never create a grant.** Filesystem mutation, external
action, and private-content disclosure each require their own grant on top of a caller identity.

### 5. AI exposure is default-deny, in two stages

1. **Build-time review.** A command is invisible to AI unless its own module declares
   `aiExposure: .reviewed`. The default value of the policy initializer is `.hidden`, so a command
   is never exposed by omission.
2. **Runtime eligibility.** A reviewed command is offered only while its module is actually
   available. Disabled, permission-blocked, disconnected and failed modules withdraw their tools.
   Commands whose execution mode is `requiresUserInterface` are never offered at all, because a
   model could not truthfully report completing them.

Module enablement is **not** an AI grant. Local permission to access data, authority to mutate it,
and consent to disclose it to a remote provider stay three separate decisions, consistent with
ADR-0006.

The bridge rejects malformed, unknown, oversized and type-mismatched input *before* dispatch, so a
rejected call has no effect. Internal identifiers are mapped to provider-safe names deterministically
and collision-checked; a collision is an error, never a silent merge.

### 6. Composition is an explicit list

`Commandly/Composition/BuiltInModules.swift` holds one line per compiled-in module. Adding a normal
feature means writing its module target, tests, documentation and package target, and adding that
one line. It must not require editing a feature switch in `AppRuntime`, `SettingsRootView`, launcher
search, the documentation catalog, or the AI executor.

### 7. Platform declarations stay at build time

Runtime registration is honestly impossible for some things, and this ADR does not pretend
otherwise. The Markdown Quick Look app extension, the System Companion helper and its LaunchAgent,
and Info.plist declarations are configured in the Xcode project. They are listed as explicit
exceptions in `docs/ARCHITECTURE.md`.

## Consequences

**Good.** Feature ownership is visible in the target graph and enforced by
`scripts/check-module-boundaries.sh`, which runs inside `make verify`. Cross-feature coupling that
used to hide in a parameter list now has to be either an extracted shared capability or a declared,
acyclic dependency. Commands can be automated without opening a window, and results stop overstating
what happened.

**Costs.** There are now two metadata shapes for one concept during the migration: a module's
`ModuleConfigurationField` and the launcher's `LauncherConfigurationField`. Modules author the
former; `Commandly/Composition/ModuleSettingsProjection.swift` projects it onto the latter so there
is one authored source and one projection rather than two hand-maintained copies. The projection is
a temporary adapter and should be removed when `LauncherConfigurationField` is retired in favour of
the module schema.

Similarly, authored documentation bodies still use the app-target `LauncherApplicationDocumentation`
model. `ModuleDocumentationContribution` currently carries article identity, summary and validated
references. Merging the two is deferred; the ledger records it as outstanding.

**Rejected alternatives.**

- *One `Features` target.* Keeps the coupling, moves it one directory down.
- *One target per menu item.* Splits small features into three targets each for no compilation or
  process-boundary benefit.
- *A dependency-injection framework or a service-locator container per module.* Explicitly out of
  scope; assemblies take their dependencies through their own initializers.
- *A general event bus.* Ordering-sensitive operations stay explicit request/response calls; typed
  observable state covers notifications.
- *Dynamic plug-in loading or a marketplace.* Commandly stays one compiled-in native application.

## Status of implementation

Timers & Focus is the reference module and is migrated. The remaining inventory, milestone status,
and outstanding work are tracked in [the migration ledger](../MODULARIZATION_PROGRESS.md). This ADR
describes the accepted target architecture; it does not claim the whole application has reached it.
