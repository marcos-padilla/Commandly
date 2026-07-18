# Command Wheel

Command Wheel is Commandly's cursor-centered way to run commands you already know. Search remains
the best way to discover a command; the wheel gives frequently used commands a stable direction so
they become fast with muscle memory.

Wheel entries store only references to Commandly commands. Selecting a segment uses the same
resolver, availability checks, executor, result handling, and privacy-safe usage history as the
launcher search interface.

## Enable and configure the wheel

1. Open **Settings → Command Wheel**.
2. Turn on **Enable Command Wheel**.
3. Select the Default profile, choose **Record Shortcut**, and press the desired modified key.
4. Resolve any shortcut conflict shown beside the recorder.
5. Use the live preview to arrange commands and tune interaction settings.

Commandly initially creates one conservative profile containing File Search, Clipboard History,
and Open Settings. The feature begins disabled and without an assigned shortcut so installing an
update cannot take over a key combination unexpectedly.

## Hold, flick, and release

With **Hold and release** selected:

1. Hold the profile's global shortcut and begin moving toward the intended direction immediately.
2. When preparation completes, the wheel appears around the pointer. Its outline and icon state show
   the current selection; opening animation never delays hit testing.
3. Release the shortcut to run the selected command. If release arrives while content is still
   preparing, Commandly retains that final pointer location and evaluates it as soon as preparation
   completes without briefly presenting a stale wheel.
4. Release in the center dead zone, over an empty slot, or before selecting to cancel.

Commandly takes a final pointer sample on key-up. A quick flick therefore resolves from the actual
release position even when macOS coalesces intermediate pointer movement. Angular hysteresis keeps
the highlight stable near the boundary between adjacent segments.

## Toggle and click mode

Choose **Toggle** for an alternative that does not require holding a key:

1. Press the shortcut once to open the wheel.
2. Hover a segment and click it, or navigate with the keyboard and press Return.
3. Click the center, click outside the panel, press Escape, or press the shortcut again to cancel.

Enable **Click selection** for pointer activation. Toggle mode is also the recommended mode for
keyboard-only use because the panel can take the smallest temporary focus transition needed for
normal key events, then return focus when it closes.

## Keyboard operation

When keyboard selection is enabled:

- **Tab** or **Right Arrow** moves clockwise through available segments.
- **Shift-Tab** or **Left Arrow** moves counter-clockwise.
- **Up Arrow** and **Down Arrow** move through the same stable radial order.
- **1–9** selects the corresponding visible slot when present.
- **Return** executes a command or opens the selected submenu.
- **Escape** returns from a submenu; at the root it cancels the wheel.

Empty and hidden segments are skipped. Keyboard focus is released when the wheel closes, and
Commandly never installs a permanent focus-stealing window.

## Submenus

A submenu segment opens one child page in place of the current page. Profiles form a rooted tree:
pages cannot form cycles, have multiple parents, or become unreachable from the root.

The profile can use one of four activation behaviors:

- **Continue outward** opens the child after the pointer crosses the submenu radius.
- **Dwell** opens it after the configured hover duration.
- **Click only** waits for an explicit click or Return.
- **Disabled** displays submenu entries without allowing entry.

Move into the center back state or press Escape to return to the parent. Commandly displays one
full-size wheel at a time.

## Profiles and application context

Each profile owns a shortcut, activation behavior, placement, appearance, interaction settings,
context rules, and a tree of pages. Settings supports creating, renaming, duplicating, reordering,
enabling, exporting, importing, and deleting profiles. Deleting the final usable default is not
allowed; choose or create a replacement first.

An enabled application-context rule compares the frontmost application's exact bundle identifier.
Rules are resolved once per invocation, without continuous polling. Resolution order is:

1. An explicitly addressed profile, unless that shortcut permits context override.
2. The matching enabled context rule with the highest numeric priority.
3. Profile order, then rule order, as deterministic tie-breaks.
4. The enabled default profile.

Settings flags conflicting rules that match the same bundle identifier at the same priority.
Commandly does not include hard-coded rules for third-party applications.

While a wheel is presented, activation of a process other than the captured frontmost application
cancels the session so a stale context cannot execute. Toggle mode exempts Commandly's own temporary
activation. This is notification-driven invalidation, not continuous polling.

## Arrange wheel content

Select a page and slot in the visual editor, then choose one of:

- **Command** searches registered commands and installed applications through the same shared
  providers used by launcher search. Application rows keep their display name for the segment and
  persist the exact typed bundle-identifier reference.
- **Submenu** creates or links a child page.
- **Recent commands** freezes a bounded list from shared successful-command history for the
  invocation.
- **Frequent commands** freezes a bounded usage-ranked list from the same history.
- **Empty** preserves the direction without making it executable.

