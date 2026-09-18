# Timers module

Target: `TimersModule` · Module ID: `timers` · Status: shipping

Timers & Focus is the reference implementation for Commandly's feature-module architecture
([ADR-0012](../../../../docs/decisions/ADR-0012-feature-modules-and-command-operations.md)).

## What it does

Named countdowns and focus sessions. Timers keep running after Commandly is dismissed and finish
with an optional local macOS sound.

## What lives where

| Concern | Location |
|---------|----------|
| Countdown domain (`CountdownTimer`, `TimerStore`) | `Sources/TimersModule/Domain/` |
| The one timer-starting operation and its handlers | `Sources/TimersModule/Commands/` |
| Typed configuration schema | `Sources/TimersModule/Settings/` |
| Authored documentation | `Sources/TimersModule/Documentation/` |
| Identifiers, canonical command definitions, manifest | `Sources/TimersModule/TimersModule.swift` |
| Assembly and lifecycle | `Sources/TimersModule/TimersAssembly.swift` |
| Launcher surface (SwiftUI) | `Commandly/Scenes/Launcher/Commands/Timers/` (app target) |
| Launcher application | `Commandly/Scenes/Launcher/Applications/TimersApplication.swift` |

The SwiftUI surface deliberately stays in the app target for now: moving it requires a
`CommandlyUI` target that owns the launcher session contract. That is tracked in the
[migration ledger](../../../../docs/MODULARIZATION_PROGRESS.md).

## Commands

| Command ID | Meaning | Mode | Input | Output | AI |
|------------|---------|------|-------|--------|-----|
| `timers.focus` | Open the Timers & Focus application | requiresUserInterface | — | presented session | hidden |
| `timers.focus.tool.open` | Open the timers surface | requiresUserInterface | — | presented session | hidden |
| `timers.new` | Open the **new-timer draft** | requiresUserInterface | — | presented session with draft | hidden |
| `timers.start` | **Start a countdown immediately** | direct | `durationSeconds` (int, 1–86400, required), `title` (string, optional) | `timerID`, `title`, `durationSeconds`, `phase`, `endsAt` | **reviewed** |

### `timers.new` is not `timers.start`

`timers.new` opens a draft for the user to complete. It has always meant that, and it still does.
Turning it into "start a timer" would change a shipped command's meaning and would let a caller
believe a countdown was running when only a form had opened. `TimersIdentifierCompatibilityTests`
guards this.

### One operation, several entry points

`TimerOperations.start(_:)` is the module's only way to start a countdown. Both of these go through
it:

- the Timers UI's own draft-start action (`TimersViewModel.startDraftTimer()`), and
- the `timers.start` command, from search, a shortcut, the Command Wheel, the menu bar, or AI.

The command runs through `LauncherApplicationToolBackgroundInvoking`, so it never opens the
launcher, and the countdown continues because `TimerStore` owns its own refresh source.

## Settings

| Variable | Kind | Default | Meaning |
|----------|------|---------|---------|
| `completionSound` | toggle | `true` | Play a local macOS sound when a timer finishes |

`completionSound` is the key the shipped application already persists, so existing user preferences
survive the migration unchanged. The schema is authored once here and projected onto the launcher's
settings model by `Commandly/Composition/ModuleSettingsProjection.swift`.

## Capabilities

None. Timers requires no macOS permission, no account connection, and no folder grant.

## Storage

The module persists nothing of its own today: countdowns live in the retained `TimerStore` for the
life of the process. Deactivating the module stops the store's refresh source and does **not**
discard its timers — disabling a module is not permission to delete its data.

## AI exposure review

**Exposed: `timers.start` only.**

Reviewed on 2026-09-18. It is safe for a model to call because:

- it performs a purely local, in-process mutation (`localMutation`), touching no file, network, or
  account;
- it discloses no user content (`disclosure: .none`) — its output is an identifier, the caller's own
  title, the duration, the phase, and the end time;
- its input is bounds-checked (1 second to 24 hours) *before* any timer is created, so an invalid or
  overflowing request has no effect;
- it is marked non-idempotent, so it is never retried automatically — a retry would create a second
  countdown;
- it returns a stable timer identifier and end time, so the caller can report truthfully what
  happened.

**Not exposed:** `timers.focus`, `timers.focus.tool.open`, `timers.new`. All three open native UI. A
model cannot complete them, and reporting them as done would be false. They return
`interactionRequired` to a non-interactive caller.

## Tests

`Packages/Modules/Timers/Tests/TimersModuleTests` covers identifier compatibility, command policy,
input validation and bounds, the direct operation, host integration and laziness, deactivation
cleanup, and the AI bridge end to end with a fake dispatcher — no provider adapter, network call, or
paid API is involved.

`CommandlyTests/TimersApplicationTests.swift` covers the same behavior through the launcher
application, including that `timers.start` never presents a session and that the UI draft and the
command produce equivalent countdowns.
