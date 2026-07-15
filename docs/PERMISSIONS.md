# Permissions

Commandly uses the App Sandbox. Permissions are requested only after explicit user intent (for example, an onboarding **Grant Access** button). Continue remains available if the user skips.

## Active permissions

| Permission | Feature benefit | Prompt timing | Recovery |
|------------|-----------------|---------------|----------|
| Calendar | Reserved for a future schedule application; Commandly does not currently surface calendar events | Onboarding Grant Access (optional) | System Settings → Privacy & Security → Calendars |
| Contacts | Reserved for a future people application; Commandly does not currently surface contacts | Onboarding Grant Access (optional) | System Settings → Privacy & Security → Contacts |
| Files and Folders | Search, preview, open, copy, move, duplicate, create shortcuts for, or trash files inside folders the user selects; let Finder AI query eligible selected scopes and propose confirmed operations; temporarily stage explicitly dropped/pasted file URLs in Shelf; list and open recent files from Downloads read-only | Onboarding Grant Access or Settings Manage Folders shows a multi-folder picker and asks for specific folders. Versioned security-scoped bookmarks are stored. Finder AI excludes Home, folders above Home, and whole-volume roots even if general File Search can use such a bookmark; select narrower folders for Finder AI. It receives no authority until the user submits a request and never inherits Downloads, uninstall, or Automation access. Shelf receives temporary access when the user explicitly drops or pastes a file URL and does not store a bookmark. Recent Downloads uses a narrow read-only Downloads entitlement and does not mutate files. | Re-run Settings → Permissions → Manage Folders and select one or more specific folders, re-drop the item into Shelf, or use System Settings → Files and Folders |
| Accessibility | Window layouts and deeper keyboard automation | Onboarding Grant Access (system trust prompt) | System Settings → Privacy & Security → Accessibility |
| Open at Login | Launch Commandly at sign-in | Setup toggle during onboarding | System Settings → General → Login Items |
| Clipboard History | Browse and re-copy recent pasteboard items from the launcher; on-device Vision/PDFKit indexes images and readable files for search | Activating the Clipboard History command (no TCC prompt for pasteboard monitoring or on-device analysis) | Clear history from the command Actions menu |
| Automation (Finder) | Show an Info window from File Search or an installed application's actions panel | First use of **Show Info in Finder** in either workflow | System Settings → Privacy & Security → Automation → Commandly → Finder |

## Entitlements and usage strings

- Sandbox remains enabled.
- `com.apple.security.network.client` permits outbound connections for explicit AI provider
  validation, model discovery, and submitted prompts. It does not create a macOS TCC prompt.
- `com.apple.security.files.user-selected.read-write` for folder picks so explicit file actions can modify selected locations.
- `com.apple.security.files.bookmarks.app-scope` for restoring selected-folder access after relaunch.
- `com.apple.security.files.downloads.read-only` for listing, opening, revealing, or copying the URL
  of a recent download. The application cannot modify Downloads through this entitlement.
- `com.apple.security.personal-information.calendars`
- `com.apple.security.personal-information.addressbook`
- `com.apple.security.automation.apple-events` plus a Finder temporary exception for Get Info
- Temporary home-relative and absolute path read-write exceptions for application uninstall discovery/trash (`~/Library`, `/Applications`, `/Library`)
- Info.plist includes `NSCalendarsFullAccessUsageDescription`, `NSCalendarsUsageDescription`, `NSContactsUsageDescription`, and `NSAppleEventsUsageDescription`.
- `NSAppTransportSecurity` sets `NSAllowsLocalNetworking` so the reviewed Ollama adapter can reach
  an explicitly configured loopback address. It is not a blanket cleartext-network exception:
  arbitrary remote HTTP endpoints remain rejected.

## AI network access (no new TCC permission)

The network-client sandbox entitlement and local-network ATS setting are capabilities, not consent
prompts. Opening Commandly, Settings, or Finder AI sends no inference request. Traffic begins only
when the user validates a provider connection or submits a prompt. Official cloud adapters use fixed
HTTPS hosts. Local Ollama is restricted to `localhost`, `127.0.0.1`, or `::1` and Commandly never
downloads a model automatically.

With a cloud provider active, the prompt and bounded Finder tool metadata/results can leave the Mac
under that provider's account and terms. File content requires a separate exact approval. Absolute
paths, security-scoped bookmarks, and unapproved contents are not sent. Network failure, provider
outage, quota, billing, or model removal must leave non-AI features usable.

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
- AI provider networking uses the entitlement/ATS boundary described above and has no separate TCC
  prompt. Finder AI remains constrained to existing user-selected folder grants; its opaque handles
  and local approvals do not broaden those grants. Finder Automation is not used as a general AI
  control surface.

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
