# Permissions

Commandly uses the App Sandbox. Permissions are requested only after explicit user intent (for example, an onboarding **Grant Access** button). Continue remains available if the user skips.

## Active permissions

| Permission | Feature benefit | Prompt timing | Recovery |
|------------|-----------------|---------------|----------|
| Calendar | My Schedule reads an agenda and meeting links; explicitly armed occurrences can open their reviewed meeting link at the scheduled time | Grant Calendar Access in My Schedule, optional onboarding, or Settings; never automatically at launch | System Settings → Privacy & Security → Calendars |
| Contacts | Reserved for a future people application; Commandly does not currently surface contacts | Onboarding Grant Access (optional) | System Settings → Privacy & Security → Contacts |
| Camera | Check your appearance in Camera Preview and explicitly capture a photo to copy or save | Only an explicit Start Camera or camera Grant Access action after the feature explains its use; opening Commandly, the registry, Settings, or the preview surface never prompts or starts capture | System Settings → Privacy & Security → Camera → enable Commandly, then return to Camera Preview and start again. Restricted access may require the device administrator. |
| Microphone | Dictation transcribes explicitly started microphone input on this Mac | Only Start Dictation requests access; launch, Settings, language choice, and history never prompt or start capture | System Settings → Privacy & Security → Microphone; reconnect/select the input and retry. Restricted access may need the device administrator. |
| Files and Folders | Search from the launcher root or full File Search application; preview, open, copy, move, duplicate, create shortcuts for, or trash files inside folders the user selects; find exact duplicates inside one explicitly selected ephemeral Storage Cleaner folder; let Finder AI query eligible selected scopes and propose confirmed operations; temporarily stage explicitly dropped/pasted file URLs in Shelf; list and open recent files from Downloads read-only | Onboarding Grant Access or Settings Manage Folders shows a multi-folder picker and asks for specific folders. Versioned security-scoped bookmarks are stored for File Search; an inline root query uses only that same scope and index. Storage Cleaner instead shows its own native picker when Find Exact Duplicates is activated and does not persist that folder grant. Finder AI excludes Home, folders above Home, and whole-volume roots even if general File Search can use such a bookmark; select narrower folders for Finder AI. It receives no authority until the user submits a request and never inherits Downloads, uninstall/cleanup exceptions, or Automation access. Shelf receives temporary access when the user explicitly drops or pastes a file URL and does not store a bookmark. Recent Downloads uses a narrow read-only Downloads entitlement and does not mutate files. | Re-run Settings → Permissions → Manage Folders for persistent File Search scopes, choose the duplicate folder again in Storage Cleaner, re-drop the Shelf item, or use System Settings → Files and Folders |
| Accessibility | Apply Window Layouts; when Highlight Mode is active, observe global clicks and keyboard input for ephemeral on-screen feedback; move the pointer one point on an interval when Keep Awake's **Move pointer slightly** option is on; re-post volume-key presses as macOS' fine step when the mixer's **Use finer volume steps** option is on. Command Wheel itself does not use this grant. The disabled Window Switcher prototype is not an active permission consumer. | Onboarding/Settings Grant Access, the first explicit Turn Highlight Mode On action, or the Keep Awake **Grant Accessibility Access** button; process launch never prompts, and both menu bar panel options are off by default | System Settings → Privacy & Security → Accessibility |
| Audio Recording | Per-app volume and per-app output routing in the menu bar panel's Volume Mixer. A muted CoreAudio process tap removes one app's sound from its output and a private aggregate device replays it at the chosen gain; samples are re-rendered in memory and never written, stored, or sent anywhere. | Only when the user moves an app's slider or chooses an output for it, which is the first moment a tap is created. Opening the panel, reading device names, or changing the system volume never creates a tap. | System Settings → Privacy & Security → Microphone → enable Commandly, then reopen the Volume Mixer |
| Open at Login | Launch Commandly at sign-in | Setup toggle during onboarding | System Settings → General → Login Items |
| Clipboard History | Find and re-copy recent pasteboard items inline from the launcher root or browse the full history application; on-device Vision/PDFKit indexes images and readable files for search | No TCC prompt; app-runtime monitoring supplies the shared capture store used by both surfaces | Clear history from the command Actions menu |
| Automation (Finder) | Show an Info window from File Search or an installed application's actions panel; explicitly copy the selected Finder item or current folder path; empty the Trash from the menu bar panel's Quick Toggles | First use of **Show Info in Finder**, **Allow Finder Access and Copy** after Finder Path explains the read, or the confirmed **Empty** button in Quick Toggles; opening Finder Path or the panel never prompts | System Settings → Privacy & Security → Automation → Commandly → Finder |
| Automation (System Events) | Switch the whole Mac between light and dark mode from Quick Toggles. macOS exposes this setting to no other interface. | Only the first time the user taps **Switch to light mode** / **Switch to dark mode**; reading the current appearance uses global preferences and never prompts | System Settings → Privacy & Security → Automation → Commandly → System Events |

