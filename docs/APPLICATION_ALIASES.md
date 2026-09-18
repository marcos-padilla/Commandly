# Installed application aliases

Installed macOS applications support one optional search nickname per bundle identifier. Select an
application in the launcher, open Actions with Command-K, and choose Set Alias or Edit Alias. The
editor focuses the nickname field; Return saves a valid change and Escape cancels the draft. Saving
or cancelling returns keyboard focus to launcher search. Clearing the field removes an existing
alias. The canonical application name and identity stay visible and remain searchable.

Aliases collapse repeated whitespace, preserve Unicode, and accept up to 64 characters. Empty input
removes an alias. Control characters and an alias already assigned to another application are
rejected with inline feedback. Duplicate checks ignore case and diacritics. An exact alias match
ranks above an incidental application-name match, including favorite and usage boosts; partial
aliases remain searchable. Aliases do not change the existing disabled-application behavior:
disabled applications stay absent from an empty search and can be found by an explicit query for
management.

`ApplicationAlias` owns normalization, validation, and alias scoring.
`ApplicationAliasEditorModel` owns the draft and saves through `ApplicationPreferencesStoring`.
The editor reloads preferences at save time to preserve unrelated favorites, ranking, and disable
changes. The `apps.aliases` UserDefaults dictionary is keyed by bundle identifier; older preference
stores without that key load with no aliases. Removing an application through Commandly clears its
alias with the other installed-application preferences.

This feature adds no permission request, network access, telemetry, or automatic application
execution. Nicknames stay in local application preferences and are never logged. The editor exposes
explicit field and button labels, validation feedback, default/cancel keyboard actions, and uses
the existing Commandly typography and semantic colors. Registered launcher applications and tools
continue using their Settings discovery tags for alternate search names, as described in
[Launcher applications](LAUNCHER_APPLICATIONS.md).

`ApplicationAliasTests` covers normalization, duplicate and invalid inputs, canonical-name and
nickname discovery, exact-match ranking, disabled results, persistence compatibility, draft
cancellation, preserving concurrent preference changes, removal, and the launcher action/save/
Escape integration. UI focus and VoiceOver behavior require a native runtime check in addition to
these tests; source review alone does not verify them.
