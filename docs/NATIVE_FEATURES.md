# Native feature inventory

This is the historical 101-item native-feature inventory. The current September 2026 video request
has a broader scope, tracked in [Video Feature Parity](VIDEO_FEATURE_PARITY.md); exclusions below
do not remove requirements from that newer goal.

This document maps the requested 101-feature checklist to the behavior that exists in the
current Commandly working tree. It is intentionally conservative: a permission contract,
placeholder row, test double, or adjacent capability does not count as a finished feature.

Commandly is an original native macOS product. The checklist is used only as a capability audit;
Commandly does not copy another launcher's source, branding, assets, marketing language, icons, or
exact interface layouts. Entries tied to another company's hosted services are retained below only
so the audit is complete, and are excluded when they conflict with the native/local scope.

## Status definitions

- **Existing** — the workflow was already implemented before this feature pass.
- **Implemented in this change** — the current working tree adds a registered application or a
  complete extension of an existing workflow for this item.
- **Partial** — a useful subset exists, but the requested end-to-end behavior does not.
- **Not implemented/excluded** — there is no usable workflow. This also covers features that require
  external services, paid APIs, unsupported/private macOS APIs, accounts, or a substantially larger
  security and permission design.

At this snapshot, 13 items are Existing, 26 are Implemented in this change, 12 are Partial, and 50
are Not implemented/excluded.

## Starting any Commandly application

1. Press **Option-Space** or choose **Open Commandly** from the menu bar.
2. Type an application, tool, tag, or supported typed command, use the arrow keys if needed, and
   press Return. The same root query can also show captured clipboard entries and authorized files.
3. Within an application, Return runs its primary action, Command-K opens its action menu, and
   Escape first clears local UI state before returning to the launcher.
4. To add search tags, enable or disable an application/tool, or assign an application/tool global
   shortcut, open **Commandly Settings → Applications**, expand the application, and select the
   relevant row. These settings apply to Commandly's registered definitions, not arbitrary installed
   macOS applications.

## Run known commands with Command Wheel

Open **Settings → Command Wheel**, enable the feature, and assign a modified shortcut to an
enabled profile. Hold-and-release mode opens the radial panel around the pointer and runs the
highlighted segment on key-up; Toggle mode supports hover/click and temporary keyboard focus.
Tab/arrow keys, 1–9, Return, and Escape provide a complete non-pointer route. Profiles can contain
stable command assignments, rooted submenus, or bounded recent/frequent command providers, and can
choose pointer, active-display-center, or normalized fixed placement.

The runtime ring is icon-only, with full names retained in Settings and accessibility. The Settings
picker searches both registered commands and installed applications; an app assignment stores the
same typed bundle-identifier reference used by launcher search and renders its native macOS icon.

Command Wheel does not add another command catalog. Registered Commandly commands and installed-app
references resolve through the same typed CommandKit registry, availability checks, executor,
feedback, and privacy-safe history used by launcher search and application/tool hotkeys. The default
configuration is disabled, has no shortcut, and contains File Search, Clipboard History, and Open
Settings. See [Command Wheel](COMMAND_WHEEL.md) for configuration, interaction, context rules,
import/export, privacy, and limitations.

## New and expanded application workflows

### Clipboard History and clipboard editing

Open **Clipboard History** to search captured text, images, and file URLs or filter by content type.
Select an entry and press Return to copy it again. Command-K exposes Delete and Clear History plus
the new text workflows:

- **New Text Entry** creates a history entry and makes it the current clipboard value.
- **Edit Text Entry** edits the selected text entry and makes the result current. Images and file
  entries are intentionally not editable.
- **Append to Clipboard** adds text after the current string clipboard, inserting a newline when
  needed, then records and copies the combined value.

Clipboard monitoring and on-device Vision/PDFKit enrichment remain in memory for the current app
process. A normal launcher-root query also shows up to six matches from that capture-time data;
Return copies one directly without first opening Clipboard History. Private root rows do not feed
autocomplete or command history. Clipboard contents, OCR text, and file contents are never logged or
uploaded.

### Calculation History

Use the launcher calculator normally, then explicitly use a successful result to add it to the
current session. Open **Calculation History** to search expressions and formatted answers. Return
copies the selected result; Command-K can copy the original expression, delete one result, or clear
the history. The bounded history is in-process only and is not a durable record of everything typed.

### Timers & Focus

Open **Timers & Focus**, choose the 25-minute Focus or 5-minute Short Break preset, or enter a name
and a duration from 1 to 1,440 minutes. Multiple timers can run at once. Select a timer to pause,
resume, reset, or delete it; search and phase filters narrow the list. Countdown state uses absolute
dates to avoid tick drift and continues when the launcher closes, but not after Commandly quits.
Completion can play a local macOS sound. There are no notifications, background launch, or automatic
Pomodoro cycles.

### Shelf