Commandly stores one non-secret boolean after Accessibility or Screen Recording has been explicitly
requested so a later failed preflight can show **Open Settings** instead of repeatedly presenting
**Grant Access**. These markers contain no window, input, title, image, file, or permission payload.

## Entitlements and usage strings

- Sandbox remains enabled.
- `com.apple.security.network.client` permits outbound connections for explicit AI provider
  validation, model discovery, and submitted prompts, plus the Logos application's public SVGL
  catalog and SVG asset requests. It does not create a macOS TCC prompt.
- `com.apple.security.files.user-selected.read-write` for folder picks so explicit file actions can
  modify selected locations and Storage Cleaner can scan and Trash confirmed duplicates inside its
  one ephemeral user-selected folder.
- `com.apple.security.files.bookmarks.app-scope` for restoring selected-folder access after relaunch.
- `com.apple.security.files.downloads.read-only` for listing, opening, revealing, or copying the URL
  of a recent download. The application cannot modify Downloads through this entitlement.
- `com.apple.security.application-groups` for the signed host and Markdown Quick Look extension to
  share only declared non-secret renderer settings.
- `com.apple.security.personal-information.calendars`
- `com.apple.security.personal-information.addressbook`
- `com.apple.security.device.camera` permits video input only after contextual camera authorization.
- `com.apple.security.device.microphone` (App Sandbox) and `com.apple.security.device.audio-input`
  (Hardened Runtime) permit Dictation input only after explicit Start and contextual authorization,
  and the Volume Mixer's CoreAudio process taps only after the user adjusts an app.
  `NSMicrophoneUsageDescription` explains that recognition happens on this Mac and that the mixer
  re-renders a tapped app's audio without recording it.
- `com.apple.security.automation.apple-events` plus temporary exceptions for `com.apple.finder` (Get Info, explicit Finder Path reads, and the confirmed Empty the Trash action) and `com.apple.systemevents` (the light/dark appearance switch only). Each is one fixed Apple Event built from published event codes; Commandly sends no script text and no caller-supplied codes.
- Temporary home-relative and absolute path read-write exceptions for application uninstall and
  review-first Storage Cleaner discovery/Trash (`~/Library`, `/Applications`, `/Library`)
- Info.plist includes `NSCalendarsFullAccessUsageDescription`, `NSCalendarsUsageDescription`, `NSContactsUsageDescription`, `NSCameraUsageDescription`, and `NSAppleEventsUsageDescription`.
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

## Logos network access (no new TCC permission)

Opening Logos requests the public catalog from `api.svgl.app`; visible previews and explicit copy or
download actions may request SVG files from `svgl.app`. The catalog is cached for ten minutes and
searching, category filtering, and favorites remain local. Favorites store only numeric catalog IDs
in UserDefaults. A download writes only after the user chooses a destination in the native save
panel. Logos does not request an account, upload content, submit assets, or add a macOS TCC prompt.

## Screenshot selection

Screenshot opens an explanation without capturing or prompting. **Choose and Capture** starts
the selected workflow. Window and Display use the native macOS content picker and its scoped
consent for only the chosen content. Region uses Screen Recording access after the explanation;
denial offers the Screen Recording Settings pane. The Settings permission row can also request
this grant explicitly, without starting capture. A canceled request cannot present a late prompt.