Recent and Frequent resolve again on every invocation and remain frozen while visible. Because the
privacy-safe history excludes command arguments, entries that require non-defaulted input—such as a
specific installed-app bundle identifier—are skipped before the configured result limit is applied.
Each provider scans at most the top 96 ranked history candidates, and repeated references across
pages share one resolution outcome for that invocation, so large histories cannot create unbounded
activation work.

The editor provides buttons and menus for every drag operation. Reordering never requires a mouse.
If a command is removed, disabled, or no longer accepts saved arguments, the editor keeps the
reference and marks it unavailable rather than silently substituting or deleting it.

### Add from search

Right-click a registered command or installed-application result and choose **Add to Command
Wheel…**. Choose the profile, page, and slot. Occupied slots show their current content and require
an explicit replacement. The same assignment panel can move or remove an existing reference,
create a child page, or reveal the profile in Settings.

Installed applications use Commandly's shared parameterized Open Application command. Search and
Command Wheel therefore pass the same bundle-identifier argument through the same executor.

## Placement and displays

Profiles can open at the pointer, at the active display center, or at a saved normalized position.
Commandly chooses the display containing the pointer first and supports negative global display
coordinates. It clamps the wheel's actual center to the display's usable frame without shrinking
segments; hit testing always uses that final center.

Display geometry is captured once for an invocation. If macOS reports any display-geometry change
while the wheel is open—including a display disconnect, arrangement change, scale change, menu-bar
move, or Dock/usable-frame change—the session cancels without executing the previous highlight.
Invoke it again after the new geometry settles.

## Import and export

Use the profile actions in Settings to export one or more profiles as versioned, human-readable
JSON. Exports contain layout preferences and non-secret serialized command references only; they
never include usage history, clipboard data, file contents, credentials, or runtime context.

Imports are validated before saving. Existing profiles are never silently overwritten. Commandly
generates new profile, page, segment, and rule identifiers when imported identifiers collide, and
reports command identifiers that are not present in the current catalog.

## Accessibility and appearance

Command Wheel follows the current light or dark appearance, shared Commandly text sizing, Reduce
Motion, Reduce Transparency, and Increased Contrast. With Reduce Motion, scale and directional
transitions become restrained opacity changes without changing selection timing.

The radial surface is intentionally icon-only, including installed applications, so long command
or application names cannot collide around the ring. Installed-app references resolve their native
macOS application icon from the saved bundle identifier and fall back to the shared app symbol when
the bundle is unavailable. Full names and state explanations remain in Settings and accessibility
semantics; a custom slot label changes those semantics without adding visible wheel text.

VoiceOver exposes each actionable segment as one element with its full title, position, selection,
submenu, and availability state. Decorative wedge shapes are hidden. The center cancel/back target
has its own description. Stable accessibility identifiers support automated UI validation.

## Permissions and privacy

The default global shortcut uses the public Carbon hot-key API, and pointer tracking samples the
current mouse location only while a wheel is active. These mechanisms do **not** require
Accessibility permission. Toggle-mode keyboard input is delivered through the temporary panel,
not a global key logger.

The command selected from a wheel can have its own existing permission requirement. For example,
Window Layouts needs Accessibility access to inspect or move another application's windows. In
that case Commandly preserves the command's normal explanation, denial handling, and Settings
recovery route; Command Wheel never prompts for a permission independently.

Commandly stores non-secret profile JSON and a bounded privacy-safe history containing command ID,
invocation source, outcome, and timestamp. It does not store pointer paths, frontmost window titles,
queries, command arguments in history, clipboard values, file contents, credentials, or full
application activity. See [Permissions](PERMISSIONS.md) and [Security Model](SECURITY_MODEL.md).

## Troubleshooting

### The shortcut does nothing

- Confirm the feature and profile are enabled.
- Check the shortcut recorder for a conflict with the launcher, Shelf, another profile, or a
  shortcut macOS refused to register.
- Record a different modified shortcut and retry. Changes apply while Commandly is running.

### Releasing does not execute

The center dead zone, neutral ring, empty slots, unavailable commands, and a release received after
the shortcut was changed all cancel safely. Move far enough in the intended direction; a fast
release received during preparation is still evaluated from its final pointer location, so a visible
outline is not required. Toggle mode and Return can help validate the assignment.

### A segment says unavailable

Open the slot in Settings to see the saved command ID and argument validation. Re-enable the owning
Commandly application, restore its required permission, replace the assignment, or leave the
reference in place for a command that may return after import or reinstall.

### The wheel is not on the expected display

Pointer placement follows the display containing the pointer. Fixed placement falls back to the
active display when its saved screen identifier is no longer connected. Re-save the normalized
position with the desired display connected.

### A command failed

The wheel detaches input and begins dismissal before asynchronous execution. With animation enabled,
the panel may finish its brief fade while command work proceeds. Commandly then uses the launcher's
existing result/status surface and the command's sanitized error message. Open the command from
search to review the same availability and permission behavior.
