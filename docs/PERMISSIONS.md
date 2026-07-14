# Permissions

Commandly uses the App Sandbox. Permissions are requested only after explicit user intent (for example, an onboarding **Grant Access** button). Continue remains available if the user skips.

## Active permissions

| Permission | Feature benefit | Prompt timing | Recovery |
|------------|-----------------|---------------|----------|
| Calendar | Reserved for a future schedule application; Commandly does not currently surface calendar events | Onboarding Grant Access (optional) | System Settings → Privacy & Security → Calendars |
| Contacts | Reserved for a future people application; Commandly does not currently surface contacts | Onboarding Grant Access (optional) | System Settings → Privacy & Security → Contacts |
| Files and Folders | Search, preview, open, copy, move, duplicate, create shortcuts for, or trash files inside folders the user selects; temporarily stage explicitly dropped/pasted file URLs in Shelf; list and open recent files from Downloads read-only | Onboarding Grant Access or Settings Manage Folders shows a folder picker; versioned security-scoped bookmarks are stored. Shelf receives temporary access when the user explicitly drops or pastes a file URL and does not store a bookmark. Recent Downloads uses a narrow read-only Downloads entitlement and does not mutate files. | Re-run Settings → Permissions → Manage Folders, re-drop the item into Shelf, or use System Settings → Files and Folders |
| Accessibility | Window layouts and deeper keyboard automation | Onboarding Grant Access (system trust prompt) | System Settings → Privacy & Security → Accessibility |
| Open at Login | Launch Commandly at sign-in | Setup toggle during onboarding | System Settings → General → Login Items |
| Clipboard History | Browse and re-copy recent pasteboard items from the launcher; on-device Vision/PDFKit indexes images and readable files for search | Activating the Clipboard History command (no TCC prompt for pasteboard monitoring or on-device analysis) | Clear history from the command Actions menu |
| Automation (Finder) | Show an Info window from File Search or an installed application's actions panel | First use of **Show Info in Finder** in either workflow | System Settings → Privacy & Security → Automation → Commandly → Finder |

## Entitlements and usage strings

- Sandbox remains enabled.
- `com.apple.security.files.user-selected.read-write` for folder picks so explicit file actions can modify selected locations.
- `com.apple.security.files.bookmarks.app-scope` for restoring selected-folder access after relaunch.
- `com.apple.security.files.downloads.read-only` for listing, opening, revealing, or copying the URL
  of a recent download. The application cannot modify Downloads through this entitlement.
- `com.apple.security.personal-information.calendars`
- `com.apple.security.personal-information.addressbook`
- `com.apple.security.automation.apple-events` plus a Finder temporary exception for Get Info
- Temporary home-relative and absolute path read-write exceptions for application uninstall discovery/trash (`~/Library`, `/Applications`, `/Library`)
- Info.plist includes `NSCalendarsFullAccessUsageDescription`, `NSCalendarsUsageDescription`, `NSContactsUsageDescription`, and `NSAppleEventsUsageDescription`.

## Not requested yet

Screen Recording, Notifications, Camera, Microphone, and Location remain unimplemented. Clipboard history is opt-in and does not use a TCC prompt, but content must never be logged. Capture-time OCR and file-text extraction stay on-device; sandbox may prevent reading some pasted file URLs (those entries remain filename-searchable only). Application uninstall discovers related files under the **real** user `~/Library` (not the sandbox container home) plus `/Applications`, using temporary file-access exceptions. The review list matches the app bundle ID and helper prefixes (e.g. `com.example.app.helper.plist`). Protected or sandboxed paths may still fail; Commandly reports partial failures instead of claiming a complete wipe.

## Native features without a new permission

- Calculation History and Timers & Focus retain only in-process session state.
- Shelf holds explicitly dropped or pasted file/folder URL references only while its board is open.
  An explicit clipboard import may instead materialize text or image data beneath a per-board
  directory in Commandly's temporary container; those private files are deleted when removed and the
  directory is deleted when the board closes or is replaced. Native pasteboard reads, active-display
  geometry, and Shelf's fixed Carbon shortcuts do not add a TCC, Screen Recording, or Accessibility
  prompt. Shelf does not add an account or background folder access. A receiving native share service
  may require its own sign-in or transfer approval.
- Productivity Library persists private user-authored items locally in Commandly's Application
  Support container and never logs their contents.
- System Activity reads aggregate host statistics and the regular GUI application list through public
  macOS APIs. Quit and force-quit occur only after explicit actions; force quit and quit-all require
  confirmation.
- Emoji Search, text-case conversion, color conversion/sampling, Dictionary, installed-font search,
  and Typing Practice use local macOS frameworks or bundled data and do not call a network service.
- Custom window-layout geometry is a non-secret preference. Applying a layout still follows the
  Accessibility flow above.

## Login items

Open at Login uses `SMAppService.mainApp` and is only registered after the user enables it in onboarding (or a future Settings control). It is not a TCC permission, but macOS may still require approval under **System Settings → General → Login Items**. Denial or pending approval must leave the app usable; the preference is persisted and the UI explains how to recover.

## Policy for all permissions

1. Document user benefit before enabling.
2. Request only when the user activates the control.
3. Explain why before the system prompt when possible.
4. Handle denial gracefully; never block onboarding completion.
5. Provide Settings recovery instructions.
6. Keep scope minimal.
7. Cover behavior with mocked tests — never require real grants in CI.
