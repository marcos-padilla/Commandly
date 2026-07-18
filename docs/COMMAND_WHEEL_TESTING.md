# Command Wheel Testing

Command Wheel combines pure geometry with Carbon events, an AppKit panel, SwiftUI presentation,
versioned persistence, and the shared command executor. No one test layer proves the feature. A
release candidate needs deterministic package/app tests, opt-in GUI automation, focused manual
macOS checks, accessibility review, performance measurements, and the full Commandly regression
suite.

This document separates the coverage present in the working tree from results recorded for a
particular implementation. A test name or command below is not a claim that it passed.

## Safety and fixtures

- Automated tests use in-memory registries, resolvers, executors, history, profile repositories,
  display snapshots, timers, event monitors, focus restorers, and application openers.
- Persistence tests use an isolated temporary directory or a dedicated disposable UserDefaults
  suite. They do not read or replace the user's Command Wheel configuration.
- Tests must not trigger real Accessibility prompts, inspect private window titles, open user files,
  read the real clipboard, call a provider network, or execute user commands.
- UI fixtures must use DEBUG-only launch arguments and stable accessibility identifiers. Production
  must not expose a hidden shortcut, test command, or bypass for availability/permission checks.
- Manual testing may exercise real system integration only on a disposable profile/configuration.
  Export a profile before destructive import/reset cases.

## Automated coverage map

### CommandKit package tests

`Packages/Tests/CommandKitTests/CommandKitTests.swift` covers the reusable boundary the wheel must
not duplicate:

- typed Codable command references and argument values;
- schema/default/required/type validation and rejection of malformed values;
- atomic catalog replacement and resolution/availability behavior;
- invocation-source value semantics;
- bounded recent/frequent usage-history summaries.

Any new wheel-assignable command needs package coverage for its manifest and typed arguments. An
app-level test must then prove search and wheel reach the same executor or presenter.

### App unit and integration tests

| Test source | Primary risk covered |
|---|---|
| `CommandWheelDomainTests.swift` | Conservative defaults; Codable value round trip; stable IDs; slot bounds; rooted page tree; missing/cyclic/unreachable pages; supported providers and rejection of reserved refresh/cache policies; appearance/argument validation; deterministic context profile selection and conflicts |
| `CommandWheelPersistenceTests.swift` | Empty storage; durable current-schema round trip; v0 migration and rewrite; corrupt/future schema preservation; default recreation; collision-safe import remapping; malformed/unsupported transfer rejection |
| `CommandWheelGeometryTests.swift` | 4/6/8/12-slot clockwise geometry; start offsets; exact boundaries; dead/neutral/selection/submenu regions; actual clamped center; empty-slot clearing; movement threshold; hysteresis; final fast-flick sample; keyboard skipping/wrapping |
| `CommandWheelPositioningTests.swift` | Cursor, active-center, and normalized fixed placement; visible-frame corners; negative origins; shared edges; display gaps; scale snapshots; missing preferred display; invalid/oversized screens; deterministic clamping/fallback |
| `CommandWheelStateMachineTests.swift` | Required state transitions; duplicate press/release/execution; release without selection; submenu transitions; provider-task ownership/cancellation; failure dismissal; stale async work; unique session generations |
| `CommandWheelRuntimeTests.swift` | Final pointer sample and exactly-once shared dispatch, including release during preparation; frontmost/display/Space invalidation before presentation; stale release and queued global-click generations; toggle dismissal; circular interactive-region pass-through; keyboard activation; submenu/center return; mode-specific monitor ownership; explicit teardown; panel flags/observer lifecycle; accessibility semantics; bounded/deduplicated dynamic content and missing/unavailable states |
| `CommandWheelSettingsModelTests.swift` | Preload/edit and catalog-refresh race ordering; invalid transactional edits; one-save submenu assignment; subtree pruning; stable slot IDs; direct installed-app search/typed assignment/native icon metadata; reference-aware availability; explicit occupied-slot replacement; duplicate/runtime shortcut issues; context conflicts |
| `CommandWheelAssignmentTests.swift` | Registered and installed-app contextual actions; typed installed-app references and display-label preservation; explicit occupied-slot replacement; move/remove; atomic submenu placement; reference listing; injected Settings reveal routing |
| `GlobalShortcutMonitorTests.swift` | Duplicate IDs/hot keys; invalid key codes; repeat suppression; paired press/release generation; queued stale-callback rejection when Carbon numeric IDs are reused; cancellation on replacement/stop; runtime ordering; disabled profiles; launcher conflict precedence |
| `SharedCommandExecutionTests.swift` | One sanitized error mapping; identical installed-app opener for search/wheel; distinct invocation sources; registered-app presentation; failure recording; durable bounded privacy-safe history |
| `SharedCommandExecutionCatalogRefreshTests.swift` | Serialized catalog snapshot/publication; coalescing into one newer pass; no successful caller resumes on a stale generation; failure ownership and recovery |
| `ApplicationCacheTests.swift` | Off-main application-icon loading; bundle/path alias reuse; success/failure TTL; explicit invalidation; LRU capacity; installed-app discovery TTL/invalidation |
| `DocumentationTests.swift` | Typed in-app Command Wheel article registration, searchable workflows, permission boundary, and contextual assignment guidance |

