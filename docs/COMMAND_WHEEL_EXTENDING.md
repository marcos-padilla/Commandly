# Extending Command Wheel

Command Wheel is intentionally thin. It stores layout and presents references to shared commands;
it is not another place to implement an action.

> Developers should not add command execution logic directly to Command Wheel. New actions belong
> in Commandly's shared command engine.

Read [Command Wheel Architecture](COMMAND_WHEEL_ARCHITECTURE.md),
[Launcher Applications](LAUNCHER_APPLICATIONS.md), and ADR-0007 before changing an execution path.

## Make an existing registered command available

1. Confirm the owning `LauncherApplicationDefinition` has a stable `CommandManifest` and is
   registered with `LauncherApplicationRegistry`.
2. Put all user-visible title, subtitle, symbol, category, keywords, argument schema, and default
   actions in that manifest. Do not create a wheel icon/title table.
3. Confirm the application has correct effective-enabled behavior. The composition root keeps its
   known manifest in `CommandRegistry` and marks disabled commands unavailable in the atomic
   availability snapshot.
4. Add a `CommandReference(commandID:arguments:)` through Settings or the search contextual action.
5. Test resolution through `CommandRegistry`, execution through
   `SharedCommandExecutionCoordinator`, and both `.search` and `.commandWheel` invocation sources.

No change to the wheel executor should be needed for a registered launcher application. The shared
executor's main-actor presenter already routes its identifier to the existing application session.

## Add a new shared command correctly

Use a registered `LauncherApplication` when the command presents a Commandly feature surface. Use a
focused non-surface shared command only for an immediate reusable engine action.

1. Add a stable `CommandID` and `CommandManifest` in the owning shared/app composition layer.
2. Declare typed `CommandArgument` values. Choose the narrowest supported value type, mark required
   values, and use a default only when omission has stable meaning.
3. Add a `CommandReference` factory when callers repeatedly construct the same safe argument set.
4. Implement behavior behind an existing domain/Infrastructure protocol. If no protocol exists,
   add one to the module that owns the capability and inject its native adapter.
5. Route the new ID in the shared executor or register it as a normal launcher application. Do not
   import AppKit into CommandKit.
6. Return `CommandResult` and typed sanitized failures. Keep permission explanation, recovery, and
   the execution-time recheck in the owning feature/service. Declare any permission needed for the
   command itself as a non-secret `CommandAvailabilityRequirement` on its manifest so search,
   Settings, and Command Wheel can reject it consistently without prompting.
7. Let the production availability evaluator include the known manifest and its current state in
   the atomic catalog snapshot.
8. Add package tests for schema/default/type validation and app tests proving search and wheel
   references call the same implementation.

Never log the reference's argument dictionary. A command whose reusable arguments may contain a
credential is not safe for profile persistence; redesign the command to reference a secure stored
connection identifier instead.

## Add a dynamic provider

A wheel provider produces bounded shared `CommandReference` values; it does not execute items.
Before adding a provider, confirm the same category can be represented properly in Commandly's
shared command/search engine. A wheel-only list of AppKit closures is not acceptable.

1. Define a stable provider ID and user-facing name.
2. Define maximum result count, supported sort methods, empty state, refresh strategy, cache policy,
   resolution behavior, and sanitized error behavior. Schema v1 implements only `onInvocation`
   refresh with `invocation` caching; reserved policy values are rejected.
3. Add the ID to `CommandWheelDynamicProviderID.supported` and extend validator compatibility
   checks. Supporting another refresh/cache policy also requires real runtime behavior, Settings,
   schema/migration review, and tests—not just permitting the enum value.
4. Implement a Sendable provider adapter that returns command references and respects cancellation.
5. Inject it into wheel preparation; resolve and freeze its output before the page becomes
   interactive. Never update order after execution in the same session.
6. Expose the provider in Settings with a non-drag assignment path and missing/error preview states.
7. Add tests for bounds, sorting, empty/error behavior, cancellation, stale-token rejection, stable
   order, and missing command references.

`commands.recent` and `commands.frequent` are the reference implementations. Both read the shared
privacy-safe successful-command history; neither maintains wheel-specific recency. Because history
excludes arguments, they skip references that cannot be replayed from the command ID plus schema
defaults before applying the result limit.

Provider preparation scans only the top 96 candidates in its configured ranking and shares command
resolution outcomes across the complete profile invocation. A new provider must preserve or tighten
that bounded-work contract; do not iterate an unbounded external result set while the wheel opens.

## Add a context rule type

The current rule is an exact frontmost-application bundle identifier with numeric priority.
Extending it changes persisted data and selection semantics:

1. Add an explicit Codable representation rather than inferring a rule from optional fields.
2. Bump the profile schema version and migrate every previous rule.
3. Update validation, deterministic priority/tie-breaking, conflict reporting, import remapping, and
   Settings controls together.