Region selection reads geometry only until the person accepts a rectangle. Capture returns an
in-memory PNG for review. Copy and Save are separate explicit actions; no screen image is uploaded,
sent to AI, or persisted automatically. Permission is rechecked and dismissal cancels and clears
pending capture. This adds no entitlement and does not activate the disabled Window Switcher.
See [Screenshot](SCREENSHOT.md) for the native API, bounded artifact, and privacy review.

## Screen recording selection

Screen Recording opens its settings in an independent window without reading screen content or
requesting access. **Choose & Record** presents the native macOS picker for exactly one window or
display; the service retains that consent-bearing filter through the recording. It does not request
broad access or enumerate other content. Display recording can include the visible recording controls,
as explained before selection. System audio is an explicit option, off by default; microphone capture
is always disabled and adds no microphone usage string or entitlement. Only one shared native picker
owner is allowed, so screenshot and recording selection cannot replace each other's consent.

The native sharing indicator and independent Stop controls remain available while capturing. A Stop
failure retains controls with recovery instructions and never reports successful shutdown. Video is
written to private temporary storage during recording; Save exports only after review. Normal discard
removes the owned video, while crash leftovers are cleaned on the next explicit recording start.
No recording is sent to AI, a server, or the clipboard. Native scoped-picker/capture acceptance is still
pending; compilation and generated-video tests do not establish live permission behavior. See
[Screen Recording](SCREEN_RECORDING.md).

## Not requested yet

Notifications, Microphone capture, Location, and Input Monitoring remain
unrequested by production Commandly. The disabled Window Switcher prototype models Screen Recording
thumbnails and global shortcut input but must not request either grant. Microphone Control changes
only the default input device's public Core Audio mute property; it does not open an audio stream,
add an audio-input entitlement, include a microphone usage string, or trigger a TCC prompt.
Clipboard history is opt-in and does not use a TCC prompt, but content must never be logged.
Capture-time OCR and file-text extraction stay on-device; sandbox may prevent reading some pasted
file URLs (those entries remain filename-searchable only). Application uninstall discovers related
files under the **real** user `~/Library` (not the sandbox container home) plus `/Applications`,
using temporary file-access exceptions. Storage Cleaner reuses only the real-user Library portion
of that exception after the user opens the application, and conservatively scans reviewed direct
children for reverse-domain leftovers plus third-party user caches. The uninstall review matches the
selected app bundle ID and helper prefixes (e.g. `com.example.app.helper.plist`); Storage Cleaner
compares identifier candidates with the installed application catalog and skips Apple, Commandly,
shared-group, ambiguous, hidden, and symbolic-link entries. Protected paths and bounded scans may
still be partial. Neither workflow deletes automatically or claims a complete disk wipe.

## Camera permission boundary

Camera authorization is separate from starting video capture. Constructing the permission adapter,
registering Camera Preview, opening its surface, and checking authorization must not construct an
`AVCaptureDeviceInput`, request access, or start a camera. Only an explicit **Start Camera** or Camera
**Grant Access** action may request an undetermined video grant. Starting the preview remains an
explicit **Start Camera** action after authorization. Camera Preview
uses video input only; it does not request microphone access or record audio.

Denied access presents **Open Settings** with the Camera recovery path above. Restricted access
explains that a device administrator may need to change the restriction. Neither state repeatedly
prompts or blocks other launcher applications. Returning from Settings requires a new explicit
start; permission preflight alone never resumes capture.

Preview frames and captured photos remain in memory for the active camera session. Stopping or
leaving the session releases capture resources. No frame, photo, device name, or capture metadata
belongs in logs, command history, uploads, or automatic persistence. An explicit photo capture may
be copied using the ordinary clipboard or saved to a user-chosen destination; the fresh rendered PNG
does not copy source EXIF, GPS, or comments. Camera permission tests inject all authorization checks
and requests, so CI never prompts for or uses the real camera.

## Window Switcher permission boundary