Settings model/editing and search-context assignment tests should exercise transactional saves,
validation failure without partial publication, profile/page/slot CRUD, occupied-slot replacement,
subtree-safe submenu removal, command picker reuse, import/export, reset, and reveal-in-Settings. If
those tests move to a new source file, add it to this table rather than weakening the expected
coverage.

## Exact automated commands

Use Xcode 27 or newer. Repository scripts resolve a compatible Xcode automatically; an explicit
override keeps local and CI runs reproducible:

```bash
export COMMANDLY_DEVELOPER_DIR="/path/to/Xcode.app/Contents/Developer"
```

Run the shared CommandKit contract tests:

```bash
DEVELOPER_DIR="$COMMANDLY_DEVELOPER_DIR" \
  swift test --package-path Packages --filter CommandKitTests
```

Run all app tests, including the Command Wheel suites:

```bash
DEVELOPER_DIR="$COMMANDLY_DEVELOPER_DIR" \
  xcodebuild \
    -project Commandly.xcodeproj \
    -scheme Commandly \
    -configuration Debug \
    -destination 'platform=macOS' \
    -derivedDataPath .derivedData \
    -only-testing:CommandlyTests \
    test
```

Run the complete package/app/build gate after focused work:

```bash
COMMANDLY_DEVELOPER_DIR="$COMMANDLY_DEVELOPER_DIR" make verify
```

`make verify` does not run GUI automation. Record each command, toolchain, and result in the
execution record below; do not summarize skipped tests as passed.

## Opt-in UI automation

The `CommandlyUIValidation` scheme is intentionally outside the default verification path because
it launches and controls native macOS windows. Run the full UI target so existing File Search
coverage also guards shared launcher behavior:

```bash
DEVELOPER_DIR="$COMMANDLY_DEVELOPER_DIR" \
  xcodebuild \
    -project Commandly.xcodeproj \
    -scheme CommandlyUIValidation \
    -configuration Debug \
    -destination 'platform=macOS' \
    -derivedDataPath .derivedData \
    -only-testing:CommandlyUITests \
    test
```

Command Wheel UI cases must use direct DEBUG-only entry points and stable identifiers to verify at
least:

- the wheel container, segment semantics, center target, selection value, and submenu state;
- icon-only runtime segments with full command/application names retained in accessibility labels and
  no visible static name text around the ring;
- keyboard movement, Return activation, Escape/back, and focus restoration in Toggle mode;
- Settings feature toggle, profile selection/creation, live preview, page/slot selection, command
  picker, occupied-slot confirmation, context-rule controls, and import/export entry points;
- unavailable/missing segment semantics and a non-drag editing route;
- Reduce Motion behavior without timing-dependent hit-test assertions.

Inspect the `.xcresult` to confirm Command Wheel cases were discovered. A successful UI command that
ran only unrelated cases is not Command Wheel UI coverage.

## Manual functional matrix

Record the macOS and hardware/display arrangement for every row.

