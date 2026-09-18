# Installed application shortcuts

An installed application can have a global shortcut independently of its favorite status. Select
the application in launcher search, open Actions (`⌘K`), and choose **Set Global Shortcut**. Recording
only changes a draft; **Save Shortcut** registers and persists it. The same action later allows
editing or removing the assignment. Search uses the original application identity and any alias.

Use Command, Option, or Control with a supported hardware key; Shift may be added. Plain keys and
Shift-only combinations are rejected so normal typing is not captured. These are ordinary Carbon
shortcuts, not Hyper remapping, single-key interception, or double-tap triggers. Those video
requirements remain separate work.

## Ownership and behavior

`Services/InstalledApplicationShortcuts.swift` validates assignments, derives bounded active bindings,
and merges each explicit save into `ApplicationPreferencesStoring`. The preferences add a separate
`apps.hotKeys` Codable dictionary; existing favorites, aliases, ranking, disabled state, and auto-quit
settings remain intact. At most 128 installed application shortcuts are retained. Malformed persisted
keys, unknown modifier bits, invalid identities and oversized data are ignored when loading.

The app-lifetime `RuntimeGlobalShortcutCatalog` and `GlobalShortcutMonitor` own every actual
registration. Installed apps follow launcher, registered applications/tools, and Command Wheel
shortcuts. Previously successful installed-app owners precede newly enabled assignments, preventing
an enabled app from silently taking another installed app's key. On fresh launch, installed bindings
start in deterministic bundle-ID order. Conflicts are reported in the editor; a failed explicit save
restores the previous preference and registrations synchronously. The application can still launch
normally when its shortcut is unavailable.

While this editor records, Commandly temporarily removes its own global registrations so an existing
shortcut can be captured without launching something. Escape, completion, cancellation, losing app
focus, or dismissing the sheet restores registration. Saving is unavailable during recording. The
key recorder observes only Commandly's local key-down events; other applications' registered global
shortcuts may still consume a key before it reaches the editor.

Disabling an app removes its active registration while retaining its assignment. Re-enabling it
checks conflicts and shows any issue. Removing an app through Commandly's uninstall flow removes its
shortcut preference. An app removed elsewhere returns a recoverable launch error. **Manage Other App
Shortcuts** inside any application's shortcut editor lists every other saved assignment, including
missing applications using their bundle identifiers. Remove releases that shortcut immediately while
preserving the current editor's draft, so stale assignments never require reinstalling an app to clear.

Pressed events invoke the existing typed installed-app command through the shared coordinator,
including availability checks, bundle-identity execution and successful-open ranking/history.
Repeated presses are coalesced by the monitor, and simultaneous in-flight opens of the same app are
deduplicated. Release/cancel events do not launch. Stale registration generations cannot invoke a
replacement. Application shutdown cancels retained background tasks and unregisters the monitor.

## Privacy and accessibility

This feature requests no permissions, reads no typed content from other applications, and introduces
no network, key logging, shell commands, or secret storage. Only bundle IDs and hardware key/modifier
values persist. No application path is used as an executable shell argument.

The editor reuses native buttons and the existing keyboard recorder, has an explicit heading and
application-specific accessibility labels, supports Cancel/Save keyboard actions, and restores root
search focus when closed. Commandly text styles and semantic colors supply appearance/scaling;
native focus, VoiceOver, real cross-application hotkey activation, and conflict recovery require live
acceptance on the built app.

## Verification

`InstalledApplicationShortcutTests` covers migration/round-trip sanitation, disabled ownership,
duplicate rejection, rollback preserving unrelated preferences, removal, modifier/count bounds,
stable owner priority, launcher/command/wheel conflicts, and editor recording/cancel/save behavior.
The existing `GlobalShortcutMonitorTests` cover repeat coalescing, stale callback generations,
replacement cancellation and idempotent teardown. Shared command tests cover typed installed-app
execution, availability and ranking. These tests do not register actual system shortcuts or launch
user applications. Run `make verify`; passing mock-backed tests does not establish native activation.
