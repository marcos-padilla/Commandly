# Window Switcher

Window Switcher is an original Commandly foundation/prototype for finding, previewing, and
controlling individual macOS windows. It is **not a registered or usable production feature** in the
sandboxed Commandly app.

The earlier design incorrectly treated public API availability as App Sandbox compatibility.
Apple's
[App Sandbox guidance](https://developer.apple.com/documentation/security/protecting-user-data-with-app-sandbox)
lists use of Accessibility APIs in assistive apps and terminating other running apps as sandbox-
incompatible activities. Those behaviors are central to this switcher. Consequently, the production
runtime must remain unregistered and disabled while the App Sandbox is enabled. The contracts,
prototype adapters, presentation model, settings schema, UI, and deterministic tests are retained as
foundation work only; they do not establish signed-build functionality.

A future separately signed non-sandboxed companion/helper or a direct-distribution build with App
Sandbox disabled requires a new explicit architecture, threat-model, signing, update, and
distribution decision. Neither path is authorized today. See the rejected
[ADR-0008](decisions/ADR-0008-window-switcher-public-api-boundary.md).

The work remains clean-room and does not copy the supplied GPL-licensed reference application's
source, assets, icons, branding, text, tests, settings layout, or exact interface.

## Prototype interaction specification

The following describes intended behavior to evaluate only after a future privileged runtime is
authorized. It is not a set of instructions that works in the current sandboxed product.

### Launcher surface

1. Invoke the future **Window Switcher** surface.
2. Type to filter by application or window title when search is enabled.
3. Use the arrow keys to move, Return to activate the selection, and Escape to close or return.
   Optional Vim navigation adds H/J/K/L while search is not accepting text. Pointer selection is
   available only when enabled.
4. Use a card's visible controls or More/context menu for actions. Every operation uses a public
   Accessibility action and reports a typed unavailable/failure state if the target disappears,
   omits the required attribute/action, or rejects it.

The list is a per-presentation snapshot rather than a durable window history. A refresh can remove a
closed window, add a new one, or repair selection without retaining the previous title or thumbnail.
The prototype launcher definition models aliases and assigned application hotkeys through the same
Toggle Overlay presentation, but that definition must not be registered in the production registry.

### Option-Tab

The prototype models Option-Tab with an active Core Graphics event tap. That tap receives the
subscribed global key-event stream and filters unrelated events immediately; it does not observe
only the configured chord. The default **Hold to Cycle** mode follows a modifier gesture: keep
Option held, press Tab repeatedly to
move forward, use Shift-Tab to reverse, release Option to activate, or press Escape to cancel.
**Toggle Overlay** instead opens or dismisses the switcher and then uses the normal keyboard controls.
Launcher, menu, and assigned registered-application hotkeys always use Toggle Overlay because Carbon
invocation at that boundary has no matching modifier-release lifecycle.

Apple distinguishes a listen-only event tap, which cannot divert input, from an active filter that
may discard events; see
[`CGEventTapOptions`](https://developer.apple.com/documentation/coregraphics/cgeventtapoptions).
A sandbox-compatible listen-only alternative would still require
[Input Monitoring approval](https://support.apple.com/guide/mac-help/control-access-to-input-monitoring-on-mac-mchl4cedafb6/mac)
and could not suppress Option-Tab or replace Command-Tab. Support for active cross-application
suppression from the sandboxed production app has not been established, so the prototype tap must
not be installed there. Any future authorized runtime must remove the tap promptly on disablement or
permission revocation and must never store, log, or add raw events or key state to command history.

### Optional Command-Tab replacement

The prototype **Replace Command-Tab** setting defaults off. It models applying the selected Toggle
Overlay or Hold to Cycle behavior to Command-Tab through the same active event-tap boundary.
This is best effort: macOS, VoiceOver, secure-input state, another utility, or an event-tap failure
can prevent reliable interception. Commandly does not claim to replace every system Command-Tab path,
and it cannot be offered by the current sandboxed runtime.

### Optional Dock-hover previews

The prototype **Dock Previews** setting defaults off. Its adapter waits for the configured hover
delay and models inspecting the Dock's public Accessibility hierarchy to identify an application
item. Cross-application Dock Accessibility traversal must not run in the current sandboxed product.
The design does not patch or inject into the Dock, intercept Dock clicks, or read a private
Dock/WindowServer database.

The preview's **Pin** control keeps that Commandly panel open so the pointer can leave the Dock and
reach window actions; **Unpin** returns it to hover dismissal. Pinning a preview does not lock or move
the system Dock.

This surface is deliberately best effort. It can become unavailable when macOS changes the Dock's
Accessibility hierarchy and can vary with Dock orientation, auto-hide, magnification, restart state,
multiple displays, and third-party Dock replacements. Failure must disable only Dock-hover
presentation in any future authorized runtime. There is no currently supported Window Switcher
entry point.

## Window set, ordering, and display

The prototype can model all matching windows, only the active application's windows, or groups by
application. Its query can include or exclude minimized windows, hidden applications, and
applications with no concrete window. It can limit concrete windows to the current desktop and/or
current display, omit Commandly itself, and exclude explicit application names or window-title
fragments with case-insensitive matching, plus exact bundle identifiers.

Current-desktop membership is an adapter judgment over public window and Accessibility information,
not a complete Spaces database. Minimized, hidden, titleless, unusual, sandboxed, Electron, and
document-based applications can expose incomplete or stale Accessibility state. **Current Desktop
Only** therefore means best effort; it does not promise cross-Space discovery or exact parity with
Mission Control.

Because public APIs do not reveal Space membership for minimized or application-hidden windows,
those explicitly included states remain eligible for the active-desktop result instead of being
silently dropped. They may originate from a different Space.

Results may preserve the focused-first order supplied by the current adapter or sort by application
name or window title. This order is not claimed as a complete recent-use history. The presentation can use an
original Commandly grid, list, or horizontal strip with compact, regular, or large items. Titles,
application names, action controls, and thumbnails can be independently shown or hidden, while
accessibility labels continue to identify every result.

## Window actions

The prototype action vocabulary models Return restoring and focusing the selected window, plus close,
minimize/restore, native full-screen, native zoom, center, left/right/top/bottom-half placement, and
graceful application quit where the target supports them. Every request re-resolves the complete
process-scoped window identity before acting. A closed/replaced window, unsupported AX action,
sandbox/system restriction, or target failure is reported rather than treated as success.

In a future authorized switcher session, Command-W would request Close, Command-M would toggle
Minimize/Restore, Command-F would toggle full screen, Command-G would request native Zoom, Command-C
would center, and Command-Q would request graceful application quit. Command-1/2 would place the
window in the left/right half and Command-3/4 would use the top/bottom half. Every operation would
also remain available through the More/context menu. These shortcuts would be consumed only by the
active switcher session and not retained; Hold and Cycle would also require keeping its trigger
modifier held.

The prototype deliberately excludes moving a window to another Space, synthesizing private tile
groups, force-quitting an application, emptying Trash, or running a shell/AppleScript fallback. Quit
would affect the selected window's owning application and could expose unsaved-work risk, so it must
remain an explicit action in any future runtime.

## Settings contract

The prototype launcher definition declares a non-secret settings schema. The sandboxed production
app must not expose or persist it as an enabled application configuration. Defaults remain
conservative for future evaluation: Command-Tab replacement and Dock previews are off, results stay
on the current desktop, hidden/windowless applications are excluded, and title/icon presentation
does not depend on optional capture.

The prototype schema groups fields for the generic Applications inspector into Invocation, Window
Set, Interaction, Grid, List & Strip, Labels & Actions, Thumbnails & Live Preview, Placement, Dock
Previews, and Exclusions.

| Setting variable | Default | Allowed values / effect |
|------------------|---------|-------------------------|
| `shortcutMode` | `holdToCycle` | `holdToCycle` or `toggleOverlay` for Option-Tab and the optional Command-Tab path; launcher/menu/application-hotkey entry always toggles |
| `replaceCommandTab` | `false` | Attempts best-effort Command-Tab interception when enabled |
| `filterMode` | `allWindows` | `allWindows`, `activeApplication`, or `applications` |
| `sortOrder` | `recentlyUsed` | `recentlyUsed`, `applicationName`, or `windowTitle` |
| `currentDesktopOnly` | `true` | Best-effort public-API current-desktop filtering |
| `currentDisplayOnly` | `false` | Restricts concrete windows to the selected presentation display |
| `includeHiddenApplications` | `false` | Includes windows owned by hidden applications |
| `includeMinimizedWindows` | `true` | Includes minimized windows and allows activation to restore them |
| `includeWindowlessApplications` | `false` | Includes application placeholders that have no concrete window |
| `searchEnabled` | `true` | Enables local type-to-search over the active snapshot |
| `mouseSelectionEnabled` | `true` | Moves selection on pointer hover; clicking remains available when disabled |
| `vimNavigationEnabled` | `false` | Adds H/J/K/L navigation without replacing arrows while search is not accepting text |
| `layoutStyle` | `grid` | `grid`, `list`, or `strip` |
| `itemSize` | `regular` | `compact`, `regular`, or `large` |
| `gridColumnCount` | `4` | Grid column count from 2 through 8 in steps of 1 |
| `showWindowTitles` | `true` | Shows titles visually; titles remain in accessibility labels when needed for identity |
| `showApplicationNames` | `true` | Shows application names visually |
| `showWindowActions` | `true` | Shows supported per-window action controls |
| `showThumbnails` | `true` | Uses a thumbnail when Screen Recording is granted; otherwise shows metadata/icon fallback |
| `livePreviewsEnabled` | `true` | Refreshes visible thumbnails while presented, subject to bounds and cancellation |
| `thumbnailCacheLimit` | `48` | In-memory thumbnail limit from 0 through 200 in steps of 8; never a disk cache |
| `thumbnailQuality` | `balanced` | `efficient`, `balanced`, or `detailed` capture sizing/quality policy |
| `placement` | `activeDisplay` | `activeDisplay`, `pointerDisplay`, or `mainDisplay` |
| `horizontalOffset` | `0` | Horizontal panel offset from -600 through 600 points in steps of 10, clamped to a reachable display frame |
| `verticalOffset` | `0` | Vertical panel offset from -600 through 600 points in steps of 10, clamped to a reachable display frame |
| `dockPreviewsEnabled` | `false` | Enables best-effort public-AX Dock-hover previews |
| `dockPreviewDelay` | `0.35` | Hover delay from 0 through 3 seconds in steps of 0.05 |
| `exclusionTerms` | empty | Comma- or newline-separated application names, exact bundle identifiers, and window-title fragments excluded locally from enumeration |

Exclusion terms are explicit user-authored preferences, not titles harvested from active windows.
If a future runtime is authorized, users should enter generic non-secret fragments because declared
settings may persist. Permission-dependent settings must never trigger a hidden prompt; the UI must
explain the benefit and provide an explicit grant/recovery action.

## Permissions

### Accessibility — required by the prototype, unavailable as a production sandbox boundary

Cross-application Accessibility is required to enumerate and control other applications' windows
and traverse the Dock hierarchy. Apple lists assistive Accessibility use as incompatible with App
Sandbox, so sandboxed production Commandly must not request this grant on behalf of Window Switcher
or start those adapters. A future non-sandboxed runtime would need an explicit explanation and
recovery route at **System Settings → Privacy & Security → Accessibility**.

Any future runtime must stop enumeration and control, tear down observation, clear the active private
snapshot, and show a recovery state when trust is revoked. It must not repeatedly request trust or
fall back to AppleScript, shell execution, or private frameworks.

### Input Monitoring — required by a listen-only alternative

A passive global event listener would require Input Monitoring approval and could observe but not
divert events. It therefore cannot implement shortcut suppression or Command-Tab replacement. The
current sandboxed app does not request Input Monitoring for Window Switcher. An active event-filter
design belongs to the future privileged-runtime review.

### Screen Recording — optional

The prototype models Screen Recording only for thumbnails. The current sandboxed production app must
not request it for an unavailable Window Switcher workflow. In a future authorized runtime, denial
or revocation would replace thumbnails with metadata cards, cancel capture, and release the bounded
in-memory image cache. Recovery would be **System Settings → Privacy & Security → Screen & System
Audio Recording**.

Any future grant must never be reused for general screen recording, OCR, analytics, file export, or
AI input. Even when authorized, minimized/off-Space windows, protected content, a closing target, or failed
public window correlation can produce no image; those cards use the same metadata fallback.
A future initial capture pass must be bounded to the first 24 visible results. With Live Previews
enabled, only the current selection may refresh, at no more than roughly twice per second;
thumbnails must not become a screen-recording stream.

## Privacy and security

- The App Sandbox stays enabled, and the privileged prototype runtime stays unregistered and disabled.
- Any future window titles, thumbnails, application/window ordering, local search queries, pointer
  locations, hover state, and raw shortcut input must be ephemeral. They must never be logged,
  persisted, uploaded, exported, added to crash breadcrumbs, or placed in command history.
- If a future runtime is authorized, thumbnail bytes must remain in a bounded memory-only cache for
  the active presentation and be discarded on replacement, dismissal, disablement, or Screen
  Recording revocation.
- Prototype enumeration and capture make no network requests. A future runtime must not send window
  data to a configured AI provider.
- A complete `WindowID` contains adapter-defined identity plus process identifier. The control adapter
  re-resolves it immediately before an action and fails closed if the owner/window changed.
- Prototype settings must not be written by the disabled production runtime. The shared permission
  service may retain only content-free booleans recording an explicit Accessibility or Screen
  Recording request for active Commandly consumers. If a future runtime is authorized, no active
  title, captured image, ordering record, query, pointer trail, or AX element reference may enter
  preferences.

## Architecture

`Packages/Sources/Infrastructure/WindowSwitching.swift` owns content-free, Sendable contracts:

- `WindowID` and `WindowSnapshot` for process-scoped ephemeral identity and metadata;
- `WindowQueryOptions` for minimized/hidden/windowless, desktop/display, bundle, and title filters;
- `WindowAction` and typed `WindowServiceError` failures;
- `WindowQuerying` and `WindowControlling` boundaries;
- `InMemoryWindowService` for deterministic tests and previews.

Prototype app-target adapters use public `NSWorkspace`/`NSRunningApplication`, `AXUIElement`,
`CGWindowListCopyWindowInfo` for on-screen correlation, a scoped Core Graphics event tap, and
ScreenCaptureKit's window screenshot surface. `CGPreflightScreenCaptureAccess` checks thumbnail
availability without prompting and exposes an explicit `CGRequestScreenCaptureAccess` path for a
future authorized runtime; production gating must prevent that call today.
UI and state stay under the Window Switcher prototype. Production composition must not register the
launcher definition or start the app-lifetime shortcut/Dock coordinator while Commandly is
sandboxed. Package modules do not import the Commandly target or retain AppKit/AX/capture objects.

Prototype enumeration/capture work is asynchronous and cancellable where public APIs permit. A
presentation generation rejects stale query and thumbnail results, and cycling never waits for a
thumbnail. The off-by-default prototype Dock path uses bounded polling rather than retaining the
Dock AX tree. Any future notification-driven refresh must coalesce bursts. Dismissal, disablement,
target termination, grant revocation, and display/Space changes must release polling, tasks, images,
panel references, and event taps.

## Public-API and originality boundary

Commandly does not use or dynamically resolve `CoreDock`, `SkyLight`, `MediaRemote`, private Core
Graphics Services, undocumented Dock/Spaces notifications, private wallpaper sampling, or private
blur/material effects. It does not copy or translate the supplied GPL project's implementation or
presentation. Originality is a release requirement, not a cosmetic difference.

Public APIs cannot provide these parity claims:

- complete enumeration across every Space or moving a window to another Space;
- locking the system Dock to a display, intercepting Dock clicks, or guaranteed Dock-hover previews;
- universal replacement of all Command-Tab behavior;
- universal media metadata/controls, lyrics, calendar widgets, or application-private integrations;
- private WindowServer blur, wallpaper-derived materials, or undocumented animations;
- correct actions for applications that omit or reject required Accessibility attributes/actions.

## Verification

Automated tests use in-memory permission, window, action, thumbnail, keyboard input, mouse-click,
and settings adapters. `WindowSwitcherMouseMonitoring` keeps native local/global mouse monitors out
of coordinator tests; controlled callbacks cover inside/outside clicks, stale-session rejection,
and delivery stopping at dismissal and teardown. The native adapter also rejects queued events from
an earlier monitor generation.
They may validate filtering, identities, ordering/selection, action routing, state-machine teardown,
stale-result rejection, schema defaults/ranges, and metadata fallback without touching a real window
or permission prompt. Current package coverage includes query-option filtering, minimized/hidden/
windowless/desktop/display exclusions, process-scoped identity use, activation, minimize/close/quit
routing, and typed missing-window/query failures.

App-target coverage verifies prototype definition/documentation integration, the modeled
Accessibility requirement, all 28 defaults across nine generic Settings sections, selection parsing,
numeric clamping and declared bounds, exclusion normalization, backward-compatible configuration-
field decoding, presentation behavior with doubles, Screen Recording preflight/request-marker
transitions, and privacy-pane recovery routing. It does not prove that the definition is registered
in production, that the sandbox grants the required authority, or that a third-party application's
real Accessibility implementation accepts an action.

Real Accessibility trees, TCC prompts, event taps, captures, Dock hierarchy, Command-Tab suppression,
Spaces, full-screen windows, and display changes require a future authorized helper or non-sandboxed
distribution and the acceptance matrix in
[Testing](TESTING.md#window-switcher-future-runtime-matrix). Passing deterministic tests does not
prove those system behaviors. The matrix must not be reported against current sandboxed Commandly.
Future performance targets are in
[Performance](PERFORMANCE.md#window-switcher-prototype-performance-contract).