Open **Shelf** from the launcher, menu-bar commands, or the default shortcuts owned by its **New
Shelf** / **New Shelf From Clipboard** tools (`⌥⇧Space` / `⌥⇧A`). Either shortcut can be replaced or
cleared in Applications settings. Each request opens in the preferred corner of the active display
and macOS Space. Drop concrete file or folder URLs on the floating board; a blue outline plus an
item-count prompt confirms targeting, and AirDrop, Messages, and Mail targets appear below it for
direct native sharing. Shelf keeps external references rather than copying those originals.

The clipboard command accepts file/folder URLs, a standalone image, or plain text. Shelf keeps URLs
as external references and materializes image/text data into private per-board temporary files that
are removed with their items or when the board closes. The board can be repositioned from any
unoccupied surface area, stays fixed during item drag-out, and reveals new content with a subtle
fade/scale that becomes immediate under Reduce Motion.

Open the detail grid to select items, inspect native previews and metadata, drag a multi-item
selection out, or use Open/Open With, Quick Look, Finder, native sharing, clipboard URL/path,
duplicate/copy/move/rename, remove, clear, and confirmed Trash actions. Drag-out is copy-only, so it
never moves/deletes originals and always retains the staged items. Settings → Applications controls
inactive visibility, closing after the last item is explicitly removed, initial corner,
and optional local drop sound.

The board is transient and single-instance. It does not persist or restore shelves, materialize
promised files, preserve rich-text formatting, provide cloud-provider uploads or links, transform
files, run scripts, monitor folders, or activate from the notch, menu-bar drag zone, or a shake
gesture. See `docs/SHELF.md`.

### Productivity Library

Open **Productivity Library** and use the add menu to create one of four local item types:

- **Snippet** — reusable text or code with `{{clipboard}}`, `{{date}}`, `{{time}}`, `{{datetime}}`,
  `{{uuid}}`, and named `{{input:Name}}` fields. Copy prompts for named values, then expands each token
  from one copy-time snapshot. Inserted values are literal text and are never interpreted again.
- **Quick Note** — persistent local text that can be searched and copied.
- **Quicklink** — a validated HTTPS/HTTP URL, file URL, absolute or `~/` path, folder path, or custom
  application deep link. `javascript:` and `data:` payloads are rejected.
- **Emoji Keyword** — a keyword in the title paired with an emoji value that can be searched and
  copied.

The application supports search, type filters, create, edit, delete confirmation, primary actions,
and the native share sheet through `ShareLink`. Every item can have up to 12 comma-separated tags
(32 characters each); tags are searchable and the Tag filter narrows the library. Items are stored as versioned JSON in Commandly's
Application Support container. Sharing is a user-selected native share action, not a Commandly
account, public link, or team library. Opening a Quicklink is always an explicit action; sandbox or
target-application restrictions can still prevent a protected path or deep link from opening.
Version 1 library files migrate when saved; version 2 retains tags. Named snippet values remain in
memory only until copying/cancellation/session close and are not saved with the template. Template
and expanded output size is limited to 1 MB, with at most 16 distinct prompted fields. Date/time
tokens use local time (`yyyy-MM-dd`, `HH:mm`). Automatic expansion while typing in other apps is not
implemented by this copy workflow.

### Recent Downloads

Open **Recent Downloads** to scan the top level of the user's Downloads folder for visible regular
files. Items are ordered by the date they were added to Downloads, then creation and modification
date fallbacks. Return opens the selected file in its default application; Command-K can open or copy
the newest item directly, reveal the selection in Finder, copy the actual file URL, or refresh.

The scan runs off the main actor, is bounded to 50 results by default, supports cancellation and
stale-result protection, and reads metadata rather than file contents. A narrow read-only Downloads
sandbox entitlement permits this workflow; Commandly cannot modify Downloads through it and never
logs filenames or paths.

### Background Remover

Open **Background Remover**, choose or drop an image, and Commandly uses Apple Vision locally to
separate all detected foreground subjects. The application shows original and transparent previews
and exports a PNG only after an explicit save action. Processing does not use the configured BYOK AI
provider or a network connection; source bytes, masks, and results stay in memory for the active
launcher session. Busy scenes, fine edges, transparent objects, and low foreground contrast can
reduce cutout quality.

### System Activity

Open **System Activity** and switch between:

- **Resources** — aggregate CPU, memory, usage of the filesystem containing the user's home
  directory, uptime, and thermal state, refreshed
  automatically every three seconds or manually with Return.
- **Applications** — searchable regular GUI applications. Return activates the selected app;
  Command-K offers graceful Quit, confirmed Force Quit, and confirmed Quit All Other Applications.

Commandly, Finder, and the current frontmost application are protected from bulk termination.
Unsaved work can still be lost when the user confirms a force or bulk action. This is not a full
Unix process inspector: it does not list daemons or provide per-process CPU, memory, ports, or signals.

### Port Manager