| Area | Cases | Expected invariant |
|---|---|---|
| Hold/release | Press and hold; slow select; fast flick; release in dead zone, neutral ring, empty slot, unavailable slot; key repeat; release after shortcut replacement | Final physical pointer sample decides; exactly one available command runs; every cancellation path runs none |
| Toggle/click | Open; hover; inside click; center click; outside click; second shortcut press; right/other mouse buttons | Selection/cancellation matches the configured mode; outside click is not swallowed; no monitor survives dismissal |
| Keyboard | Tab, Shift-Tab, four arrows, 1–9, Return, Escape at root/child, all-empty page | Stable clockwise order wraps and skips non-actionable slots; focus returns to the previous app |
| Submenus | Directional threshold, dwell, click-only, disabled, center return, Escape, rapid page changes | One page is visible; no stale dwell/provider task changes the current page; back never executes a prior highlight |
| Dynamic content | Empty, one, bounded many, missing, unavailable, provider failure, non-replayable parameterized history; execute then reopen | Order is frozen while open, non-replayable candidates are skipped before the limit, and content refreshes on the next invocation; failure is sanitized |
| Context rules | Match/no match; exact bundle ID; priority tie; disabled rule/profile; explicit profile with/without override; another process activates while presented | Selection follows documented priority, captures context before Commandly changes focus, and cancels before stale context can execute |
| Settings | Enable/disable; add/rename/duplicate/reorder/delete/default; page/slot edits; direct command/application picker; typed arguments; recent/frequent; reset; import/export/collision/malformed file | Every change is validated and durable before publication; installed apps persist an exact typed bundle-ID reference; final usable default remains; no secret/runtime history enters transfer JSON |
| Search assignment | Registered command and installed app; empty/occupied slot; replace/move/remove; new submenu; reveal Settings | Assignment uses the shared reference and explicit replacement; existing search actions remain available |
| Command parity | Run the same registered command and installed app from search, app hotkey, and wheel | Same implementation/permission/error behavior; source differs; no double presentation or history record |
| Failure recovery | Missing command, invalid saved argument, disabled owner, denied command permission, opener failure, corrupt profile file | Wheel does not substitute or crash; existing feedback/recovery appears; corrupt storage remains preserved |
| Lifecycle | 100 open/cancel cycles; terminate while held/open; disable feature; edit shortcut/profile while held; activate another app; sleep/wake | Panel, timers, event monitors, provider/execution tasks, and registrations tear down; context change and stale key-up cannot affect a new session |

## Displays, Spaces, and focus

Test pointer, active-display-center, and fixed placement on:

- one display with menu bar and each Dock edge;
- two displays with different scale factors;
- a display left or below the primary (negative global coordinates);
- displays separated by a coordinate gap and displays sharing an edge;
- a small usable frame that forces center clamping;
- a full-screen application and at least two normal Spaces.

For each arrangement, confirm the panel appears on the captured display/Space, uses the returned
actual center for highlighting, stays the configured size near edges, and does not enter normal
Window menu/cycling. Change Spaces with the wheel open; disconnect a display; and change display
arrangement, scale, menu-bar ownership, or Dock/usable-frame geometry. Every geometry notification
must cancel without executing a stale selection. Hold mode must not activate Commandly; Toggle mode
may activate temporarily but must restore the prior process.

## Accessibility and appearance

Use VoiceOver and keyboard navigation with Default/Larger text, Comfortable/Compact density,
light/dark appearance, Increase Contrast, Reduce Transparency, and Reduce Motion. Confirm:

- each actionable segment is one element with title, position, selection, availability, and submenu
  state, while decorative shapes are absent from the accessibility tree;
- center cancel/back is distinct, and unavailable/missing/error/loading states are understandable
  without color;
- spoken and visual selection remain synchronized while moving quickly or crossing a boundary;
- icon tiles, state glyphs, and optional keyboard-hint badges do not overlap at supported sizes,
  while full names remain available to VoiceOver;
- reduced settings do not alter hit regions, release timing, or keyboard order;
- every Settings operation has a labeled keyboard/button/menu route and visible focus indication.

Record assistive-technology findings separately from automated accessibility identifier assertions.

## Performance and leak validation

Use a Release build on the same reference Apple-silicon Mac for comparisons. Measure at least 30
warm activations after one discarded warm-up and report median, p95, maximum, macOS/Xcode version,
display arrangement, profile size, placement mode, and dynamic-provider state.

Targets are defined in [Performance](PERFORMANCE.md): warm shortcut-to-visible under 50 ms and
sampled-input-to-model feedback under 16 ms. The measurement must exclude shortcut-recording time
and command execution. Profile activation must show no synchronous profile-file read, full command
index, repeated icon decode, or per-frame screen enumeration.