Window Switcher is not an active permission consumer in sandboxed production Commandly. Apple's
[App Sandbox guidance](https://developer.apple.com/documentation/security/protecting-user-data-with-app-sandbox)
lists assistive Accessibility API use and terminating other running apps as incompatible activities.
The prototype needs cross-application Accessibility to enumerate/control windows and inspect the
Dock, so the app must not register the feature, start those adapters, or present an Accessibility
grant as a route to a working sandboxed switcher.

The prototype active event tap receives the subscribed global key-event stream and filters unrelated
events immediately. It is not accurate to say that the system delivers only the configured chords.
A passive listen-only alternative would require
[Input Monitoring](https://support.apple.com/guide/mac-help/control-access-to-input-monitoring-on-mac-mchl4cedafb6/mac)
and cannot suppress Option-Tab or replace Command-Tab. The current app must not request Input
Monitoring for this unavailable workflow, and active suppression is not an established sandbox
boundary.

Screen Recording would add bounded memory-only thumbnails but would not solve window enumeration or
control. Production Commandly must not request Screen Recording for the disabled prototype. A future
authorized non-sandboxed runtime would require contextual explanations and revocation handling for
each separate grant, while keeping titles, thumbnails, queries, application/window activity, pointer
locations, and raw key events out of persistence, logs, uploads, and command history.

A separately signed non-sandboxed companion/helper or disabling App Sandbox for a direct-
distribution build requires a new accepted architecture, security, and distribution decision. The
current permission UI and adapters are foundation/test surfaces, not proof that either model is
authorized or functional.

## Native features without a new permission

- Application and tool global shortcuts use the unified Carbon registration path and add no
  Accessibility or Input Monitoring prompt. Invoking a tool never grants it broader authority: a
  permission-dependent tool still follows its owning feature's contextual explanation, denial, and
  recovery flow. Typed commands have no shortcut or permission state of their own.
- Markdown Preview reads only a file explicitly selected or dropped into Commandly. Finder supplies
  its selected file directly to the separately sandboxed, read-only Quick Look extension. Neither
  path creates a Files and Folders TCC prompt or a persistent folder grant. Enabling or disabling the
  preview provider is a macOS extension-management choice under System Settings, not a data-access
  permission. The extension has no Downloads-wide, network, print, shell, or temporary home-folder
  entitlement; its App Group contains renderer settings only.
- Background Remover receives temporary sandbox access only to an image the user explicitly picks or
  drops. Apple Vision performs foreground segmentation on device, the source and transparent result
  remain in memory for the launcher session, and the PNG is written only through an explicit Save
  panel. It adds no network request, persistent folder grant, account, or TCC prompt.
- Image Tools uses the same explicit picker/drop and Save-panel boundary. ImageIO conversion runs
  locally with bounded input/output and strips source metadata. It does not request TCC permission,
  read other files, overwrite the source automatically, or send image data to a provider.
- Command Wheel's unified Carbon profile shortcut receives press/release events without an
  Accessibility grant. Pointer position is sampled only while the wheel is active. Hold mode uses
  no global mouse monitor; toggle mode temporarily monitors mouse-down only to distinguish an
  inside selection from an outside dismissal, while keyboard input stays inside the temporary
  panel. There is no event tap or global keyboard monitor. A chosen command still follows its own
  existing permission explanation, denial behavior, and recovery route. Permission-dependent
  command manifests are preflighted through the existing permission service without prompting, so
  Settings and the shared resolver show the same unavailable state; the owning implementation
  still rechecks at execution time.
- Command Wheel profiles are non-secret versioned JSON. Its bounded ranking history retains command
  ID, source, outcome, record ID, and timestamp—not pointer paths, search queries, command arguments,
  clipboard values, file contents, credentials, private URLs, or frontmost-window titles.
- Calculation History and Timers & Focus retain only in-process session state.
- Shelf holds explicitly dropped or pasted file/folder URL references only while its board is open.
  An explicit clipboard import may instead materialize text or image data beneath a per-board
  directory in Commandly's temporary container; those private files are deleted when removed and the
  directory is deleted when the board closes or is replaced. Native pasteboard reads, active-display
  geometry, and Shelf's two tool-owned default Carbon shortcuts do not add a TCC, Screen Recording,
  or Accessibility prompt. Either shortcut can be replaced or cleared in Applications settings.
  Shelf does not add an account or background folder access. A receiving native share service may
  require its own sign-in or transfer approval.
- Productivity Library persists private user-authored items locally in Commandly's Application
  Support container and never logs their contents.
- System Activity reads aggregate host statistics and the regular GUI application list through public
  macOS APIs. Quit and force-quit occur only after explicit actions; force quit and quit-all require
  confirmation.
- Port Manager locally inspects listener metadata only after the user opens it. Stopping a listener
  requires explicit confirmation and sends a graceful termination request to its revalidated owning
  process; port/process metadata is not persisted, uploaded, or logged. Sandboxing or process
  ownership can limit which listeners are visible or stoppable.
- Microphone Control reads the default input device name and mute property through Core Audio. It
  never reads audio samples, persists device state, or logs device information. Turning the
  microphone on or off is always an explicit action, and unsupported devices remain unchanged.
- Highlight Mode uses a click-through local overlay and global event monitors only while explicitly
  enabled. Click positions, typed characters, and shortcuts remain in memory only for their visual
  animation; they are not persisted, logged, uploaded, copied, or added to command history. Users
  should disable typed-text feedback before entering sensitive information. Denial or removal of
  Accessibility access leaves the mode unavailable without blocking the rest of Commandly.
- Emoji catalog search, text-case conversion, color conversion/sampling, Dictionary, installed-font
  search, and Typing Practice use local macOS frameworks or bundled data. Emoji's optional Find with
  AI sends only the explicitly submitted description and output-format instructions through the
  configured Quick AI connection. It never sends saved emoji keywords or clipboard content.
- Custom window-layout geometry is a non-secret preference. Applying a layout still follows the
  Accessibility flow above.
- AI provider networking uses the entitlement/ATS boundary described above and has no separate TCC
  prompt. Finder AI remains constrained to existing user-selected folder grants; its opaque handles
  and local approvals do not broaden those grants. Finder Automation is not used as a general AI
  control surface.

## Login items

The optional **System Companion** has its own explicit Settings → System Integration setup,
separate from Open at Login. Commandly opens the verified companion's separate setup window;
that non-sandboxed owner validates matching signatures before explicitly registering its own
per-user background LaunchAgent through `SMAppService.agent`. Opening setup does not register it.
Enabling this foundation grants no Accessibility, Input Monitoring, microphone, or screen access;
its available operation is an authenticated metadata check. Cross-app action payloads are currently
rejected locally. Disconnect in Commandly closes only its channel. Disable Background Service in
Companion Setup unregisters the helper, with recovery if macOS cannot confirm removal.
See [System Companion](SYSTEM_COMPANION.md) for the signed-peer boundary and the
separate native acceptance requirements. The main app retains its existing sandbox.

Open at Login uses `SMAppService.mainApp` and is only registered after the user enables it in onboarding (or a future Settings control). It is not a TCC permission, but macOS may still require approval under **System Settings → General → Login Items**. Denial or pending approval must leave the app usable; the preference is persisted and the UI explains how to recover.

## Policy for all permissions

1. Document user benefit before enabling.
2. Request only when the user activates the control.
3. Explain why before the system prompt when possible.
4. Handle denial gracefully; never block onboarding completion.
5. Provide Settings recovery instructions.
6. Keep scope minimal.
7. Cover behavior with mocked tests — never require real grants in CI.

## Dictation

[Dictation](DICTATION.md) uses on-device SpeechAnalyzer modules with a chosen supported language.
Opening the application reads available languages/inputs and installed model status, but does not
request microphone authorization, download a model, or start capture. Download Language and Start
Dictation are separate explicit actions. There is no SFSpeechRecognizer/server fallback; no speech
server authorization or audio upload is added. Apple manages shared language assets.

Capture stops on Stop, Cancel, route removal, device interruption, or a five-minute limit. Only
reviewed text can be explicitly copied or saved to bounded local history; raw audio is never saved.
Optional Preview Style sends the displayed draft and style instruction to the selected saved AI
provider after its disclosure. It does not send microphone audio, other dictations, or current-app
contents. Generated tests/fixtures do not establish actual microphone grants or recognition quality.

## GIF search and System Settings navigation

[Notion Workspace](NOTION_WORKSPACE.md) accepts a user-owned internal integration token, validates
read access, and stores it through the existing Keychain adapter. Only explicit title search,
page/block reads and database queries reach Notion. No account installation, workspace write,
attachment download or new TCC permission is performed.

[Slack Emoji](SLACK_EMOJI.md) uses a user-supplied internal bot token with exactly `emoji:read`.
Check & Connect explicitly verifies identity and scope before storing it in the existing Keychain
adapter. Refresh and selection fetch only the chosen workspace's inventory and original media;
queries stay local. Native Save uses an exact user-selected destination. No additional entitlement
or TCC permission is introduced, and the feature cannot send Slack messages.

[GIF Search](GIF_SEARCH.md) uses the existing network-client entitlement and an explicitly configured
GIPHY API key in Keychain. Submitting Search or Trending sends the key and requested query directly
to GIPHY; selecting a result fetches its preview. Copy/Save fetches the original animation. Opening
the tool and typing do not contact the catalog. A native Save panel grants only the selected file;
there is no new TCC permission. Provider account creation and terms acceptance remain user actions.

[System Settings commands](SYSTEM_SETTINGS_NAVIGATION.md) read only fixed Apple bundle metadata and
open a known settings page with NSWorkspace. They do not read or change settings values, grant
permissions, register a service, or automatically operate the destination page.

## Configured keyboard triggers and literal expansion

The optional non-sandboxed companion owns the public CG event tap and Caps-only IOHID observer.
Input Monitoring and Accessibility are separately requested only by the visible Companion Setup
“Review Keyboard Access” action after its explanation. Main-app Configure, constructors, Settings
loads and connection checks only preflight grants and never prompt. The main app retains its sandbox.

Bindings and automatic expansion are individually configured, followed by explicit Enable. The tap
necessarily receives subscribed events before filtering; unrelated input is passed through without
logging, IPC or storage. Optional expansion keeps only a configured keyword prefix (maximum 32 ASCII
characters), and reads only an exact bounded range in a supported non-secure focused text field.
Secure Input, focus boundaries and lost capability authority clear input state. Disconnect, permission
revocation, session loss, device removal and expiration stop interception and release Hyper flags.

Users recover through Companion Setup and System Settings → Privacy & Security → Input Monitoring
and Accessibility. OS grants do not enable a feature by themselves. Saved preferences do not persist
an enabled flag. There is no clipboard, synthetic paste/backspace, full-field value replacement, AI,
private AX attribute, shell or AppleScript fallback. Native permission, keyboard hardware, secure
context and host text/Undo acceptance remains pending; see [Keyboard Triggers](KEYBOARD_TRIGGERS.md).

## Quick Toggles

Each row acts only on an explicit tap, and **Empty the Trash** additionally asks for confirmation
in the row before anything is removed. Three rows — showing hidden files, hiding desktop icons, and
putting the display to sleep — need authority App Sandbox withholds; they stay visible, explain
that, and never present a switch that does nothing.

Locking the screen and the keyboard-light row post key events and therefore need Accessibility.
They say so in place of their caption until it is granted, and neither reads input.

## Menu bar panel readings (no new TCC permission)

The panel's System, Network, Disks, Power, and Fans sections read kernel statistics, the IO
registry, and mounted-volume capacity. None of these is behind a consent prompt, and none of them
identifies a person: processor and memory counters, interface byte totals, volume capacity, battery
state, and fan speed. Sampling runs only while the relevant section is on screen, so a closed panel
costs nothing.

Some readings are simply unavailable to a sandboxed app, and the panel says so rather than showing a
zero: chip and fan sensors need an IOKit user client App Sandbox does not open, per-app network use
needs a command-line tool the sandbox cannot run, per-app energy impact needs a process interface the
sandbox does not grant, and drive SMART counters need a device interface the sandbox does not open.
Fan control is offered only where that same controller can be reached and written.

The Network section's **Test speed** button is the one place in the panel that sends data off the
Mac. It runs only when the user presses it, measures against Cloudflare's public speed endpoints,
and uploads generated zeroes — never anything from this Mac.