Open **Port Manager** to inspect local TCP and UDP listeners visible to the current user. Filter by
port, process name, PID, or protocol, then press Return on a selected listener to review a required
confirmation. Confirming sends a graceful termination request to the process owning that listener;
Commandly rechecks the process/port match immediately before that request. A port cannot be stopped
independently of its process, and protected or other-user processes may be unavailable. Listener
metadata stays on-device for the active session and is never stored, uploaded, or logged.

The exact launcher phrases `kill port <number>` and `stop port <number>` invoke the same Kill Port
tool with a typed integer. They prefill Port Manager and may prepare the matching listener for
review, but they never bypass the explicit confirmation or owner revalidation. The Kill Port tool
can also receive a global shortcut; without an argument it opens the review surface for manual
selection.

### Storage Cleaner

Open **Storage Cleaner** to review identifier-based app leftovers and third-party caches in the
current user's real Library. Leftovers are selected as recommendations; caches remain unchecked
until the user chooses them. The scanner is bounded, excludes Apple and Commandly data plus
ambiguous names and shared containers, and reports partial access instead of claiming a complete
disk sweep.

Choose **Find Exact Duplicates…** to select one folder for an ephemeral on-device scan. Regular files
are grouped by size and then compared with incremental SHA-256 hashes. One copy in every exact-match
group always remains unchecked, including when the user changes which copy to keep. Commandly does
not persist the folder grant, paths, hashes, results, or selections. Review Cleanup shows an exact
count and size before confirmed items move to Trash; Storage Cleaner never permanently deletes or
empties Trash. See [Storage Cleaner](STORAGE_CLEANER.md).

### Microphone Control

Open **Microphone Control** to see the current default input device and whether its Core Audio mute
property is on or off. Press Return or use the main button to change that state. The view refreshes
while open so a device switch or mute change made elsewhere is reflected in Commandly.

This changes the default device rather than one application's private capture session, so apps that
use that input device receive the same muted or unmuted state. Commandly does not capture audio or
request Microphone permission. Some external, virtual, aggregate, and driver-managed devices do not
publish a writable mute property; those devices are reported as unsupported and their gain is not
silently changed.

### Window Layouts

Open **Window Layouts**, search or browse the 58 built-in presets, and press Return to apply the
selected rectangle to the window that was focused before Commandly opened. Commandly captures that
external target before raising the launcher, then uses the macOS Accessibility API to resize and
position its focused window on the relevant visible screen.

The **Custom** source lets the user save and delete named normalized rectangles by entering x, y,
width, and height values within the screen. Custom rectangles persist as non-secret preferences.
Applying a layout requests Accessibility access only after the user invokes the action. Unsupported
or missing focused windows fail with an explanation. There is no multi-application workspace layout,
window-sequence automation, or separate global shortcut for each rectangle.

### Window Switcher

