# Menu Bar Shortcuts

`menu-bar.shortcuts` lets people search registered Commandly applications/tools and pin up to eight
as independent native status icons. Each icon opens an AppKit menu with Open, Manage Shortcuts, and
Remove. This is a real `NSStatusItem` integration; it does not merely add another fixed entry to
Commandly's dropdown. Holding Command while dragging lets macOS arrange icons, whose native autosave
names preserve their identities. macOS controls available menu-bar space and may hide crowded items.

The launcher manager uses arrow-key selection and Return to pin/remove, a visible pin count, pinned
items first, searchable titles/owning applications, labeled controls, selected-row semantics, and a
scrollable detail pane. Escape returns through shared launcher navigation. Pinning/removing updates
icons immediately and never invokes a tool. The usual tool review/permission flows run only after
the person selects Open. These are registered Commandly tools, not arbitrary executable paths or
foreign applications' custom status displays.

## Ownership and execution

`Services/MenuBarShortcuts` owns the preference policy, snapshot catalog, and observable controller.
`Scenes/StatusBar/NativeMenuBarShortcutPresenter` retains only the explicitly pinned AppKit items.
The registered application/model/view live under the launcher applications and commands folders.
AppRuntime assembles one retained controller, publishes the registry-backed catalog, and removes
owned native items on teardown. Constructors do not create icons or execute tools.

The controller revalidates pin membership and current enablement both when an action arrives and
when its task starts. Repeated in-flight actions for the same ID are coalesced. Runtime dispatches
the exact ID with `CommandInvocationSource.menuBar` through the existing shared command coordinator;
current catalog availability, tool-owned approval and permission checks remain authoritative.
Background-capable applications keep their background behavior; view applications use the ordinary
launcher presentation path. Teardown cancels pending tasks and removes status items.

Disabled/missing targets remain visible and removable, but their native Open menu is disabled.
Configuration changes refresh the catalog, and invocation rechecks it even if a native menu was
already open. Missing IDs are retained to avoid silently destroying preferences for a temporarily
unavailable capability. No external app is launched based on an untrusted path or label.

## Persistence and privacy

The only new preference is `menuBar.shortcuts.v1`: JSON command IDs bounded to eight unique strings,
256 UTF-8 bytes each and 8 KiB serialized. Empty/control-character IDs, duplicate lists, wrong stored
types, and malformed/oversized data fail closed. An unreadable list creates no icons and requires an
explicit Reset Saved Shortcuts action; it is never silently rewritten. Failed persistence leaves the
previous visible/saved list intact. Registered tool preferences, arguments, search text, clipboard
contents and private documents are not copied into this store. No permission, networking, account,
polling timer or third-party dependency is added. Hiding Commandly's main icon does not remove these
separately opted-in pins.

DEBUG productivity fixtures use an empty in-memory store and the real native presenter, so generated
acceptance choices cannot modify the person's saved pins. Unit tests inject a fake presenter and
never create real status items or execute a real tool. The 11 dedicated tests cover storage/privacy
bounds, failure preservation, missing/disabled items, stale actions, duplicate invocation, recovery,
limits/teardown, keyboard selection, and registry identity. Shared execution tests also cover
menu-bar availability rejection and durable source metadata. Native generated manager search/Return pin and remove passed with correct counts. Direct status-item
Open/Manage/Remove interaction remains separate acceptance because the native control surface did not
expose that menu. `make verify` passed in
`/tmp/commandly-video-verify-tranche10-menubar-retry.log`, including all eleven dedicated cases and
the updated shared execution/history tests.

## Native API references

- [NSStatusItem](https://developer.apple.com/documentation/appkit/nsstatusitem)
- [NSStatusBar](https://developer.apple.com/documentation/appkit/nsstatusbar)
- [NSStatusItem autosaveName](https://developer.apple.com/documentation/appkit/nsstatusitem/autosavename-swift.property)
- Installed macOS 27 AppKit headers `NSStatusItem.h`, `NSStatusBar.h`, `NSStatusBarButton.h`.

This feature provides chosen command shortcuts. Live third-party status data and extension-provided
menu-bar interfaces remain separate portions of the broader extension/integration requirements.

## Catalog cost

The actual built-in catalog test now records a Swift Testing attachment so its measurement survives
Xcode test-console filtering. The targeted Debug run on September 14, 2026 measured construction and
sorting of 103 registered tools at 0.0010395 seconds (about 1.04 ms). This is one local sample, not a
release benchmark or a launch-time guarantee. Registry construction is outside the measured interval.
Evidence: `/tmp/commandly-menubar-timing-acceptance.log` and
`/tmp/commandly-menubar-timing-attachments/DED725F3-1C4E-4138-90FC-0667211A23D9.txt`.