Use Instruments Time Profiler and Allocations/Leaks (or Xcode's memory graph for object ownership)
while repeating open, submenu, execute, and dismiss cycles. Confirm bounded dynamic provider output
and stable memory after settling. Inspect that `CommandWheelPanel`, hosting controller, input
lifecycle, event monitor tokens, pointer/dwell timers, and provider tasks are released. A unit test
that observes a fake cancellation is not evidence that AppKit monitor tokens or the real panel do
not leak.

## Regression review

Before completion, verify that:

- ⌥Space still toggles the launcher and Shelf's two fixed shortcuts still route correctly;
- registered-application hotkeys still present their existing session once, including cold launch;
- launcher command and installed-app search retain selection, ranking, action menus, feedback, and
  dismissal behavior;
- disabled applications stay absent from discovery but saved wheel references remain visibly
  unavailable;
- Settings, Documentation, onboarding, menu-bar commands, and app termination still work;
- no new Accessibility prompt appears merely from enabling or opening Command Wheel;
- logs, UserDefaults history, profile export, and errors contain no query, pointer path, clipboard or
  file content, credential, private URL, or unapproved argument value.

## Execution record for this implementation

Validation recorded on 2026-07-16 used macOS 27.0 (26A5378n), Xcode 27.0 (27A5218g),
and an M4 Pro MacBook Pro with 48 GB of memory. The available physical setup had only the built-in
display, keyboard, and trackpad. Automated passes are recorded separately from pending manual work,
unavailable hardware coverage, and measurements that were not performed.

| Check | Execution details | Result |
|---|---|---|
| `make doctor` | Final current-tree run with the Xcode 27 developer directory | Passed |
| Focused CommandKit tests | Covered by the successful package-test phase of `make verify`; no separate final filter-only invocation was recorded | Passed within `make verify` |
| Focused wheel/domain/settings/runtime/cache tests | Debug `xcodebuild` run of `ApplicationCacheTests`, `CommandWheelGeometryTests`, `CommandWheelDomainTests`, `CommandWheelRuntimeTests`, and `CommandWheelSettingsModelTests`; 75 tests / 78 invocations. Result bundle: `/tmp/commandly-root-focused/Logs/Test/Test-Commandly-2026.07.16_18-15-11--0400.xcresult`. Cache coverage includes the 128-entry LRU cap and success/failure TTL behavior | Passed |
| Shared catalog refresh tests | Focused `SharedCommandExecutionCatalogRefreshTests` run; 11/11. Result bundle: `/private/tmp/commandly-catalog-refresh-derived/Logs/Test/Test-Commandly-2026.07.16_18-15-18--0400.xcresult` | Passed |
| App test target | Final `make verify` app-test phase; 405 tests. Result bundle: `.derivedData/Logs/Test/Test-Commandly-2026.07.16_18-31-26--0400.xcresult` | Passed |
| `make verify` | Final current-tree run after test hardening; package tests, 405 app tests, and the Debug app build completed | Passed |
| Command Wheel UI automation | Focused `CommandlyUIValidation` run; 9/9 Command Wheel UI tests. Result bundle: `.derivedData/Logs/Test/Test-CommandlyUIValidation-2026.07.16_18-13-18--0400.xcresult` | Passed |
| Broader `CommandlyUIValidation` suite | 9/10: the legacy File Search smoke test could not obtain the launcher window on this Xcode/macOS combination; speculative compatibility changes were reverted | Known failure outside the focused wheel cases |
| Icon-only/application rapid-access visual check | No final human visual inspection was recorded | Pending |
| Hold/toggle/keyboard/submenu manual matrix | Not exercised on the physical keyboard/trackpad | Pending |
| Multi-display/Spaces/full-screen/focus matrix | No external display or mouse was available; Dock, Spaces, full-screen, and display arrangement were not changed | Not run; hardware/setup unavailable |
| VoiceOver/appearance matrix | VoiceOver and system appearance/accessibility settings were not changed on the validation Mac | Not run |
| Activation/selection performance | No Release physical-shortcut latency sample was captured; the required 30-warm-activation median/p95/maximum measurement remains outstanding | Not measured |
| Repeated-open leak/lifecycle review | No 100-cycle physical open/cancel Instruments Allocations/Leaks or memory-graph run was captured | Not measured |
| Shared-command and legacy-shortcut regression review | Shared execution/catalog behavior passed automated app tests. Manual ⌥Space, Shelf, registered-application hotkey, and legacy launcher checks remain pending; the broader UI result above retains the File Search failure | Partial automated pass; manual review pending |

Do not mark the feature complete until this record distinguishes automated passes from manual
passes, failures, skipped cases, and measurements that were not obtainable on the validation Mac.