Window Switcher is foundation/prototype work, not a usable launcher application. Contracts,
in-memory adapters, original UI/presentation models, a settings schema, app-target prototypes, and
deterministic tests exist, but production registration and coordinator startup must remain disabled
while Commandly uses App Sandbox. Apple's
[App Sandbox guidance](https://developer.apple.com/documentation/security/protecting-user-data-with-app-sandbox)
lists assistive Accessibility API use and terminating other running apps as incompatible activities;
the prototype requires both cross-application window control and graceful quit.

The modeled Option-Tab/Command-Tab active event tap, Dock Accessibility traversal, window
enumeration/actions, and Screen Recording thumbnails are therefore not current product workflows.
A listen-only input monitor would require Input Monitoring and could not suppress or replace system
shortcuts. A future separately signed non-sandboxed companion/helper or a non-sandboxed direct-
distribution build requires a new accepted architecture, security, and distribution decision.

The prototype and interface remain original Commandly work; no GPL-licensed source, assets, copy,
symbols, or exact layout from the supplied reference project is included. Private Dock, Spaces,
WindowServer, media, and blur APIs remain forbidden. See [Window Switcher](WINDOW_SWITCHER.md) and
the rejected [ADR-0008](decisions/ADR-0008-window-switcher-public-api-boundary.md).

### Emoji Search

Open **Emoji Search**, type an English Unicode name such as “heart,” select with the keyboard or
pointer, and press Return to copy. The catalog is curated locally from Unicode scalar metadata and
contains more than 200 common emoji. It performs no network or AI search and is not a complete emoji
standard browser.

### Convert Text Case

Open **Convert Text Case**, enter text in the Input editor, and choose UPPERCASE, lowercase, Title,
Sentence, camelCase, PascalCase, snake_case, kebab-case, or CONSTANT_CASE. The converted pane updates
locally; press Return or use the footer to copy it.

### Color Tools

Open **Color Tools** and enter `#RGB`, `#RGBA`, `#RRGGBB`, `#RRGGBBAA`, `rgb(...)`, or `rgba(...)`,
or choose **Pick from Screen** to use the native macOS color sampler. The application previews the
color and can copy HEX, RGB/RGBA, or HSL. It does not record the screen or upload sampled pixels, and
it does not yet parse or emit every color space.

The application also exposes **Pick Screen Color** as a focused tool. Assigning that tool a global
shortcut runs the native picker directly and copies the sampled Hex value without first opening the
Color Tools surface.

### Dictionary

Open **Dictionary**, enter a word, and press Return. The definition comes from dictionaries installed
in macOS through the local Dictionary Services API. The result can be selected or copied. No web
fallback, translation, account, or downloadable dictionary service is included.

### Search Fonts

Open **Search Fonts** to filter the font families installed on this Mac. Select a family to preview a
pangram, uppercase/lowercase characters, and digits in that family; press Return to copy the family
name. The workflow does not install, activate, deactivate, or sync fonts.

### Typing Practice

Open **Typing Practice** and reproduce the displayed local passage in the editor. Commandly reports
estimated words per minute and character-position accuracy and marks the attempt complete when the
passage matches. **New Attempt** resets it. Attempts and scores are not saved or uploaded.

## Relevant existing workflows

### Launching installed applications

Open Commandly and type an installed app's name. Results are discovered from the standard macOS
Applications folders and show the app's own bundle icon. Return opens the selected app. Right-click
or press Command-K for Finder, favorite, clipboard, disable, ranking, auto-quit, and uninstall actions.

### Calculator

Type an arithmetic, scientific, unit, date, time-zone, finance, geometry, business, or developer
expression directly into the launcher. A calculator card appears above normal search results. Return
or the answer pane copies the result without dismissing Commandly; the question pane restores the
expression for editing. Evaluation is deterministic and local except the pre-existing currency-rate
path, which uses the no-key Frankfurter service and reports provider failures rather than inventing
rates. Calculator expressions and predictions are not logged or persisted.

### Search Files

Open **Search Files**, authorize folders through the Files and Folders flow, then search indexed
names, paths, Finder tags, metadata, supported document text, PDFs, and bounded on-device image OCR.
Use the type filter and arrow keys; Return opens in the default app. Command-K exposes Open With,
native sharing, Finder actions, copy/move/duplicate, clipboard export, Commandly shortcuts, and Trash.
The SQLite/FTS index stays local and covers only user-authorized folders. A normal root query also
shows at most ten indexed matches after a short cancellable debounce; Return opens one directly,
while filters, previews, and mutation actions remain in Search Files.

### Application tags, tools, shortcuts, auto-quit, and uninstall

**Commandly Settings → Applications** shows an expandable Group → Application → Tool hierarchy and
manages built-in/user tags, global Carbon hotkeys, enablement, and non-secret configuration for
registered Commandly definitions. A tool can own a shortcut independently of its application;
typed-command syntax invokes a tool but cannot own another shortcut. Installed macOS app rows instead
use the launcher's action panel. There, **Enable Auto Quit** gracefully terminates that background
app after the fixed idle threshold, while **Uninstall Application…** opens a review of the bundle and
matching support files before moving selected items to Trash. Protected files may fail and are
reported as partial failures rather than a complete wipe.

Launcher, registered application/tool, and Command Wheel shortcuts share one conflict-checked Carbon
registration plan. Shelf's defaults are owned by its two tools rather than a separate fixed runtime
route. Profile shortcuts support both key-down and key-up so hold-and-release does not require
Accessibility access or a global keyboard monitor. Installed applications can be assigned to wheel
slots through the shared parameterized open-application command; this does not make arbitrary
installed-app hotkeys configurable.

### Launcher placement

The fixed-size launcher is initially centered and can be dragged by its background. Its current
position can be adjusted manually during use, but there is no dedicated reset-position command or
workspace-aware placement system.

## Complete 101-item status

| # | Requested idea | Status | Actual Commandly behavior and limitation |
|---:|---|---|---|
| 1 | Launch Applications | Existing | Root search discovers standard installed `.app` bundles and opens the selected bundle with `NSWorkspace`. |
| 2 | Search Files | Existing | Root search shows a bounded open-only projection; the registered local-index application adds filters, previews, content search, and native file actions inside user-authorized folders. |
| 3 | Browse Your Clipboard History | Existing | Root search can copy bounded capture-time matches; the in-memory application adds type filters, previews, editing, delete, clear, and on-device enrichment. |
| 4 | Append entries to your clipboard | Implemented in this change | Clipboard History can append text to the current string clipboard with newline handling and record the combined entry. |
| 5 | Edit your clipboard | Implemented in this change | Text history entries can be edited; saving also makes the edited value current. Image and file entries are read-only. |
| 6 | Do Simple Math | Existing | The launcher calculator supports basic arithmetic, percentages, powers, roots, and common numeric syntax. |
| 7 | Do Complicated Math | Existing | CalculatorKit covers scientific functions and many deterministic finance, geometry, business, statistics, and developer evaluators; it is not general symbolic algebra. |
| 8 | Convert between units | Existing | Native `Measurement`-based and dedicated registries cover many physical/data units with explicit ambiguity and assumption handling. |
| 9 | Perform date calculations | Existing | Calendar-aware relative dates, differences, business days, schedules, time zones, and clamped month/year arithmetic are supported. |
| 10 | Keep a history of all of your calculations | Implemented in this change | Calculation History keeps up to 100 explicitly used successful results for the current process, not every typed query and not across relaunches. |
| 11 | Check the Weather | Not implemented/excluded | No WeatherKit or remote weather workflow is registered; Location permission is not requested. |
| 12 | Search for GIFs | Not implemented/excluded | GIF catalog search requires remote content/provider integration and is absent. Local files can still be found through Search Files. |
| 13 | Search for Emojis | Implemented in this change | Emoji Search locally filters a curated Unicode catalog and copies the selection. |
| 14 | Search for Emojis with AI | Not implemented/excluded | The BYOK runtime is not connected to Emoji Search; that application remains deterministic and local. |
| 15 | Set Timers | Implemented in this change | Timers & Focus supports multiple named countdowns, presets, pause/resume/reset/delete, filters, and optional local sound. |
| 16 | Replace Spotlight | Partial | Option-Space opens a fast keyboard launcher, but Commandly does not disable Spotlight, take over Command-Space, or modify macOS preferences. |
| 17 | Lock the screen | Not implemented/excluded | No lock-screen command is registered. |
| 18 | Save reusable blocks of text | Implemented in this change | Persistent Productivity Library snippets provide searchable reusable text/code. |
| 19 | Turn your favorite emojis into keywords | Implemented in this change | Emoji Keyword items pair a searchable title/keyword with a copied emoji value. |
| 20 | Create dynamic blocks of code from your clipboard | Implemented in this change | Snippets replace every `{{clipboard}}` token on explicit copy. There is no arbitrary script or template execution. |
| 21 | Share snippets | Implemented in this change | Saved items and drafts use the native share sheet; there is no Commandly-hosted public/team link. |
| 22 | Search Google | Not implemented/excluded | No query-to-Google command exists. A user may save a static website Quicklink, but it is not a search provider. |
| 23 | Have AI search the web | Not implemented/excluded | Finder AI has no browser or web-search tool, and no remote web-search service is included. |
| 24 | Not search the web at all | Not implemented/excluded | There is no AI web-search mode or toggle, and Finder AI cannot search the web. Ordinary launcher, file, emoji, dictionary, font, and tool searches are local; currency and explicit BYOK provider traffic are the documented network exceptions. |
| 25 | Take Quick Notes From Anywhere | Implemented in this change | Persistent Quick Notes are available from the launcher and can receive a configured global app shortcut. They copy/share text but do not modify Apple Notes. |
| 26 | Open Your Latest Download | Implemented in this change | Recent Downloads orders visible top-level files by download/creation/modification recency and can open the newest or selected file in its default app. |
| 27 | Copy Your Latest Download | Implemented in this change | Recent Downloads can copy the newest or selected file URL to the pasteboard for use in another app. |
| 28 | Search Screenshots By Content | Partial | Search Files performs bounded on-device OCR for indexed images in authorized folders, which can include screenshots; there is no screenshot-specific catalog or guarantee every image is OCR'd. |
| 29 | Arrange windows in 58 predefined ways | Implemented in this change | Window Layouts provides exactly 58 built-in normalized presets and targets the external app focused before Commandly opened. |
| 30 | Custom window management commands | Partial | Users can persist and apply custom rectangles, but each custom layout is not an independently discoverable command or global hotkey. |
| 31 | Automate the whole thing with window layouts | Not implemented/excluded | There is no multi-window, multi-application workspace capture/restore or sequence automation. |
| 32 | Monitor System Resources | Implemented in this change | System Activity shows aggregate CPU, memory, the home-directory filesystem, uptime, and thermal state; no GPU/network/battery or per-process resource table. |
| 33 | Set up hotkeys for apps | Partial | Global hotkeys are configurable independently for registered Commandly applications/tools and for Command Wheel profiles. Arbitrary installed app launch hotkeys are not configurable. |
| 34 | Set up aliases for apps | Partial | Registered Commandly applications/tools have maintained tags plus bounded user tags. Legacy aliases remain searchable, but arbitrary installed `.app` results do not receive custom tags. |
| 35 | Toggle system | Partial | Microphone Control provides one supported system toggle through Core Audio. There is no general system-toggle framework, and private or unsupported control APIs are not used. |
| 36 | Emptying the trash | Not implemented/excluded | File, uninstall, and Storage Cleaner workflows can move selected items to Trash, but Commandly does not empty Trash. |
| 37 | Install brew apps | Not implemented/excluded | Homebrew is external and would require shell/process execution, which this project explicitly forbids. |
| 38 | Stay on top of your schedule | Not implemented/excluded | “My Schedule” remains an honest placeholder. Calendar permission support alone is not a calendar application. |
| 39 | Join Online Meetings | Not implemented/excluded | No calendar-event or meeting-link workflow exists. |
| 40 | Check your appearance before joining | Not implemented/excluded | No camera preview is implemented and Camera permission is not requested. |
| 41 | Take a selfie | Not implemented/excluded | No camera capture workflow exists. |
| 42 | Create Quicklinks for your favorite websites | Implemented in this change | Productivity Library validates and opens HTTP/HTTPS Quicklinks on explicit action. |
| 43 | Create Quicklinks for your most used files | Implemented in this change | File URLs and absolute or `~/` file paths can be saved; sandbox/protected-path restrictions still apply. |
| 44 | Create Quicklinks for folders | Implemented in this change | Folder paths/file URLs can be saved and opened through the native workspace. |
| 45 | Create Quicklinks for app deeplinks | Implemented in this change | Valid custom URL schemes are accepted; unsafe `javascript:` and `data:` schemes are rejected. |
| 46 | Toggle Bluetooth | Not implemented/excluded | macOS does not provide a suitable supported sandboxed API for a third-party app to toggle Bluetooth power; private APIs are not used. |
| 47 | Control Apple Music | Not implemented/excluded | Commandly can launch installed apps but has no Music playback/library controller. |
| 48 | Control Spotify | Not implemented/excluded | No Spotify account, Apple Events, URL-control, or Web API integration is included. |
| 49 | Create Spotify playlists with AI | Not implemented/excluded | Finder AI has no Spotify authority. This would require a separately reviewed Spotify account/API integration and approval boundary. |
| 50 | Switch between open windows | Not implemented/excluded | Contracts, settings, prototype adapters/UI, and deterministic tests exist, but sandboxed production Commandly keeps Window Switcher unregistered and disabled. Cross-application assistive Accessibility/termination is App Sandbox-incompatible; a privileged helper or non-sandboxed distribution requires a new accepted decision. |
| 51 | Manage running processes | Partial | System Activity lists and manages regular GUI applications only; it is not a daemon/Unix-process inspector. |
| 52 | Start a Screen Recording | Not implemented/excluded | No recording workflow exists. The disabled Window Switcher prototype models bounded in-memory thumbnails, but production Commandly does not request Screen Recording for it. |
| 53 | Take a Screenshot | Not implemented/excluded | No screenshot workflow exists. The disabled Window Switcher prototype has no production capture path or save/copy/export action. |
| 54 | Record audio | Not implemented/excluded | No audio recorder exists and Microphone permission is not requested. |
| 55 | Quit applications | Implemented in this change | System Activity requests graceful termination for a selected unprotected GUI application. |
| 56 | Force quit applications | Implemented in this change | System Activity offers a destructive confirmation before native force termination. |
| 57 | Automatically quit applications | Existing | Installed-app Actions can enable a fixed five-minute background idle auto-quit policy using graceful native termination. |
| 58 | Uninstall applications | Existing | A review workflow discovers the app and matching support files, then moves the user's selected items to Trash and reports partial failures. |
| 59 | AI Chat with multiple models | Partial | BYOK settings support an explicit catalog of providers and credential-visible models, while Finder AI provides one in-memory conversation with the active model. There is no provider-neutral general chat surface or mid-conversation model switch. |
| 60 | Browse your AI Chat history | Not implemented/excluded | The current Finder AI transcript is memory-only and ends with its launcher session; there is no persisted or searchable chat history. |
| 61 | Add attachments to AI Chat | Not implemented/excluded | There is no general AI chat attachment workflow. Finder AI can disclose only exact bounded file text through its separate local approval flow. |
| 62 | Give entire websites as context to AI | Not implemented/excluded | There is no website ingestion, browser crawler, or AI context system. |
| 63 | Save and share AI presets through a hosted service | Not implemented/excluded | This requires an external service and conflicts with the original/local scope. |
| 64 | Launch AI commands from anywhere | Partial | Finder AI is a registered launcher application; there is no catalog of standalone reusable AI commands or presets. |
| 65 | Assign hotkeys to AI commands | Partial | Finder AI participates in registered-application hotkey settings, but individual AI prompts or presets are not commands and cannot receive their own hotkeys. |
| 66 | Switch Keyboard Layouts | Not implemented/excluded | No input-source switching command is registered. |
| 67 | Switch your display resolution | Not implemented/excluded | No display-mode workflow is registered. |
| 68 | Eject all of your disks | Not implemented/excluded | No volume-ejection service or confirmation workflow exists. |
| 69 | Eject one disk at a time | Not implemented/excluded | No mounted-volume browser or eject action exists. |
| 70 | Convert images | Not implemented/excluded | No ImageIO conversion application is registered. File Search previews and manages files without transforming them. |
| 71 | Rotate images | Not implemented/excluded | No image mutation workflow exists. |
| 72 | Compress images with TinyPNG | Not implemented/excluded | TinyPNG is an external network service; no credential/upload path is included. |
| 73 | Convert Text Cases | Implemented in this change | Convert Text Case supports nine deterministic local styles and copies the output. |
| 74 | Measure distances on your screen | Not implemented/excluded | No screen-measurement overlay exists. The disabled Window Switcher prototype does not create a production Screen Recording grant or measurement workflow. |
| 75 | Search for Fonts | Implemented in this change | Search Fonts filters and previews installed font families and copies the family name. |
| 76 | Pick colors | Implemented in this change | Color Tools invokes the native `NSColorSampler` after explicit user action; its focused picker tool can receive a direct global shortcut. |
| 77 | Convert colors to any format | Partial | Color Tools parses HEX and RGB/RGBA and emits HEX, RGB/RGBA, and HSL; other color spaces and “any format” are not supported. |
| 78 | Look up word definitions | Implemented in this change | Dictionary uses installed macOS dictionaries locally and can copy the result. |
| 79 | Translate a word to another language | Not implemented/excluded | No Translation framework or remote translation workflow is registered. |
| 80 | Manage your Apple Notes | Partial | A calculator action can copy `expression = result` and open Notes, but Commandly cannot browse, create, edit, or delete notes. Quick Notes remain Commandly-local. |
| 81 | Use natural language to create reminders | Not implemented/excluded | No EventKit reminders workflow or natural-language parser is registered. |
| 82 | Set your Slack status | Not implemented/excluded | Requires an external Slack account/API and is absent. |
| 83 | Open files in their default app | Existing | Return in Search Files opens the selection through the native workspace. |
| 84 | Choose another app on the fly | Existing | Search Files Actions includes a nested native Open With list. |
| 85 | Track flights | Not implemented/excluded | Requires current remote aviation data and no provider is integrated. |
| 86 | Check the time at your destination | Existing | Calculator time-zone queries use date-aware IANA zones and reject ambiguous abbreviations. |
| 87 | Sync your setup with the cloud | Not implemented/excluded | Preferences and indexes are local; no iCloud/CloudKit synchronization exists. |
| 88 | Create and share themes | Not implemented/excluded | Commandly has design tokens and local appearance preferences, not a user theme editor or sharing service. |
| 89 | Share hosted images of your code | Not implemented/excluded | Hosted code-image services are intentionally not integrated. |
| 90 | Create custom icons through a hosted service | Not implemented/excluded | Hosted icon creation and third-party assets are intentionally not integrated. |
| 91 | Download YouTube videos | Not implemented/excluded | Requires external downloading/network behavior and raises platform/copyright concerns; no such command exists. |
| 92 | Manage pomodoro sessions | Partial | Timers & Focus provides 25/5 presets and multiple countdowns, but no automatic work/break cycle, session history, or productivity reporting. |
| 93 | Quit all applications at once | Implemented in this change | System Activity can confirm and gracefully quit all eligible GUI apps while protecting Commandly, Finder, and the frontmost app. |
| 94 | Quick access to all your system settings | Partial | Commandly Settings and recovery links open relevant Accessibility, Calendar, Contacts, and Files & Folders panes; there is no catalog of every System Settings pane. |
| 95 | View 2 factor authentication codes | Not implemented/excluded | SecurityKit contains contracts, not a TOTP vault. No secret-storage UI or code generator exists. |
| 96 | Practice your typing | Implemented in this change | Typing Practice reports local WPM/accuracy for a fixed passage and resets attempts without accounts or persistence. |
| 97 | Move the Commandly launcher around to fit your workspace | Existing | The Commandly launcher is initially centered and draggable by its background; it is fixed-size rather than workspace-aware. |
| 98 | Reset the Commandly launcher position | Not implemented/excluded | There is no explicit reset-position command. |
| 99 | Create an Organization | Not implemented/excluded | No accounts, organization backend, billing, roles, or cloud service exists. |
| 100 | Share snippets and Quicklinks with your team | Not implemented/excluded | Native ShareLink can share individual content, but there is no team workspace, synchronization, or access control. |
| 101 | Throw Confetti | Partial | Onboarding has a one-time local completion burst, but there is no reusable Confetti command or general effect application. |

## Native, free, permission, and privacy boundaries

| Area | Native/free implementation | Permission and privacy boundary |
|---|---|---|
| Clipboard History | `NSPasteboard`, Vision, PDFKit, and local text extraction | No TCC prompt; in-memory only; content and enrichment are never logged. Clear History is user initiated. |
| Background Remover | Apple Vision foreground-instance masks and Core Image PNG encoding | Explicitly picked or dropped images are processed on device. Bounded previews and the transparent result remain in memory until the session ends; export requires an explicit destination and no image data is logged or uploaded. |
| Calculator | Native deterministic parsers and Foundation measurements/calendars | Queries/results are not logged or persisted. Currency is the one documented pre-existing no-key network provider and was not expanded by this pass. |
| Productivity Library | Versioned JSON, native pasteboard/workspace, and `ShareLink` | Local Application Support storage; no content/path logging. Quicklinks open only after explicit action and unsafe schemes are rejected. |
| Timers & Focus | Foundation dates/timer and optional `NSSound` | In-process only. No Notifications entitlement/prompt and no attempt to survive app termination. |
| Shelf | SwiftUI/AppKit drag-and-drop and screen geometry, Carbon hot keys, Quick Look, `NSWorkspace`, `NSSharingService`, `NSPasteboard`, `FileManager`, and optional `NSSound` | One transient board of security-scoped file/folder URL references plus owner-only temporary files for explicit clipboard text/image imports. Owned files are removed with their item or board. No path/content logging, upload, persistence, Screen Recording/Accessibility requirement, or new automatic TCC prompt. File mutations and native sharing are explicit; the receiving service controls any transfer or sign-in. |
| System Activity | Mach host statistics, `ProcessInfo`, `FileManager`, and `NSRunningApplication` | No new permission prompt. Quit/force/bulk actions require explicit user action; destructive actions have confirmation/protection where appropriate. |
| Storage Cleaner | Bounded `FileManager` scans, the installed-app catalog, CryptoKit SHA-256, a native folder picker, and Trash | Real-user Library discovery begins only when Storage Cleaner opens and reuses the disclosed temporary uninstall exception. Duplicate discovery reads one explicitly selected ephemeral folder. No results, paths, hashes, or grants are persisted/logged/uploaded; at least one duplicate copy remains and every Trash batch requires confirmation. |
| Microphone Control | Core Audio default-input and mute properties | No audio stream, recording, account, persistence, input entitlement, usage string, or TCC prompt. Device details are not logged. Unsupported devices remain unchanged. |
| Window Switcher prototype | Infrastructure contracts, in-memory adapters, and unregistered public-API app-target prototypes | Not a usable sandboxed workflow. Production registration, cross-application Accessibility/control, active event filtering, Dock traversal, Quit, and thumbnail requests remain disabled. Any future privileged runtime must keep titles, images, queries, ordering, and pointer/input state ephemeral and continue to forbid private Dock, Spaces, WindowServer, media, and blur APIs. |
| Window Layouts | Accessibility API and native screen/window geometry | Accessibility is requested contextually when applying a layout. Denial is recoverable in System Settings. Only the previously focused external target is acted on. |
| Offline tools | Unicode metadata, Dictionary Services, `NSFontManager`, `NSColorSampler`, local transforms | No network or account. The color sampler is a system-controlled explicit picker, not general screen capture. |
| File Search | FileManager/FSEvents, system SQLite FTS5, Quick Look, PDFKit, and bounded Vision OCR | Only user-selected security-scoped folders are indexed. Index/query/path/content data stays local and is not logged. Mutations are explicit. |
| Markdown Preview | SwiftUI/AppKit, a dependency-free shared renderer, nonpersistent WebKit, and a sandboxed Quick Look extension | Reads only an explicitly picked/dropped file or Finder-supplied preview URL. Source and local images are bounded, document HTML/scripts and implicit network loads are blocked, and the App Group stores renderer settings only. No TCC prompt, upload, content/path logging, or code execution. |
| Recent Downloads | Actor-confined `FileManager` metadata scan plus native workspace/Finder/pasteboard actions | A read-only Downloads entitlement grants top-level metadata access without a prompt. File contents are not read, filenames/paths are not logged, and no mutation action exists. |
| App management | `NSWorkspace`, `NSRunningApplication`, Finder integration, and Trash | Finder Get Info may request Finder Automation on first use. Uninstall and Storage Cleaner Library access is limited by disclosed sandbox exceptions, bounded review-first discovery, and partial-failure reporting. |
| Registered application/tool tags and hotkeys | UserDefaults for non-secret user tags/settings and Carbon global shortcuts | Built-in tags remain definition metadata. No Accessibility permission is needed for Carbon hotkeys. Typed commands do not own shortcuts, and secrets must never be stored in this settings schema. |
| Command Wheel | Carbon shortcuts, active-session pointer sampling, AppKit/SwiftUI radial panel, versioned profile JSON, and bounded command-outcome history | No new TCC prompt, event tap, or global keyboard monitor. Profiles exclude secrets; history excludes arguments, queries, pointer paths, clipboard/file contents, credentials, and private URLs. Selected commands retain their own permission boundaries. |

Calendar and Contacts permission plumbing exists for future work, but there is no schedule, meeting,
people-search, or reminders application. The disabled Window Switcher prototype does not request
Screen Recording or Input Monitoring. Camera, Microphone capture, Location, Notifications, Bluetooth
control, and cloud/account permissions remain unrequested. `ExtensionKit` still contains
experimental manifest models only; it does not load third-party code or extensions.