4. Capture any required context once before presentation. Prefer system notifications to polling.
5. Keep rule evaluation pure and nonisolated; never hard-code third-party identifiers.
6. Test exact match, no match, priority, conflict, disabled profile/rule, explicit-profile override,
   migration, and privacy boundaries.

Do not add window-title or document-content matching without a separate permission/privacy design.

## Add a segment presentation state

Presentation derives from the frozen `CommandWheelPresentedSegment`; the persisted segment remains
UI-neutral.

1. Add a semantic state only when it changes user understanding or interaction.
2. Map it during preparation, outside SwiftUI `body`.
3. Render it using existing DesignSystem roles and the manifest's system symbol.
4. Supply label, value, hint, selected/disabled traits, and a stable accessibility identifier on one
   coherent segment element. Hide decorative wedge layers.
5. Ensure light/dark appearance, Increased Contrast, Reduce Transparency, and Reduce Motion do not
   alter selection behavior.
6. Test state mapping independently from pixel rendering and add a UI assertion for the semantic
   accessibility output.

Never add a segment-state switch that calls `NSWorkspace`, file services, a pasteboard, URL opener,
permission API, or command implementation.

## Add a profile migration

Profile and transfer files carry explicit schema versions.

1. Add the new version constant without changing an old version's meaning.
2. Define a Decodable legacy shape for the previous representation.
3. Map every field to a complete current `CommandWheelConfiguration`, supplying documented safe
   defaults for new fields.
4. Normalize the required default profile, then validate the entire rooted graph.
5. Rewrite durable storage atomically only after successful decode and validation.
6. Keep unsupported or corrupt originals intact and return a sanitized typed error.
7. Extend transfer import separately when its shape changes.
8. Test current round trip, previous migration, unknown fields, corruption, unsupported future
   versions, graph invalidity, default recreation, and import ID/reference remapping.

## Test new geometry behavior

Geometry is pure AppKit-global, Y-up math. Keep it independent from `NSScreen`, panel frames,
SwiftUI animation, and event delivery.

- Add parameterized coverage for 4, 6, 8, and 12 slots when angular behavior changes.
- Include exact clockwise boundaries, negative angles/coordinates, start-angle offsets, dead and
  neutral regions, empty slots, submenu radius, and final fast-flick samples.
- For positioning, cover every usable-frame corner, menu bar/Dock insets, negative display origins,
  gaps, scaling, normalized fixed points, missing displays, and oversized content.
- Test hysteresis as a sequence, not isolated points: boundary noise, intentional crossing, return
  to center, slow movement, and final release.

Selection must always use the positioner's `actualCenter` after edge clamping.

## Debug input monitoring

1. Verify the profile shortcut appears exactly once in the unified `GlobalShortcutPlan`.
2. Inspect registration issues for duplicate ID, duplicate hot key owner, or Carbon unavailable.
3. Confirm press and release carry the same registration generation.
4. Confirm key repeat and duplicate release produce no state transition.
5. While open, inspect that one pointer timer exists. Toggle mode may additionally own local/global
   mouse-down monitors; hold mode must not.
6. Close, disable, replace the shortcut, activate another application, trigger any display-geometry
   change, or terminate the app and confirm sampling, dwell work, monitors, provider tasks, and the
   panel are removed.

Do not debug by adding a global keyboard monitor. It changes permission requirements and can hide
the actual Carbon lifecycle problem.

## Debug window placement

1. Capture the pointer location and immutable display snapshots before any activation.
2. Log only display/session identifiers and requested/actual centers—not window titles or private
   application data.
3. Feed the snapshot to `CommandWheelPositioningEngine` and inspect `wasClamped`.
4. Confirm the panel frame equals the returned content frame and selection uses returned actual
   center.
5. Check active-Space collection behavior, exclusion from normal cycling, and nonactivating hold
   mode independently from geometry.
6. Reproduce with negative-origin displays, each Dock edge, a menu bar on another display, and a
   supported full-screen application.

## Diagnose permissions

Command Wheel's Carbon shortcut, active-session pointer sampling, mouse-down outside-click monitor,
and temporary toggle panel do not require Accessibility permission.

If a selected command reports a permission problem:

1. Resolve the same reference from launcher search and confirm it reports the same result.
2. Inspect the manifest's declared requirement, the production availability snapshot, and the
   owning feature's `PermissionServicing` state and recovery route.
3. Confirm Command Wheel did not request the permission at activation or cache a stale permission
   result across invocations.
4. Revoke access in System Settings while a wheel is active and confirm the command fails safely
   through its normal path.
5. Update [Permissions](PERMISSIONS.md) and the owning feature documentation when a new capability is
   introduced.

## Required verification

Run the focused package/app/UI tests documented in
[Command Wheel Testing](COMMAND_WHEEL_TESTING.md), then run `make verify`. Inspect the final diff for
new command switches in wheel files; there should be none.
