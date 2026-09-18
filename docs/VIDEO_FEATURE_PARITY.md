# Video feature parity: 102 capabilities

This is the requirements and evidence ledger for the current request to bring every capability
demonstrated in [102 Things You Can Do With Raycast 2.0](https://www.youtube.com/watch?v=G7_7F_FBqQE)
to Commandly and improve Commandly's presentation. It supersedes the older 101-item checklist in
[NATIVE_FEATURES.md](NATIVE_FEATURES.md) **for this request**. A feature is not removed from this
scope because it requires an external integration, credentials, another client platform, a backend,
or a new architecture decision.

Initial source audit: September 14, 2026. The working tree already contained substantial uncommitted
feature work when this audit began. Entries below describe the inspected working tree; they do not
attribute those existing changes to this task.

The first integrated tranche delivers clipboard pins/names/collections, library tags and richer
snippet templates, image conversion, and shared keyboard/menu improvements. `make verify` passed
on September 14, 2026 at 14:26 EDT. Live acceptance is ongoing and has found issues beyond unit
coverage; see the ledger below. The initial evidence descriptions deliberately preserve the starting
gaps. Calendar scheduling, installed-app aliases, and explicit OCR/QR extraction passed the second
aggregate verification. Camera, Confetti, and folder browsing are being validated in the third tranche.

## Evidence and status rules

The inventory is paraphrased from the video's retrieved English automatic captions, with timestamps
rounded to the corresponding spoken cue. The final cue is **Confetti**, as identified by the video's
official chapter; the automatic caption misrecognizes it. This ledger does not reproduce the
transcript or copy the reference product's assets, code, copy, or exact visual layout.

The audit numbers normalize combined statements into individual requirements: Hermes and OpenClaw
are separate integrations; Mac-to-Mac, Mac-to-PC, and iPhone are separate sync targets; snippet and
Quicklink tagging are separate requirements. The two note cues are retained separately pending
visual confirmation of the second cue. These choices produce 102 requirements without treating
the older checklist as the video's contents. Later frame-by-frame inspection resolved the second
note cue as Notes on iOS; see the third tranche's clarification.

- **Implemented**: a discoverable workflow and concrete implementation are present in the inspected
  source. This is implementation evidence, not a claim that its tests or live behavior passed today.
- **Partial**: a concrete subset is present; the last column identifies the remaining behavior.
- **Missing**: no matching usable workflow was found. Contracts, placeholders, adjacent utilities,
  and the ability to launch another installed app do not establish feature completion.
- **Unverified**: code or a reference cue exists, but a material behavior or interpretation cannot
  be established from the evidence inspected. A live system integration must not be called working
  solely because a mock-backed model test exists.

The evidence keys link to exact source and test files below. **Every initial row still requires
appropriate current verification.** Referenced tests were located and inspected, not run by this
documentation audit. Missing workflows have no matching feature test; an adjacent test is explicitly
identified as a starting point rather than proof. A successful aggregate build alone cannot close
permission-dependent, external-service, multi-device, or visual acceptance checks.

## Timestamped inventory

| # | Cue | Required capability | Initial status | Source and test evidence; remaining acceptance work |
|---|---|---|---|---|
| 1 | 0:02 | Launch an installed application | Implemented | [APP](#app--installed-applications). Root search uses installed bundle metadata and the workspace opener. Exercise keyboard search, Return, missing apps, and launch failure on the built app. |
| 2 | 0:06 | Find files by name | Implemented | [FILE](#file--authorized-file-search-and-actions). Indexed name search and bounded root results exist. Verify authorized folders, cancellation, and opening a selected result. |
| 3 | 0:10 | Find files by their contents | Implemented | [FILE](#file--authorized-file-search-and-actions). Bounded text/PDF/image extraction feeds the local index. Verify supported formats, reindexing, and inaccessible files; this is not universal content extraction. |
| 4 | 0:14 | Navigate folders to locate a file | Partial | [FILE](#file--authorized-file-search-and-actions). Search results can open an enclosing folder in Finder. There is no navigable in-Commandly directory browser with parent/child history. |
| 5 | 0:20 | Retain and search clipboard history | Implemented | [CLIP](#clip--clipboard-and-image-text). Captures text, images, and file URLs, with search and copy. History currently ends when Commandly quits; exercise that lifetime and sensitive-item exclusions. |
| 6 | 0:24 | Organize clipboard items | Partial | [CLIP](#clip--clipboard-and-image-text). Type filters and date grouping exist. User-defined organization, collections, and pin/order controls are absent; compare the organization shown in the video before closing. |
| 7 | 0:28 | Give copied items custom names | Missing | [CLIP](#clip--clipboard-and-image-text). Entry metadata has no editable display-name field, and the editor changes only text content. No rename test exists. |
| 8 | 0:32 | Edit clipboard content | Implemented | [CLIP](#clip--clipboard-and-image-text). Text entries support editing, then copy the saved text. Image/file mutation is absent; verify which types the reference edits. |
| 9 | 0:37 | Search and copy animated GIFs | Missing | [REG](#reg--registration-and-discovery) has no GIF provider/application. Needs remote catalog/search, preview, attribution/terms handling, and usable copy/download; no matching tests. |
| 10 | 0:40 | Search and copy emoji | Implemented | [OFFLINE](#offline--local-utilities). Curated local Unicode-name search and copy exist. Verify keyboard navigation and catalog/search coverage; the current catalog is not the complete emoji standard. |
| 11 | 0:43 | Find emoji through AI | Missing | [OFFLINE](#offline--local-utilities), [AI](#ai--provider-connections-and-finder-agent). The provider runtime is not connected to emoji search. No AI emoji test exists. |
| 12 | 0:47 | Search a Slack workspace's emoji | Missing | [REG](#reg--registration-and-discovery). No Slack account/emoji adapter, authentication, workspace choice, or custom emoji cache exists. Needs an explicitly connected account and integration tests. |
| 13 | 0:52 | Dictate into the current application | Missing | [PERM](#perm--permissions-and-platform-boundaries). No audio capture, speech recognition, transcription, or focused-field insertion workflow exists. Microphone Control only toggles a device mute property. |
| 14 | 0:57 | Dictate in multiple languages | Missing | [PERM](#perm--permissions-and-platform-boundaries), [AI](#ai--provider-connections-and-finder-agent) are adjacent seams only. Needs language selection/detection, supported-language reporting, and multilingual transcription tests. |
| 15 | 1:01 | Apply different dictation writing styles | Missing | [AI](#ai--provider-connections-and-finder-agent). No dictation style profiles, text rewriting pipeline, or preview/correction UX exists. No matching tests. |
| 16 | 1:07 | Review earlier dictations | Missing | [PERM](#perm--permissions-and-platform-boundaries). No dictation model, history store, retention controls, or history browser exists. Needs privacy-conscious persistence and deletion tests. |
| 17 | 1:11 | Apply 58 window arrangement presets | Unverified | [WINDOW](#window--window-layouts). Exactly 58 presets, a model, and an Accessibility adapter exist. The shipping app is sandboxed; cross-application control must be verified in its signed distribution configuration before claiming it works. |
| 18 | 1:16 | Create additional window arrangement commands | Partial | [WINDOW](#window--window-layouts). Custom normalized rectangles persist and can be applied inside Window Layouts. Each layout is not an individually discoverable command/hotkey, and live control shares row 17's verification gap. |
| 19 | 1:22 | Remap Caps Lock to a Hyper modifier | Partial | [Keyboard Triggers](KEYBOARD_TRIGGERS.md). Configured physical Caps observer plus session CG event tap implements Hyper; explicit helper/input opt-in. Source compiled and focused reducer tests pass; supported hardware/native input acceptance pending. |
| 20 | 1:25 | Preserve normal Caps Lock behavior with Hyper enabled | Partial | [Keyboard Triggers](KEYBOARD_TRIGGERS.md). Short solitary Caps tap preserves lock; chords/long holds do not toggle. Reset, timeout and stop paths release Hyper. Native HID/CG ordering remains pending. |
| 21 | 1:29 | Give installed apps searchable nicknames | Missing | [APP](#app--installed-applications), [KEYS](#keys--shortcuts-and-discovery-preferences). Installed-app preferences contain favorites, disabling, auto-quit, and ranking, but no aliases. Tags for registered Commandly applications are a separate capability. |
| 22 | 1:33 | Give commands searchable nicknames | Implemented | [KEYS](#keys--shortcuts-and-discovery-preferences). Registered applications/tools accept custom search tags and preserve legacy aliases. Verify immediate discovery, persistence, and disabled parent behavior. |
| 23 | 1:38 | Save reusable text snippets | Implemented | [LIB](#lib--snippets-notes-and-quicklinks). Persistent typed items, search, editing, explicit copy, and sharing exist. Automatic text expansion into other apps is not present and must be checked against the demonstration. |
| 24 | 1:43 | Expand dynamic snippet placeholders | Partial | [LIB](#lib--snippets-notes-and-quicklinks). Only every `{{clipboard}}` occurrence is replaced on explicit copy. No date, cursor, argument, selection, or other dynamic placeholder engine is implemented. |
| 25 | 1:47 | Associate a keyword with an emoji | Partial | [LIB](#lib--snippets-notes-and-quicklinks). Emoji Keyword items can be searched and copied. Typing a keyword in another app does not automatically expand it; verify the video's insertion behavior. |
| 26 | 1:52 | Ask a quick, disposable AI question | Partial | [AI](#ai--provider-connections-and-finder-agent). Finder AI has an in-memory conversation using the selected provider. There is no general quick-AI query surface independent of the Finder application. |
| 27 | 1:55 | Continue an AI question with follow-ups | Partial | [AI](#ai--provider-connections-and-finder-agent). Finder AI retains conversation turns for its active session. General quick-chat follow-up UX and session continuity beyond that application are absent. |
| 28 | 1:59 | Capture a quick note from anywhere | Implemented | [LIB](#lib--snippets-notes-and-quicklinks), [KEYS](#keys--shortcuts-and-discovery-preferences). New Quick Note is a registered tool with a configurable shortcut and persistent local save. Verify focus, keyboard entry, save errors, and reopening the note. |
| 29 | 2:05 | Use notes on iPhone | Unverified | Initial [LIB](#lib--snippets-notes-and-quicklinks) audit could not resolve the caption's second context. Frame inspection at 2:06 later confirmed Notes on iOS. An actual iPhone notes client is still missing; see the third-tranche clarification. |
| 30 | 2:07 | Calculate basic arithmetic | Implemented | [CALC](#calc--calculator-and-history). Deterministic arithmetic and root result/copy UI exist. Run calculator tests and exercise editing/copy without losing focus. |
| 31 | 2:09 | Calculate advanced expressions | Implemented | [CALC](#calc--calculator-and-history). Scientific, statistics, finance, and other evaluators exist. Test demonstrated expressions and precise errors; broad evaluator coverage does not establish symbolic-algebra support. |
| 32 | 2:12 | Convert units | Implemented | [CALC](#calc--calculator-and-history). Unit registries and ambiguity handling exist. Verify the demonstrated unit pairs, localization, and numeric precision. |
| 33 | 2:14 | Calculate dates | Implemented | [CALC](#calc--calculator-and-history). Calendar-aware relative dates and differences exist. Verify current date, DST, month-end, and time-zone cases. |
| 34 | 2:16 | Calculate percentages and discounts | Implemented | [CALC](#calc--calculator-and-history). Percent/finance evaluators are present. Validate the specific reference expression shapes and copying formatted answers. |
| 35 | 2:19 | Browse calculation history | Partial | [CALC](#calc--calculator-and-history). Stores at most 100 explicitly used successful results in memory. It does not retain all calculated expressions or survive relaunch. |
| 36 | 2:23 | Launch favorite installed apps with hotkeys | Missing | [APP](#app--installed-applications), [KEYS](#keys--shortcuts-and-discovery-preferences). Registered Commandly tool shortcuts and Command Wheel app assignments exist; direct configurable hotkeys for arbitrary installed `.app` results do not. |
| 37 | 2:28 | Invoke a command with a single-key trigger | Partial | [Keyboard Triggers](KEYBOARD_TRIGGERS.md). Settings assigns registered argument-free commands or file Quicklinks to finite single keys, with editable/unknown-context pass-through for printable keys. Native acceptance pending. |
| 38 | 2:34 | Open a folder with a double-tap trigger | Partial | [Keyboard Triggers](KEYBOARD_TRIGGERS.md). Settings assigns saved file Quicklinks to clean double modifier taps; intervening chords cancel. Native Finder opening via that trigger remains pending. |
| 39 | 2:40 | Search screenshots using text in the image | Partial | [FILE](#file--authorized-file-search-and-actions), [CLIP](#clip--clipboard-and-image-text). Bounded on-device OCR can find indexed screenshot images. There is no screenshot-specific catalog or guarantee that all screenshots are indexed/OCRed. |
| 40 | 2:44 | View an upcoming schedule | Missing | [REG](#reg--registration-and-discovery), [PERM](#perm--permissions-and-platform-boundaries). My Schedule is a placeholder. Calendar permission state alone is not an event store, agenda model, or usable calendar UI. |
| 41 | 2:47 | Join a meeting from the schedule | Missing | [PERM](#perm--permissions-and-platform-boundaries). No event ingestion, meeting URL detection, countdown, or meeting-opening command exists. Needs a real schedule and safe URL handling. |
| 42 | 2:52 | Join scheduled meetings automatically | Missing | [PERM](#perm--permissions-and-platform-boundaries). No opt-in meeting scheduler, preference, wake/restart behavior, or prevention of duplicate joins exists. No matching tests. |
| 43 | 2:55 | Preview the camera before joining a meeting | Missing | [PERM](#perm--permissions-and-platform-boundaries). No camera preview or contextual Camera permission flow exists. Test device loss, denial, mirroring, and session cleanup when implemented. |
| 44 | 3:00 | Capture a selfie | Missing | [PERM](#perm--permissions-and-platform-boundaries). No camera capture, image review, copy, or export workflow exists. No matching tests. |
| 45 | 3:04 | Save website Quicklinks | Implemented | [LIB](#lib--snippets-notes-and-quicklinks). HTTP/HTTPS values are validated, persisted, and explicitly opened. Verify malformed URLs and target-browser failures. |
| 46 | 3:07 | Save file Quicklinks | Implemented | [LIB](#lib--snippets-notes-and-quicklinks). File URLs and absolute/home-relative paths are accepted. Verify sandbox access, moved files, and actionable failure recovery; a path alone is not a persistent authorization grant. |
| 47 | 3:10 | Save folder Quicklinks | Implemented | [LIB](#lib--snippets-notes-and-quicklinks). Folder paths/file URLs use the native opener. Verify protected/moved folders and keyboard discovery. |
| 48 | 3:12 | Save application deep links | Implemented | [LIB](#lib--snippets-notes-and-quicklinks). Custom URL schemes are accepted while unsafe script/data schemes are rejected. Verify handler availability and opening the intended destination. |
| 49 | 3:17 | Start a screen recording | Missing | [PERM](#perm--permissions-and-platform-boundaries). No production recording session, controls, audio choices, or export exists. The disabled Window Switcher thumbnail prototype does not provide this capability. |
| 50 | 3:20 | Take a screenshot | Missing | [PERM](#perm--permissions-and-platform-boundaries). No production screenshot selection/capture/copy/save workflow exists. Screen-thumbnail contracts do not count as a screenshot command. |
| 51 | 3:24 | Annotate a screenshot through CleanShot | Missing | [REG](#reg--registration-and-discovery). No CleanShot handoff adapter or annotation workflow exists. Keep this integration requirement; verify its documented API/installed-app prerequisite before implementation. |
| 52 | 3:28 | Chat with a choice of current AI models | Partial | [AI](#ai--provider-connections-and-finder-agent). BYOK provider/model setup and Finder AI exist. General chat, within-conversation model selection, and verified current provider/model compatibility remain incomplete. |
| 53 | 3:32 | Have AI perform actions | Partial | [AI](#ai--provider-connections-and-finder-agent). Finder AI has bounded read tools and locally approved exact file mutations. General application actions, broader integrations, and the full demonstrated agent scope are absent. |
| 54 | 3:37 | Quit an application gracefully | Unverified | [SYSTEM](#system--running-applications-and-system-actions). System Activity calls the native termination API. Verify actual cross-process behavior in the signed sandboxed app, refusal, and unsaved-document handling. |
| 55 | 3:39 | Force quit an application | Unverified | [SYSTEM](#system--running-applications-and-system-actions). Confirmation/model/native adapter exist. Verify signed sandbox behavior and protected targets without using live user applications as test victims. |
| 56 | 3:41 | Quit inactive applications automatically | Unverified | [APP](#app--installed-applications). Five-minute background idle policy and mock-backed tests exist. Verify real termination in the distribution configuration and correct foreground/running-state changes. |
| 57 | 3:47 | Quit all eligible applications at once | Unverified | [SYSTEM](#system--running-applications-and-system-actions). Bulk confirmation protects Commandly, Finder, and the frontmost app. Verify actual sandbox behavior, partial failures, and eligibility on controlled test apps. |
| 58 | 3:49 | Correct grammar and spelling | Missing | [AI](#ai--provider-connections-and-finder-agent), [OFFLINE](#offline--local-utilities). No dedicated correction command, current-selection acquisition, result comparison, or replace/copy workflow exists. Text-case conversion is not grammar correction. |
| 59 | 3:55 | Apply a quick text correction | Missing | [AI](#ai--provider-connections-and-finder-agent). No one-action quick-fix workflow exists. Visual inspection must establish its exact input and replacement behavior before defining acceptance tests. |
| 60 | 3:59 | Uninstall an application with review | Implemented | [APP](#app--installed-applications). Discovers app/support candidates, reviews selection, then moves chosen items to Trash with partial failure reporting. Verify grants and filesystem outcomes using controlled fixtures. |
| 61 | 4:03 | Begin a focus session | Partial | [TIMER](#timer--timers-and-focus). A 25-minute timer is present. No website/application blocking, distraction policy, or complete focus-session lifecycle is implemented; verify the video's focus behavior. |
| 62 | 4:08 | Temporarily leave focus mode | Partial | [TIMER](#timer--timers-and-focus). Timers can pause and a five-minute break can be started. There is no focus restriction bypass/unfocus state or automatic restoration of a focus policy. |
| 63 | 4:13 | Discover and install an extension ecosystem | Missing | [EXT](#ext--extension-foundation). ExtensionKit validates metadata only and explicitly does not load code. No catalog, install/update/uninstall, permissions, runtime, or compatible third-party ecosystem exists. |
| 64 | 4:18 | Build extensions with AI assistance | Missing | [EXT](#ext--extension-foundation), [AI](#ai--provider-connections-and-finder-agent). No extension-generation workspace, preview, validation, packaging, or installation exists. Requires an original supported extension runtime first. |
| 65 | 4:23 | Develop extensions manually | Missing | [EXT](#ext--extension-foundation). Manifest contracts are not a developer SDK/runtime. Needs documented APIs, templates, packaging, permission isolation, diagnostics, and developer tests. |
| 66 | 4:26 | Check the local time at a destination | Implemented | [CALC](#calc--calculator-and-history). Date-aware time-zone queries and IANA-zone resolution exist. Verify the video's city syntax, ambiguity, and DST behavior. |
| 67 | 4:30 | Calculate the time difference between cities | Implemented | [CALC](#calc--calculator-and-history). Time-zone/difference evaluators exist. Verify both city orderings, DST transitions, non-whole-hour offsets, and the demonstrated phrase. |
| 68 | 4:34 | Change a display's resolution | Missing | [REG](#reg--registration-and-discovery), [PERM](#perm--permissions-and-platform-boundaries). No display-mode browser, apply/revert workflow, or safe recovery timer exists. No matching tests. |
| 69 | 4:37 | Convert image formats | Partial | Implementation in progress; not verified. Initial [IMAGE](#image--existing-image-processing-boundary) only exported a background-removal PNG. General file selection, format/options, preview, destination, metadata handling, and cancellation are being implemented separately. |
| 70 | 4:43 | Ask AI to convert an image | Missing | [AI](#ai--provider-connections-and-finder-agent), [IMAGE](#image--existing-image-processing-boundary). The Finder tool catalog has no image transformation tool. Needs a typed approved conversion plan and the concrete converter from row 69. |
| 71 | 4:47 | Translate text with source-language detection | Missing | [OFFLINE](#offline--local-utilities), [AI](#ai--provider-connections-and-finder-agent). No translation service/application exists. Dictionary definitions and asking arbitrary text in Finder AI do not establish this workflow. |
| 72 | 4:51 | Translate between chosen languages | Missing | [OFFLINE](#offline--local-utilities). No source/target language selection, supported-language reporting, translation adapter, or tests exist. |
| 73 | 4:56 | Quickly check a word's translation | Missing | [OFFLINE](#offline--local-utilities). Installed Dictionary lookup gives a definition, not an explicit translation command. Needs a focused word-translation entry point. |
| 74 | 5:00 | Copy the current Finder path | Partial | [FILE](#file--authorized-file-search-and-actions). A selected File Search result's path can be copied. No command reads the currently selected item/current folder in Finder. |
| 75 | 5:02 | Chat with a Hermes agent | Missing | [AI](#ai--provider-connections-and-finder-agent). No Hermes connector, agent/session selection, authentication, or streaming conversation bridge exists. No matching integration tests. |
| 76 | 5:04 | Chat with an OpenClaw agent | Missing | [AI](#ai--provider-connections-and-finder-agent). No OpenClaw connector or session bridge exists. Keep separate acceptance for discovery, connection lifecycle, and tool/approval behavior. |
| 77 | 5:07 | Search and preview fonts | Implemented | [OFFLINE](#offline--local-utilities). Installed font families can be searched/previewed/copied. Verify long names, keyboard selection, and missing fonts. |
| 78 | 5:10 | Pick a screen color | Implemented | [OFFLINE](#offline--local-utilities). Explicit native `NSColorSampler` action and direct shortcut tool exist. Verify cancel, screen selection, output, and focus restoration on the built app. |
| 79 | 5:13 | Convert colors across formats | Partial | [OFFLINE](#offline--local-utilities). Parses HEX/RGB/RGBA and emits HEX, RGB/RGBA, HSL. Other spaces and bidirectional support are incomplete; inspect the demonstrated format list. |
| 80 | 5:17 | Sync data between Macs | Missing | [SYNC](#sync--local-persistence-only). Preferences/library are local. No account, encrypted sync transport, conflict resolution, deletion propagation, or multi-Mac verification exists. |
| 81 | 5:19 | Sync data between Mac and PC | Missing | [SYNC](#sync--local-persistence-only). No Windows client or common cross-platform sync contract exists. Mac-only persistence cannot satisfy this requirement. |
| 82 | 5:21 | Sync data with an iPhone | Missing | [SYNC](#sync--local-persistence-only). No iPhone client, shared schema, or sync service exists. Needs actual multi-device acceptance, not only serialized model tests. |
| 83 | 5:23 | Tag snippets | Partial | Implementation in progress; not verified. Initial [LIB](#lib--snippets-notes-and-quicklinks) schema had no tags. Item schema, editor, filtering, and migration must be checked; application discovery tags do not count. |
| 84 | 5:27 | Tag Quicklinks | Partial | Implementation in progress; not verified. Same item-tag work as row 83; needs Quicklink-specific round-trip and filter tests. |
| 85 | 5:30 | Keep useful items directly in the menu bar | Partial | [MENU](#menu--status-menu). Fixed launcher/settings/documentation/Shelf entries exist. No user-configured quick-access item list or per-item menu-bar application is implemented. |
| 86 | 5:33 | Browse a Notion workspace | Missing | [REG](#reg--registration-and-discovery). A saved Notion deep link opens another app but cannot browse/search a workspace. Needs authentication, API adapter, paging/search, and failure/permission tests. |
| 87 | 5:37 | Change system settings from commands | Partial | [SYSTEM](#system--running-applications-and-system-actions), [PERM](#perm--permissions-and-platform-boundaries). A microphone mute control and Settings recovery links exist. There is no general settings command catalog covering the shown controls. |
| 88 | 5:40 | Practice typing | Implemented | [OFFLINE](#offline--local-utilities). Local passage, elapsed WPM, character accuracy, completion, and reset exist. Verify real typing, corrections, paste policy, keyboard focus, and accessible feedback. |
| 89 | 5:45 | Search commands available in the current app | Missing | [REG](#reg--registration-and-discovery), [PERM](#perm--permissions-and-platform-boundaries). Registry discovery covers Commandly commands, not other applications' menu commands. Needs contextual enumeration, execution, permission handling, and app-switch invalidation. |
| 90 | 5:49 | Pin favorite app commands in that search | Missing | [APP](#app--installed-applications), [KEYS](#keys--shortcuts-and-discovery-preferences). Installed-app favorites exist; favorite foreign-app menu commands do not. Depends on row 89 and stable command identity. |
| 91 | 5:54 | Create custom AI agents | Partial | [AI_AGENTS](AI_AGENTS.md): user-authored text profiles, instructions, provider/model choices, lifecycle, and bounded local persistence. Tool execution/autonomy remain outside this text runtime. |
| 92 | 5:57 | Launch a custom AI agent with a hotkey | Implemented | [AI_AGENTS](AI_AGENTS.md): each saved agent has a stable individual launcher tool and uses existing per-tool shortcut settings; catalog refresh updates discovery and shortcuts after save/delete. |
| 93 | 6:00 | Give AI a persistent user profile | Implemented | [AI_AGENTS](AI_AGENTS.md): editable/deletable explicit local profile, included only for agents with Use My Profile enabled. |
| 94 | 6:03 | Let AI retain useful memory of activity | Partial | [AI_AGENTS](AI_AGENTS.md): explicit manual or reviewed chat-excerpt memory with provenance, per-agent scope, enable/disable, editing and deletion. No automatic activity collection. |
| 95 | 6:07 | Extract readable text from images | Partial | [CLIP](#clip--clipboard-and-image-text), [FILE](#file--authorized-file-search-and-actions). Vision OCR supplies search text and the clipboard image preview supports Live Text selection. No universal explicit OCR tool/output review exists; verify the video's image-input/copy route. |
| 96 | 6:11 | Decode QR codes | Missing | [CLIP](#clip--clipboard-and-image-text). No barcode request, decoded-payload model, or copy/open review exists. Live Text is configured for text/visual lookup; it is not evidence of a QR workflow. |
| 97 | 6:15 | Add reusable skills to AI agents | Implemented | [AI_AGENTS](AI_AGENTS.md): bounded text-only skill authoring, JSON import/export, discovery, per-agent enablement, and instruction loading; skills cannot execute code or grant capabilities. |
| 98 | 6:18 | Extend AI with additional capabilities/tools | Partial | [AI](#ai--provider-connections-and-finder-agent). Typed built-in Finder tools exist. Users cannot add tool integrations or external capability providers; no install/configuration/permissions UI exists. |
| 99 | 6:21 | Let an agent continue work autonomously | Partial | [AI](#ai--provider-connections-and-finder-agent). A bounded conversation tool loop can perform permitted reads and locally approved exact mutations. Persistent tasks, background operation, and the full demonstrated autonomy are absent. |
| 100 | 6:28 | Share a full screen with AI as context | Missing | [AI](#ai--provider-connections-and-finder-agent), [PERM](#perm--permissions-and-platform-boundaries). No explicit screen selection, preview, bounded visual attachment, or provider disclosure workflow exists. |
| 101 | 6:34 | Share a selected screen region with AI | Missing | [AI](#ai--provider-connections-and-finder-agent), [PERM](#perm--permissions-and-platform-boundaries). No region selector or cropped visual context route exists. Needs explicit review and cancellation, not automatic ambient capture. |
| 102 | 6:41 | Trigger a confetti celebration | Partial | [CELEBRATE](#celebrate--existing-onboarding-effect). A one-time onboarding success effect exists. No reusable discoverable confetti command or general celebration surface exists. |

## Source and test evidence index

These links are implementation starting points. A test listed here may cover only a deterministic
model, parser, adapter double, or adjacent behavior. None grants access to real user data or proves
that a live permission/service/platform integration works.

### REG — registration and discovery

- Source: [LauncherApplicationRegistry.swift](../Commandly/Composition/LauncherApplicationRegistry.swift),
  [LauncherApplicationDefinition.swift](../Commandly/Composition/LauncherApplicationDefinition.swift),
  [LauncherModels.swift](../Commandly/Scenes/Launcher/LauncherModels.swift),
  [AppRuntime.swift](../Commandly/Application/AppRuntime.swift).
- Tests: [CommandlyTests.swift](../CommandlyTests/CommandlyTests.swift),
  [SharedCommandExecutionTests.swift](../CommandlyTests/SharedCommandExecutionTests.swift),
  [LauncherInlineSearchTests.swift](../CommandlyTests/LauncherInlineSearchTests.swift).
- Boundary: [ADR-0010](decisions/ADR-0010-application-tools-tags-and-inline-discovery.md).
  A new feature needs a real owning application/tool and documentation, not another placeholder.

### APP — installed applications

- Source: [WorkspaceApplicationServices.swift](../Commandly/Services/WorkspaceApplicationServices.swift),
  [ApplicationPreferencesStore.swift](../Commandly/Services/ApplicationPreferencesStore.swift),
  [LauncherViewModel+ApplicationActions.swift](../Commandly/Scenes/Launcher/LauncherViewModel+ApplicationActions.swift),
  [AutoQuitService.swift](../Commandly/Services/AutoQuitService.swift),
  [WorkspaceApplicationUninstallDiscoverer.swift](../Commandly/Services/WorkspaceApplicationUninstallDiscoverer.swift),
  [ApplicationUninstallViewModel.swift](../Commandly/Scenes/Launcher/Commands/Uninstall/ApplicationUninstallViewModel.swift).
- Tests: installed application launch/search, favorite/disable, uninstall, and auto-quit cases in
  [CommandlyTests.swift](../CommandlyTests/CommandlyTests.swift), plus
  [ApplicationCacheTests.swift](../CommandlyTests/ApplicationCacheTests.swift).

### FILE — authorized file search and actions

- Source: [PersistentFileSearchService.swift](../Commandly/Services/FileSearch/PersistentFileSearchService.swift),
  [FileIndexDatabase.swift](../Commandly/Services/FileSearch/FileIndexDatabase.swift),
  [FileContentExtractor.swift](../Commandly/Services/FileSearch/FileContentExtractor.swift),
  [FileSearchViewModel.swift](../Commandly/Scenes/Launcher/Commands/FileSearch/FileSearchViewModel.swift).
- Tests: file-index, scope, extraction, native-action, and ten-thousand-record performance cases in
  [CommandlyTests.swift](../CommandlyTests/CommandlyTests.swift),
  [FileIndexLifecycleTests.swift](../CommandlyTests/FileIndexLifecycleTests.swift),
  [LauncherInlineSearchTests.swift](../CommandlyTests/LauncherInlineSearchTests.swift).
- Boundary: [FILE_SEARCH.md](FILE_SEARCH.md). Filename/content/path search works within authorized
  indexed roots; it does not establish navigation of every filesystem location.

### CLIP — clipboard and image text

- Source: [ClipboardHistoryStore.swift](../Commandly/Services/ClipboardHistoryStore.swift),
  [ClipboardHistoryViewModel.swift](../Commandly/Scenes/Launcher/Commands/Clipboard/ClipboardHistoryViewModel.swift),
  [VisionClipboardContentEnricher.swift](../Commandly/Services/Clipboard/VisionClipboardContentEnricher.swift),
  [ClipboardLiveTextImageView.swift](../Commandly/Scenes/Launcher/Commands/Clipboard/ClipboardLiveTextImageView.swift).
- Tests: [ClipboardEditingTests.swift](../CommandlyTests/ClipboardEditingTests.swift), clipboard
  filtering/copy/enrichment/lifecycle cases in [CommandlyTests.swift](../CommandlyTests/CommandlyTests.swift),
  [LauncherInlineSearchTests.swift](../CommandlyTests/LauncherInlineSearchTests.swift).

### LIB — snippets, notes, and Quicklinks

- Source: [ProductivityLibraryItem.swift](../Commandly/Services/ProductivityLibrary/ProductivityLibraryItem.swift),
  [ProductivityLibraryStore.swift](../Commandly/Services/ProductivityLibrary/ProductivityLibraryStore.swift),
  [ProductivityLibraryViewModel.swift](../Commandly/Scenes/Launcher/Commands/ProductivityLibrary/ProductivityLibraryViewModel.swift),
  [ProductivityLibraryApplication.swift](../Commandly/Scenes/Launcher/Applications/ProductivityLibraryApplication.swift).
- Tests: [ProductivityLibraryTests.swift](../CommandlyTests/ProductivityLibraryTests.swift), focused
  tool resolution in [SharedCommandExecutionTests.swift](../CommandlyTests/SharedCommandExecutionTests.swift).
- Current schema has no item tags, expansion keyword trigger, or multi-device identity.

### KEYS — shortcuts and discovery preferences

- Source: [ApplicationHotkeyMonitor.swift](../Commandly/Services/ApplicationHotkeyMonitor.swift),
  [RuntimeGlobalShortcutCatalog.swift](../Commandly/Services/RuntimeGlobalShortcutCatalog.swift),
  [LauncherApplicationPreferencesStore.swift](../Commandly/Services/LauncherApplicationPreferencesStore.swift),
  [ApplicationHotkeyRecorder.swift](../Commandly/Scenes/Settings/Components/ApplicationHotkeyRecorder.swift).
- Tests: [GlobalShortcutMonitorTests.swift](../CommandlyTests/GlobalShortcutMonitorTests.swift),
  shortcut validation, custom tags, and alias persistence cases in
  [CommandlyTests.swift](../CommandlyTests/CommandlyTests.swift).
- Registered Commandly tool shortcuts do not imply arbitrary installed-app, single-key,
  double-tap, Hyper-key, or text-expansion support.

### WINDOW — window layouts

- Source: [WindowLayoutModels.swift](../Commandly/Services/WindowLayouts/WindowLayoutModels.swift),
  [AccessibilityWindowLayoutService.swift](../Commandly/Services/WindowLayouts/AccessibilityWindowLayoutService.swift),
  [WindowLayoutsApplication.swift](../Commandly/Scenes/Launcher/Applications/WindowLayoutsApplication.swift).
- Tests: [WindowLayoutsApplicationTests.swift](../CommandlyTests/WindowLayoutsApplicationTests.swift).
- A separate Window Switcher prototype remains disabled in production under the rejected
  [ADR-0008](decisions/ADR-0008-window-switcher-public-api-boundary.md). Its tests do not establish
  usable system integration. Resolve the sandbox/distribution architecture for cross-app control
  explicitly instead of treating documented prototype limits as completed features.

### CALC — calculator and history

- Source: [CalculatorKit](../Packages/Sources/CalculatorKit),
  [CalculatorHistoryApplication.swift](../Commandly/Scenes/Launcher/Applications/CalculatorHistoryApplication.swift),
  [CalculatorResultCard.swift](../Commandly/Scenes/Launcher/Components/CalculatorResultCard.swift).
- Tests: [CalculatorKitTests](../Packages/Tests/CalculatorKitTests),
  [CalculatorHistoryApplicationTests.swift](../CommandlyTests/CalculatorHistoryApplicationTests.swift),
  root calculator presentation/action cases in [CommandlyTests.swift](../CommandlyTests/CommandlyTests.swift).
- Boundary: [CALCULATOR.md](CALCULATOR.md). Currency is an existing network exception; the
  capabilities in this video's calculator cues should be exercised with exact reference examples.

### OFFLINE — local utilities

- Source: [OfflineToolsDomain.swift](../Commandly/Services/OfflineTools/OfflineToolsDomain.swift),
  [OfflineToolsServices.swift](../Commandly/Services/OfflineTools/OfflineToolsServices.swift),
  [OfflineToolsApplication.swift](../Commandly/Scenes/Launcher/Applications/OfflineToolsApplication.swift),
  [OfflineToolsView.swift](../Commandly/Scenes/Launcher/Commands/OfflineTools/OfflineToolsView.swift).
- Tests: [OfflineToolsApplicationTests.swift](../CommandlyTests/OfflineToolsApplicationTests.swift),
  focused color-tool execution in [SharedCommandExecutionTests.swift](../CommandlyTests/SharedCommandExecutionTests.swift).
- Covers emoji, text case, colors, Dictionary, installed fonts, and typing. Does not cover GIFs,
  translation, grammar correction, Slack emoji, dictation, or QR decoding.

### AI — provider connections and Finder agent

- Source: [AIKit](../Packages/Sources/AIKit),
  [AISettingsModel.swift](../Commandly/Scenes/Settings/AISettingsModel.swift),
  [AIConnectionStore.swift](../Commandly/Services/AI/AIConnectionStore.swift),
  [KeychainSecureStore.swift](../Commandly/Services/AI/KeychainSecureStore.swift),
  [FinderAIViewModel.swift](../Commandly/Scenes/Launcher/Commands/FinderAI/FinderAIViewModel.swift),
  [FinderAIToolExecutor.swift](../Commandly/Scenes/Launcher/Commands/FinderAI/FinderAIToolExecutor.swift),
  [FinderAIWorkspaceService.swift](../Commandly/Services/AI/Finder/FinderAIWorkspaceService.swift).
- Tests: [AIKitTests](../Packages/Tests/AIKitTests),
  [AISettingsModelTests.swift](../CommandlyTests/AISettingsModelTests.swift),
  [FinderAIViewModelTests.swift](../CommandlyTests/FinderAIViewModelTests.swift),
  [FinderAIToolExecutorTests.swift](../CommandlyTests/FinderAIToolExecutorTests.swift),
  [FinderAIWorkspaceTests.swift](../CommandlyTests/FinderAIWorkspaceTests.swift).
- Boundary: [AI.md](AI.md) and [ADR-0006](decisions/ADR-0006-byok-ai-and-finder-tool-safety.md).
  This is a bounded, session-only Finder assistant with local file approvals and a non-streaming
  initial runtime. It is not evidence for general chat history, custom agents, external agent
  connectors, persistent memory, skills, screenshots, or autonomous background work.

### SYSTEM — running applications and system actions

- Source: [NativeSystemActivityService.swift](../Commandly/Services/SystemActivity/NativeSystemActivityService.swift),
  [SystemActivityViewModel.swift](../Commandly/Scenes/Launcher/Commands/SystemActivity/SystemActivityViewModel.swift),
  [MicrophoneControlApplication.swift](../Commandly/Scenes/Launcher/Applications/MicrophoneControlApplication.swift).
- Tests: [SystemActivityApplicationTests.swift](../CommandlyTests/SystemActivityApplicationTests.swift),
  [MicrophoneControlApplicationTests.swift](../CommandlyTests/MicrophoneControlApplicationTests.swift).
- Aggregate resources and GUI-app management are implemented in source, not a full process or
  system-settings catalog. Validate cross-app termination under the actual sandbox/signing setup.

### TIMER — timers and focus

- Source: [TimerStore.swift](../Commandly/Services/Timers/TimerStore.swift),
  [TimersViewModel.swift](../Commandly/Scenes/Launcher/Commands/Timers/TimersViewModel.swift),
  [TimersApplication.swift](../Commandly/Scenes/Launcher/Applications/TimersApplication.swift).
- Tests: [TimersApplicationTests.swift](../CommandlyTests/TimersApplicationTests.swift).
- Absolute-date countdowns survive closing the launcher, not quitting Commandly. Focus and Short
  Break presets are timers; there is no restriction policy or automatic work/break cycle.

### IMAGE — existing image processing boundary

- Source: [BackgroundRemoverApplication.swift](../Commandly/Scenes/Launcher/Applications/BackgroundRemoverApplication.swift),
  [BackgroundRemoval](../Commandly/Services/BackgroundRemoval).
- Adjacent tests: [BackgroundRemoverApplicationTests.swift](../CommandlyTests/BackgroundRemoverApplicationTests.swift).
- Foreground segmentation and PNG export do not implement general image conversion, screenshot
  annotation, QR extraction, or AI image transformations.

### EXT — extension foundation

- Source: [ExtensionKit.swift](../Packages/Sources/ExtensionKit/ExtensionKit.swift).
- Adjacent tests: [ExtensionKitTests.swift](../Packages/Tests/ExtensionKitTests/ExtensionKitTests.swift).
- The source explicitly calls the metadata experimental and forbids external code loading. Real
  extension support needs an accepted runtime/security/dependency design, installable packages,
  user permissions, and original Commandly SDK/catalog workflows. A validator is not a marketplace.

### SYNC — local persistence only

- Source: [AppSettingsStore.swift](../Commandly/Services/AppSettingsStore.swift),
  [ProductivityLibraryStore.swift](../Commandly/Services/ProductivityLibrary/ProductivityLibraryStore.swift),
  [LauncherApplicationPreferencesStore.swift](../Commandly/Services/LauncherApplicationPreferencesStore.swift).
- Adjacent tests: [ProductivityLibraryTests.swift](../CommandlyTests/ProductivityLibraryTests.swift)
  and preference round-trip cases in [CommandlyTests.swift](../CommandlyTests/CommandlyTests.swift).
- There are no sync or Windows/iPhone client tests. Cross-device work remains in scope and requires
  a shared schema, account or user-chosen transport, privacy design, clients, and conflict testing.

### MENU — status menu

- Source: [StatusBarMenu.swift](../Commandly/Scenes/StatusBar/StatusBarMenu.swift).
- Adjacent tests: runtime/presentation cases in [CommandlyTests.swift](../CommandlyTests/CommandlyTests.swift).
- The menu is a fixed command list. No configurable favorite-content menu has a matching test.

### PERM — permissions and platform boundaries

- Source: [SystemPermissionService.swift](../Commandly/Services/SystemPermissionService.swift),
  [WorkspacePrivacySettingsOpener.swift](../Commandly/Services/WorkspacePrivacySettingsOpener.swift),
  [Commandly.entitlements](../Commandly/Configuration/Commandly.entitlements),
  [Info.plist](../Commandly/Configuration/Info.plist).
- Adjacent tests: [SystemPermissionServiceTests.swift](../CommandlyTests/SystemPermissionServiceTests.swift),
  permission flow cases in [CommandlyTests.swift](../CommandlyTests/CommandlyTests.swift).
- Boundary: [PERMISSIONS.md](PERMISSIONS.md), [SECURITY_MODEL.md](SECURITY_MODEL.md). A permission
  enum, Settings recovery link, or usage string is not the requested feature. New access must be
  contextual and testable with injected permission state. Missing camera/speech/screen/schedule
  workflows need implementation before live permission verification is meaningful.

### CELEBRATE — existing onboarding effect

- Source: [Onboarding](../Commandly/Scenes/Onboarding).
- Adjacent tests: `optionSpaceHotkeyConfirmsAndCelebrates` and onboarding lifecycle cases in
  [CommandlyTests.swift](../CommandlyTests/CommandlyTests.swift).
- The onboarding completion effect is not a reusable registered launcher command.

## Initial user-experience findings

1. The root placeholder catalog presents **My Schedule**, **Welcome to Commandly**, and
   **Quit Commandly** as selectable rows even though their actions only report that users must
   wait or use another surface. A dependable launcher should execute its advertised action or
   present its availability before selection. See `LauncherPlaceholderCatalog` in
   [LauncherModels.swift](../Commandly/Scenes/Launcher/LauncherModels.swift).
2. A user's installed applications and Commandly's registered applications have different
   preference models. Tags and hotkeys are exposed only for the registered hierarchy. Implementing
   rows 21 and 36 should reuse the shared typed installed-app command and conflict resolver so
   discovery, launcher actions, Command Wheel, and shortcuts remain consistent.
3. Clipboard organization and library tags require data/model/editor work. Styling the existing
   lists cannot satisfy those workflows. Adding persistent private content also needs explicit
   retention/deletion choices and migration/error tests.
4. The launcher has fixed dimensions, density/text-size preferences, a keyboard-driven selection
   model, and Reduce Motion/Reduce Transparency support. Any style pass should retain readable
   selection/hover contrast, visible focus, accessible labels, predictable Escape/Return/Command-K,
   and stable layout at all supported appearance settings. Relevant surfaces are
   [LauncherRootView.swift](../Commandly/Scenes/Launcher/LauncherRootView.swift),
   [LauncherHomeView.swift](../Commandly/Scenes/Launcher/LauncherHomeView.swift),
   [LauncherApplicationScreen.swift](../Commandly/Scenes/Launcher/Applications/LauncherApplicationScreen.swift),
   and [DesignSystem](../Packages/Sources/DesignSystem).
5. The sandboxed production configuration and native window-control/termination claims need
   reconciliation through actual signed-app verification and an explicit distribution decision.
   Registering a prototype or changing a status label does not fix a platform boundary.

## Verification and completion ledger

At initial audit, this document records **source evidence only**. No row is accepted as fully
verified video parity yet, and no aggregate test result is claimed here.

For each implementation tranche, record:

| Evidence required | What to record |
|---|---|
| Requirement | Row number(s), video timestamp, and any resolved visual ambiguity. |
| Implementation | Owning module, concrete source paths, registered entry points, and user-facing behavior. |
| Targeted verification | Exact test command/result and what it proves; mock-only boundaries remain explicit. |
| Build/aggregate verification | Current `make verify` result and any failure with attribution. |
| Live acceptance | Keyboard/pointer flows, error states, permissions, external account prerequisites, actual device/platform, and observed outcome. |
| Presentation | Screenshots or observed rendering, light/dark appearance, contrast, focus, scaling, Reduce Motion/Transparency, and VoiceOver labels. |
| Privacy and persistence | Captured data, destinations, retention/deletion behavior, secrets boundary, and cancellation/cleanup. |
| Remaining gap | Exact unmet behavior and next dependency; never silently recategorize an unimplemented request as excluded. |

Completion requires verified behavior for every requested row. An unresolved dependency remains
open and must be reported honestly; it does not fulfill that requirement. Completion does not mean the presence of
102 rows, 102 command names, a successful mock test suite, or a visual resemblance to the reference.

### Tranche 1 — September 14, 2026

- **Reference clarification, row 6:** the frame at 0:26 explicitly shows pinning clipboard entries.
  Pins therefore satisfy the demonstrated organization operation; collections are an additional
  Commandly feature. The second note cue remains ambiguous and open.
- **Rows 6–7:** clipboard organization metadata is separate from captured content. Pins sort first
  and survive ordinary history eviction while preserving a slot for new captures. Names, collections,
  and pins remain session-only. Seven `ClipboardOrganizationTests` and existing editing tests passed.
  The inline result title now uses the custom name without changing the copied UUID/content or
  adding clipboard results to autocomplete/history.
- **Rows 24, 83–84:** version-2 library items migrate version-1 data with empty tags. Tags save,
  search, and filter. Explicit snippet copy supports clipboard/date/time/datetime/UUID and named
  inputs, treats substituted content literally, and bounds UTF-8 output. Six initial template tests
  passed; two later tests cover recovery from oversized named input and Quicklink-specific tags.
  Those later tests await the next run.
- **Row 69:** Image Tools is registered with explicit selection/drop, PNG/JPEG/HEIC/TIFF output
  when supported by the native encoder, resize, quarter-turn rotation, previews, and native export.
  ImageIO/CoreGraphics processing stays off the main actor, bounds input/output dimensions and
  bytes, handles orientation, and writes fresh pixels without copying private metadata. All 13
  application/native conversion tests passed in full verification. Real picker/export acceptance
  remains open.
- **Presentation:** shared action and option menus support arrow/Return/Escape behavior, empty
  results, visible selection, and focus restoration. Semantic contrast and Reduce Motion handling
  were tightened. Three menu-selection tests passed. A real app check using isolated sample data
  confirmed keyboard snippet entry/copy/cancel, post-sheet search focus, and tag search.
- **Live defects under investigation:** selecting a different library item visually updates the
  detail but leaves stale accessible text; selection-specific view identity has been added and awaits
  retest. Opening Clipboard History and querying its accessibility tree caused a reproducible
  accessibility-label recursion crash. A containing accessibility element is being tested. These
  prevent calling the affected UI fully accepted despite the earlier aggregate pass.
- **Verification support:** Window Switcher runtime fixtures no longer install real global mouse
  monitors; a recording fake makes stale-session/outside-click tests deterministic. All 13 runtime
  tests passed. This does not change the rejected production architecture in ADR-0008.
- **Aggregate:** `make doctor` and `make verify` passed with Xcode 27 / Swift 6.4 on arm64 macOS.
  No Swift concurrency warnings remained in that pass; the AppIntents metadata tool reported its
  expected absence of an AppIntents dependency. The verification log is
  `/tmp/commandly-video-verify.log`; subsequent edits require another verification pass.

No cloud account, new system permission, real calendar, general clipboard, or user's private
library was used for the live sample-data checks. The whole 102-capability goal remains active.

### Tranche 2 — September 14, 2026

- **Aggregate verification:** `make verify` passed again; log
  `/tmp/commandly-video-verify-tranche2.log`. This included package tests, the complete app test
  suite, and the app build. Subsequent camera work, a final Schedule handoff-race regression,
  and accessibility grouping changes require another pass.
- **Row 21:** installed applications now offer Set/Edit Alias in their action menu. Alias editing
  normalizes and validates nicknames, rejects collisions, preserves concurrent preference edits,
  and keeps the canonical app identity. Search prioritizes an exact alias. Six alias tests passed,
  including launcher action/editor/discovery/cancel integration. Live alias editing remains open.
- **Rows 40–42:** My Schedule replaces the placeholder with a read-only EventKit agenda, date and
  calendar filters, contextual access/recovery, meeting-link review, exact-event revalidation, and
  explicit per-occurrence autojoin. The coordinator survives launcher dismissal, not app termination;
  it handles changes, revoked access, wake timing, cancellation, and duplicate suppression. Seventeen
  Schedule app tests and three Infrastructure tests passed. A subsequent concurrent manual/automatic
  handoff test (the eighteenth app test) still awaits rerun. The native fixture displayed upcoming
  events, completed reviewed joining through a no-op opener, and applied a date range with Down/
  Return while restoring search focus. Live Calendar grants and native meeting opening remain open.
- **Rows 95–96:** Image Tools now includes explicit Extract Text and Decode QR modes and focused
  launcher tools. Vision operates locally on bounded pixels. OCR results are editable; QR payloads
  are copied as text and web destinations require a separate review. Five native recognition,
  six inspection model, and one shared-tool routing test passed. A generated 1400×800 fixture
  produced the exact heading `COMMANDLY LOCAL TEST` and QR URL `https://example.com/commandly`
  in the running app. The URL review showed the host/full address and canceled without opening it.
- **Row 69 live acceptance:** selecting the generated image through the native picker, converting,
  reviewing, and exporting a fresh PNG succeeded. `sips` confirmed a 1400×800 PNG at
  `/tmp/commandly-image-fixtures/commandly-converted.png`. JPEG/HEIC/TIFF native codecs are covered
  by deterministic adapter tests; additional native-picker format/resize/rotation UI checks remain.
- **Rows 6–7 accessibility:** containing the Clipboard screen's accessibility children resolved the
  reproducible label-recursion crash. Pinning, naming, assigning a collection, and saving with
  Command-Return succeeded. Metadata was preserved across reopening. Additional row/detail identity
  and focus changes address stale display/AX state and await their final live retest.
- **Rows 24, 83–84:** all eight template/tag tests now pass, including oversized-input recovery,
  Quicklink tag persistence/filtering, and aggregate tag lists beyond one item's bound.
- **Search correctness:** eight deterministic confirmation cases now prevent Return from using
  a previous query's result, cancel pending intent on edits/navigation/Escape, and coalesce repeats.
  The live rapid `Image Tools` query followed immediately by Return opened the requested application.
- **Next implementation:** camera preview/selfie and an original confetti command are in progress.
  Their implementation does not change the remaining gaps elsewhere in the initial inventory.

### Tranche 3 — September 14, 2026 (verification in progress)

- **Native acceptance, rows 6–7:** renaming the isolated clipboard sample to `Meeting notes`, assigning
  `Work`, and saving with Command-Return now update the current row and its accessibility description
  immediately. Search becomes first responder after save. Pinning moves the item into a Pinned group
  immediately and exposes Unpin. No reopen is needed; the earlier stale-row gap is resolved.
- **Native acceptance, row 21:** Set Alias opens the native editor, Return saves `studio`, and typing
  that alias finds the original Sample Canvas application with `Alias: studio` in its subtitle.
  Native inspection found missing initial focus in the alias sheet and shared action panel; focus
  now defers until AppKit attaches the field editor and requires a rebuilt-app retest.
- **Rows 43–44 and 102:** Camera Preview/selfie and Confetti are registered and integrated. Camera
  stays inactive until explicit Start, uses bounded native video frames, stops after capture, and
  offers review/copy/PNG export. Confetti uses a finite original animation and Reduce Motion still
  arrangement. Their source and new tests are present; current aggregate verification is pending.
- **Reference clarification, row 29:** frame-by-frame inspection at 2:06 explicitly labels the second
  workflow Notes on iOS and shows an iPhone. It requires an actual mobile notes client, still missing;
  a second macOS editor cannot fulfill it. The preceding desktop cue shows a floating note over another
  application, so that presentation behavior also remains part of row 28's native acceptance.
- **Build findings:** the first camera build found a Swift region-isolation error in the native sample
  delegate. Rendering now stays synchronously on its capture queue and only immutable bounded frame
  bytes enter the UI stream. A subsequent build cleared that error and found an in-progress File
  Browser compile error. Neither attempt counts as a successful verification pass.
- **Aggregate and targeted verification:** `make verify` passed in
  `/tmp/commandly-video-verify-tranche3-final.log`, including 32 camera, five Confetti, ten File
  Browser, and eighteen Schedule app tests. The camera export test verifies GPS/comments are removed
  while allowing only macOS-generated technical EXIF color-space/dimension fields. Subsequent camera
  lifecycle review and keyboard changes require another pass.
- **Native camera acceptance:** the generated 640×360 preview visibly mirrored its left/right shapes;
  Take Photo stopped capture before review. Retake resumed preview, Escape stopped and cleared it,
  and native export saved `/tmp/commandly-image-fixtures/commandly-selfie.png`; `sips` verified PNG
  format and 640×360 dimensions. Return activation and fitting controls into the launcher were
  tightened after this check and await rebuilt-app retesting. No real camera or permission was used.
- **Native Confetti acceptance:** root search opened the original celebration, Return visibly replayed
  a burst, the view settled afterward, and Escape returned to root search. Reduce Motion is covered
  by model tests; actual macOS accessibility-setting acceptance remains open.
- **Additional native findings:** the shared action panel now claims focus automatically, but the
  alias sheet needed a native field-editor attachment path. Rapid Command-K also used a previous
  search result; it now shares the exact-query wait/cancellation path with Return. Ten confirmation
  cases and the six alias tests passed in `/tmp/commandly-video-actions-targeted.log`.
- **Camera lifecycle review:** a restart could overlap asynchronous cleanup of the previous camera,
  and native photo encoding could delay stopping capture. Both are being corrected with deterministic
  cancellation/ownership regressions before live device acceptance.

### Tranche 4 — September 14, 2026 (verification in progress)

- **Row 4 native acceptance:** the isolated File Browser fixture opens Design Workspace with Return,
  navigates Projects/Archive using Down and Return, displays the empty-folder state, and returns
  with Command-Up. Typing `launch` filters immediate children; Return explicitly opens the generated
  Launch plan entry through the no-op opener and displays success. Symbolic links remain visibly
  unavailable with an explanation, including on Return. Folder filter focus remains active across
  navigation. This validates UI behavior without reading or opening real user files.
- **Camera lifecycle fixes:** restart/device switching now awaits the prior capture cleanup;
  cancellation prevents a waiting restart. Native photo processing moves to a separately isolated
  cancellable worker, so stopping capture need not await encoding. Six additional controlled
  concurrency regressions are present and await the coordinated test result.
- **Rows 26–27 and 52:** Quick AI is integrated with bounded real provider text streaming, follow-up
  context, explicit Stop/Retry/New Chat, and configured provider/model selection. Opening reads
  metadata only; submitted text uses existing credential/revision validation and adapters. New
  deterministic streaming/package and app tests are present. Live account availability and native
  chat acceptance are pending; broader model discovery is the next increment, not closed by a
  single configured model per provider.
- **Row 50:** Screenshot is integrated with explicit region/window/display selection, native
  ScreenCaptureKit, bounded PNG review, and separate Copy/Save. Generated fixtures and 21 initial
  tests cover contracts, geometry, rendering, cancellation, and shared tool entry paths. Review
  identified keyboard-default and display-layout race fixes before native acceptance. Real screen
  capture/picker consent remains unverified.
- **Build findings:** first integration failed on an AppKit text-field property; it now sets the
  property on the field's cell. The second attempt reached test compilation and found a Quick AI
  callback isolation mismatch, now explicitly matched to the package protocol. Neither attempt
  is a successful aggregate verification; the last full pass remains tranche 3 above.
- **Reference clarification, row 59:** visual inspection around 3:57 labels the workflow an inline
  quick fix and shows a progress indicator in the originating editor. A separate chat with corrected
  text cannot alone close this requirement; selected text, in-place replacement, and safe failure
  behavior still need implementation and acceptance.
- **Reference clarification, rows 61–62:** paused video frames explicitly demonstrate blocking
  distracting applications and websites with a mode/block selection, then snoozing the focus session
  through a floating Pause/Complete control. A timer alone does not meet either requirement.
- **Aggregate verification:** `make verify` passed in
  `/tmp/commandly-video-verify-tranche4-final.log`, including the camera lifecycle regressions,
  23 Screenshot tests, Quick AI app tests, and all reviewed provider streaming fixtures.
- **Native alias/search acceptance:** rapidly typing Sample Canvas then Command-K now shows actions
  for Sample Canvas. Typing Alias and Return opens the editor with the native input already focused.
  Typing `studio` and Return saves it; the root result immediately shows `Alias: studio` and searching
  that alias resolves the same application.
- **Native camera keyboard acceptance:** Return starts the generated preview and a second Return
  takes the photo, stops the camera, and presents review. All controls fit the 720×480 launcher.
  Escape returned home in fresh focused runs, including after saving an alias. An earlier intermittent
  Escape failure during focus transitions could not be reproduced in these runs; it remains a
  focused-window transition acceptance concern rather than a claimed source fix.
- **Native Screenshot acceptance:** Return captures the generated region image; Return again copies
  through the no-op fixture. Native export saved `/tmp/commandly-image-fixtures/commandly-screenshot.png`;
  `sips` confirmed PNG and 800×450. Escape after export returns home. The direct window tool opens with
  Window selected; changing to Display and capturing produces a Display-labeled review. These are
  generated pixels, not evidence of real ScreenCaptureKit capture or permission behavior.
- **Native Quick AI acceptance:** an explicitly submitted fixture prompt and follow-up render in one
  conversation. The reply is generated by the inert fixture, without provider traffic. The initial
  implementation loses composer focus after the reply; the expanded model-selection batch restores
  focus when the composer becomes enabled and awaits a rebuilt-app check.

### Tranche 5 — September 14, 2026 (verification in progress)

- **Rows 28 and 52:** independent floating notes and explicit provider model discovery are integrated.
  Notes share the library persistence actor, use expected-version item mutations, preserve conflicting
  drafts, and participate in a safe application-quit handshake. New Floating Note and Open Floating
  Note are discoverable, with library refresh deferred while its editor is active. Model discovery is
  explicit, uses existing official adapters, preserves conversations on failure, and keeps chosen
  models local to the chat. Native acceptance and the full new verification pass are pending.
- **Build finding:** the first combined run compiled production changes but failed in three floating
  note test macro expansions around key-path predicates. Those lookups now use explicit local values
  before `#require`; the next pass must execute the tests before they count as verified.
- **Additional build findings:** a mutation-store test needed immutable inputs for its concurrent
  writes, and Xcode's Quick AI test-helper conformance inference produced an invalid isolation
  diagnostic. The test conformance now lives in a separate extension; actor state stays isolated.
- **Row 51:** reviewed screenshots now offer an explicit CleanShot handoff through its documented
  annotation URL. Resolution verifies the official bundle ID and Apple-anchored developer signature,
  pins the selected recipient app, and stages bounded private PNG files with independent cleanup.
  The official signed release was inspected without installing or launching it. CleanShot is absent
  on this Mac, so actual import/annotation remains unverified; a URL dispatch cannot prove import.
- **Aggregate verification:** `make verify` passed in
  `/tmp/commandly-video-verify-tranche5-batchfix.log`. This executed the floating-note integration,
  conflict/quit/mutation tests, expanded Quick AI model-discovery tests, and all sixteen CleanShot
  service/store/model cases, alongside the existing package/app suite and build.
- **Native acceptance limitation:** the Mac locked before the updated note/model-picker windows
  could be exercised. Unlock was requested while implementation and automated verification continued.
  These new native flows, including post-reply composer focus, remain explicitly unverified.

### Tranche 6 — September 14, 2026 (verification in progress)

- **Row 36:** installed-app shortcut assignment is integrated into root application Actions. It
  records a draft, explicitly saves/removes a bounded preference, uses the existing unified Carbon
  registration owner and shared typed app execution, and restores an earlier assignment after failed
  registration. Existing owners retain priority when another installed app is enabled. Recording
  pauses Commandly's own global registrations and restores them on finish, cancel, focus loss or
  dismissal. Tests cover persistence, conflicts/rollback, disabled apps, bounds and editor lifecycle;
  live cross-application activation is pending. Hyper, single-key and double-tap triggers remain open.
- **Build finding:** the first pass found a dictionary tuple-label conversion error while loading
  persisted shortcuts. Explicit key/value tuple conversion fixes it; the corrected build and tests
  must pass before this increment is verified.
- **Verification and timing finding:** all nine new installed-app shortcut tests passed. The next
  full run exposed an existing onboarding test that polled a 2.5-second wall-clock limit for its
  animation completion under concurrent load. The production choreography keeps its duration; that
  test now injects its wait and awaits the actual task instead. `make verify` then passed in
  `/tmp/commandly-video-verify-tranche6-final.log`, including the complete app/package suites and build.
- **Independent-window text sizing:** floating notes now observe the runtime's shared
  `AuxiliaryWindowAppearance`, so changing the text-size setting updates open note editors without
  replacing their drafts or reopening windows. The native visual check still awaits Mac unlock.

### Tranche 7 — September 14, 2026 (integration in progress)

- **Rows 58–59:** Spelling & Grammar and its two tool entries are registered. The checker explicitly
  requests native suggestions and offers editable review/copy. The companion macOS text Service
  receives a request-specific selection, uses cancellable progress and a bounded deadline, and returns
  eligible corrections through the originating editor's Services contract. The runtime retains one
  provider and the app delegate installs it after launch; the built Info.plist declares its exact
  selector and plain-text types. Package/app policy tests and native Services discovery/selection/Undo
  checks are pending aggregate integration. Direct launcher acquisition of another app's selection
  remains an open part of row 59, even when the native Services path is available.
- **Review findings:** Services now reject shared general/find/font/ruler/drag pasteboard names
  before reading, and validate unchanged text/deadline before every write. Unchanged output performs
  no write. Multiple individual corrections accumulate against the immutable original; manual edits
  and overlapping replacements retain the reviewed draft. Text sizing, help scrolling, initial focus,
  and progress-panel placement were tightened before acceptance.
- **Aggregate verification:** `make verify` passed in `/tmp/commandly-video-verify-tranche7-writing.log`,
  including the twenty-one writing app tests (with registration and fixture checks), four package
  correction-policy tests, and ten installed-app shortcut tests including stale assignment removal.
- **Native engine acceptance:** an isolated command-line harness using the actual checker, parser,
  and correction-policy sources called the installed native spelling service on generated text.
  Both explicit English and automatic-language requests returned two issues and the expected
  spelling/grammar corrections. The automatic request retained the leading emoji correctly; output
  is in `/tmp/commandly-native-writing-smoke/automatic-emoji.log`. This verifies the native engine
  boundary, not the signed app's Services discovery, host selection replacement, Undo, or window UI.

### Tranche 8 — September 14, 2026 (integration in progress)

- **Rows 71–73:** Translate and Translate a Word are integrated with native source detection,
  the full supported-language catalog, explicit chosen source/target, language preparation,
  cancellation, bounded result review and copy. Each live session owns a fresh native bridge;
  a stable operation-specific configuration avoids incidental view updates replacing its session.
  Twenty-one tests and the coordinated full verification are pending; native downloads/translation
  consent and output quality remain unverified while the Mac is locked.
- **Aggregate verification:** `make verify` passed in
  `/tmp/commandly-video-verify-tranche8-translation.log` with the initial twenty-one translation cases.
  A follow-up adds the labeled generated acceptance fixture and exact locale/script preference tests;
  the expanded twenty-five cases await the next combined verification.
- **Native metadata acceptance:** the actual catalog adapter returned 47 native supported languages
  and English–Spanish status `installed` in `/tmp/commandly-native-translation-smoke/metadata.log`.
  This read-only probe created no translation session or download and does not verify translated text.

### Tranche 9 — September 14, 2026 (integration in progress)

- **Row 49:** Screen Recording and its window/display/stop tools are integrated with retained native
  controls, exact scoped picker consent, optional system audio, continuous encoded video, playable
  review, and explicit MP4/MOV export. Native stream and recording-output finalization must both
  confirm shutdown before review. Private video storage and cancellation run behind injected ports.
- **Quit behavior:** capture stops before note save prompts. Recording approval is bound to its exact
  session/artifact/options, so starting a new recording while another document's close is pending
  cannot silently discard the new video. App-level ordered-close tests cover rejected Stop, cancelled
  note close, invalidated recording approval, new edits during cleanup, and duplicate quit requests.
- **Pending validation:** isolated recording tests passed before integration; the coordinated app build,
  full verification, native picker/capture and independent-window acceptance remain pending. The DEBUG
  fixture generates a labeled one-second playable video with no screen/audio capture for UI testing.
- **Aggregate verification:** `make verify` passed in
  `/tmp/commandly-video-verify-tranche9-recording.log`, including twenty-three recording model/native/
  store/fixture cases, three recording registration cases, eight app termination cases, and the expanded
  twenty-five translation tests. The native picker/capture and physical UI limitations remain open.

### Tranche 10 — September 14, 2026 (verification in progress)

- **Row 85:** Menu Bar Shortcuts now provides user-selected, persistent, independent native icons
  for up to eight registered tools. Its keyboard manager and per-icon Open/Manage/Remove menus share
  the existing command availability/review/permission path. Failed saves preserve prior pins; disabled
  and missing entries stay removable and cannot execute. No tool runs from pinning or initialization.
- **Validation:** eleven dedicated preference/controller/catalog/keyboard cases and shared execution
  menu-bar provenance/disabled-command coverage are included in the pending aggregate verification.
  The initial incremental build found a missing Foundation import in catalog sorting; it was fixed
  before the full run. Native status-item interaction remains pending Mac unlock.
- **Scope:** pins expose genuine Commandly tool shortcuts. Extension-provided live status displays
  and third-party data still require their corresponding extension/integration implementations.
- **Aggregate verification:** `make verify` passed in
  `/tmp/commandly-video-verify-tranche10-menubar-retry.log`, including all eleven dedicated menu-bar
  tests and the existing shared command/history suites. The first full attempt found a missing SwiftUI
  import in the application registration view builder; the successful rerun includes that correction.

### Tranche 11 — September 14, 2026

- **Row 68:** Display Resolution is integrated with an independent chooser, native exact-mode catalog,
  temporary preview, a continuous 15-second revert deadline, explicit session Keep, and failure recovery.
  The app's quit sequence now stops recording, restores a pending display preview, reviews notes,
  then commits only the approved recording cleanup. New display activity before the final reply cancels
  quitting. `make verify` passed in `/tmp/commandly-video-verify-tranche11-display.log` with nineteen
  display cases and the three additional cross-feature termination cases. No real display was changed.
- **Native acceptance resumed:** the Mac was unlocked. A generated floating note opened with initial
  body focus, saved by Command-S, retained an unsaved edit after Escape in its close prompt, saved/closed
  by Command-Return, and appeared in the library with the final edit. The generated spelling fixture
  reviewed both errors and produced the expected emoji-preserving correction. Translate's generated
  fixture submitted with Command-Return and showed its explicitly labeled result. These fixtures do
  not replace the separate native engine, consent, or provider integration acceptance.
- **Menu-bar manager:** native keyboard search/Return added then removed the generated Confetti pin
  with correct counts and selection. Direct status-item menu activation remains unverified because
  the computer-use surface could not expose that menu; no user pins were modified.
- **Recording runtime crash:** the first generated recording reached Stop but crashed on constructing
  the SwiftUI `VideoPlayer` overlay. The native AVKit superclass was not linked. Direct `AVPlayerView`
  hosting now builds with explicit AVKit linkage and the generated video plays in native review.
  The subsequent native Save dialog failed without losing the reviewed video. Export repair and
  another real Save-dialog acceptance run remain required; the earlier green tests missed both paths.
- **Display fixture:** the native chooser presented its generated modes, applied the alternate mode,
  showed the fifteen-second countdown, and returned to the original current selection on expiry.
  No physical display configuration was read or changed by this fixture acceptance.
- **Architecture:** the product owner explicitly accepted [ADR-0011](decisions/ADR-0011-optional-system-companion.md).
  The optional signed per-user companion is now authorized for implementation while the main app remains
  sandboxed. Registration, native grants, and signed cross-process acceptance are separate pending steps.

### Tranche 12 — September 14, 2026 (integration in progress)

- **Rows 10–11:** the dedicated Emoji Search application preserves its existing entry IDs and replaces
  the small curated picker with 3,944 fully-qualified Unicode 17 emoji plus nine components. Search
  includes CLDR English keywords, exact sequences, categories, and full skin-tone variants. Explicit
  AI description search uses the existing configured Quick AI service with bounded, validated results.
  Regeneration checks passed; bundled resource, native UI, and aggregate verification remain pending.
- **Row 70:** Finder AI's `finder_convert_image` now creates an exact local conversion approval and
  uses the native byte-only converter. Source and destination authority, cancellation, identity changes,
  collision, and single-use approval are tested with generated files. Forty isolated cases passed;
  combined app verification and native approval/provider acceptance remain pending.
- **Aggregate verification:** `make verify` passed in
  `/tmp/commandly-video-verify-tranche12-final.log`, including emoji, Finder image conversion, and the
  new recorder export cases. Integration exposed imported actor-conformance inference in two emoji
  test doubles and missing default shortcut metadata; both were fixed. An existing onboarding test
  exceeded its wall-clock polling budget under load; it now awaits its actual login-item update.
- **Native recording save:** the signed sandboxed app created and replaced the generated 11,388-byte
  MP4 through NSSavePanel, with native success feedback and 0600 output permissions. The saved review
  closed without an unsaved prompt. CUA lost its no-window target afterward; a process sample showed
  an idle main event loop, and restarting the owned generated fixture restored UI control.
- **Native emoji:** name/keyword search found Japan flags and a woman astronaut; an exact
  `👩🏽‍🚀` query selected the correct joined skin-tone sequence. Return produced explicit copy feedback.
  Visual inspection exposed a wrapped picker label, now hidden while preserving its accessibility
  name. Empty-query ranking and singular result copy were corrected; those follow-ups await the next
  verification. Native variant-menu selection and optional AI success acceptance remain pending.
- **Row 79 source clarification:** frame inspection at 5:14–5:16 shows root input `#966A5E`, a color
  preview, and outputs Hex, Hex with Alpha, RGBA, RGBA Percentage, RGB CSS4, and HSL. That specific
  set and direct root detection are the next color-conversion acceptance scope.

### Tranche 13 — September 14, 2026 (integration in progress)

- **Companion foundation:** the approved separate helper target, versioned bounded IPC contracts,
  metadata session lifecycle, signed-peer checks, and explicit System Integration setup are integrated.
  Fourteen package tests and an isolated unsigned helper build passed before publication. The root
  aggregate and signed embedded-pair checks remain pending. No helper has been registered or started.
- **Privacy boundary:** Foundation's signing requirement authenticates received messages; it does
  not promise to authenticate a named-service destination before the initial outbound message.
  All future action requests are therefore rejected locally before a connection. An authenticated
  channel bound to one helper instance must be reviewed before any private selection/action payload.
  This foundation does not complete window, app-menu, text insertion, keyboard-trigger, or app-control rows.
- **Acceptance fixtures:** generated-only Finder AI image conversion and successful emoji semantic
  search fixtures are wired for native review without live credentials, network, or user folders.
  Finder uses its real workspace, single-use approval, and native image converter; four isolated
  conversation tests passed. Both native success flows and combined verification remain pending.

- **Aggregate verification and signing:** `make verify` passed in
  `/tmp/commandly-video-verify-tranche13-companion.log`, including the fourteen companion package
  cases, settings tests, four Finder image fixture cases, and emoji follow-up fixes. `make build`
  passed in `/tmp/commandly-video-native-tranche13-build.log`. Both embedded app/helper signatures
  passed strict validation against their exact identifier and team requirement. Main sandbox and
  profile presence, non-sandboxed hardened helper, and embedded LaunchAgent path were inspected.
  This does not prove registration or an actual native handshake; neither has run.
- **Native Finder image success:** the signed sandboxed generated conversation showed the exact
  one-use conversion approval and completed the real local conversion after Approve Once. Its JPEG
  exists with 0600 permissions. Native codec tests prove dimensions/source preservation; external
  content inspection was denied by macOS app-container protection. Real-provider planning remains open.
- **Native emoji follow-up:** corrected header layout and first-item ordering passed inspection; Down
  moved six grid cells, the native variant picker selected a different skin tone with arrow keys/Return,
  and the generated AI fixture returned four validated suggestions on explicit Return. Selecting its
  mixed-tone handshake and Return produced copy feedback. No live AI request or real clipboard ran.

- **Native setup fixture:** System Integration showed Disabled, reviewed the enable explanation,
  reached Enabled/Connection Unchecked, then Ready/Metadata Connection after Check Connection, and
  returned to Disabled. All operations used the visibly labeled in-memory fixture. Native inspection
  found Settings section crowding and low-contrast footers; shared spacing and footer readability
  fixes are queued for the next verification/native run.

### Tranche 14 — September 14, 2026 (integration in progress)

- **Rows 13–16:** Dictation is integrated with on-device SpeechAnalyzer, explicit language downloads,
  contextual microphone start, bounded provisional/final review, optional AI style previews, and
  explicitly saved text history. Twenty-four isolated tests passed before publication; registration
  smoke coverage, combined app verification, and native acceptance are pending. Current-app insertion
  remains dependent on the companion; no auto-detection of spoken language is claimed.
- **Native companion installation finding:** the user approved a real enable/check/disable acceptance.
  The first Enable failed before any helper started. macOS identified its sandboxed registering owner
  as incompatible with a non-sandboxed target, consistent with Apple DTS's macOS 14.2+ rule. Setup
  ownership is being moved into the companion's own visible non-sandboxed app; the main stays
  sandboxed. See ADR-0011's correction. No actual XPC handshake or cross-app capability passed.
- **Settings readability:** the signed native window now has clear section spacing and readable
  explanatory footers. The focused build and menu catalog test passed; combined verification follows
  the new feature integration. The 103-tool Debug catalog sample took 1.04 ms (one sample, not a SLA).

- **Aggregate verification:** `make verify` passed in
  `/tmp/commandly-video-verify-tranche14-dictation-channel.log`, including all 25 app dictation
  cases and the 32 package tests covering the authenticated bound companion channel. The channel
  still needs a real helper registration and native connection check.
- **Native speech preflight:** read-only API inspection reports SpeechTranscriber available and
  45 supported locales, with nine English locales in `installedLocales`. Creating the equivalent
  English module nevertheless reports AssetInventory status `supported` rather than `installed`.
  A generated-audio acceptance probe therefore stopped before recognition; it did not download a
  model or use a microphone. Real recognition remains unverified.

### Tranche 15 — September 14, 2026 (native acceptance in progress)

- **Rows 78–79:** shared bounded color parsing now drives both root search and Color Tools, with
  all six observed output formats, alpha-preserving defaults, original checkerboard previews,
  typed copy actions, Command-K, and Command-1 through Command-6. `make verify` passed in
  `/tmp/commandly-video-verify-tranche15-color.log`. Coverage includes 52 syntax cases, 1,296
  deterministic round trips, queued-copy cancellation, stale result identities, late sampler
  results, and root pending-query dispatch. Native appearance/keyboard acceptance follows.
- **Row 87 source clarification:** frame inspection at 5:39 shows a Windows query `display`,
  settings destinations for display, brightness, color profile, orientation, resolution, and
  scale, with the primary action `Open Windows Setting`. This cue demonstrates settings-page
  navigation. Commandly will supply discoverable macOS destinations; direct display changes
  remain separately tracked under row 68.

- **Native color and shared Actions:** root recognition, percentage action search, Command-6 HSL,
  alpha defaults, six editor formats, and Command-5 CSS4 passed in the clean signed app. Real
  NSColorSampler returned a color from Commandly's own interface. Editor Command-K exposed a
  shared footer binding that never displayed its menu. The shell now supplies a searchable panel,
  with custom-menu ownership retained for File Search and Markdown Preview. Full verification
  passed in `/tmp/commandly-video-verify-tranche15-actions-final.log`; a fresh clean signed build
  passed deep strict signature validation. Native Command-K → CSS4 → Return copied the expected
  value and restored input focus. Sampler Escape cancellation remains unconfirmed: automation's
  Escape events did not yield a clear state transition, while Back returned to root successfully.
- **Native dictation fixture:** Command-Return started generated provisional text and stopped into
  final editable review; Return inserted a newline, Command-Shift-C copied, and explicit Save
  appeared in searchable history with keyboard copy. An optional generated-provider style preview
  preserved the original until a choice; Keep Original discarded it. A replacement recording's
  Cancel restored the exact saved text and save identity, allowing Back without an unsaved alert.
  No microphone, actual recognition, live AI request, or persistent user history was used. Native
  review found stale saved status and an offscreen transcript after starting from an expanded AI
  section; the status/scroll corrections are queued for the next aggregate and native check.

### Tranche 16 — September 14, 2026

- **Aggregate verification:** `make verify` and the clean signed build passed in
  `/tmp/commandly-video-verify-tranche16-setup-owner.log` and
  `/tmp/commandly-video-native-tranche16-setup-owner.log`. Exact main/helper team and identifier
  requirements, deep strict signing, effective entitlements, and helper-owned packaging passed.
- **Actual companion acceptance:** opening setup did not register a job; user-approved Enable
  registered the helper-owned per-user service. Main Check Connection reached Ready/Metadata over
  the authenticated bound endpoint. Disconnect and explicit reconnect passed. Setup Disable
  removed the launchd job and ended the headless process; main Refresh cleared Ready and a disabled
  Check showed recovery. Setup then closed. The companion is disabled and unregistered; no new
  privacy grants occurred. Wrong-signer/replacement harnesses and all cross-app actions remain open.
- **UI follow-ups:** dictation status/scroll corrections and Color Tools field-editor Escape
  fallback passed native acceptance. Dictation restart from expanded/scrolled styles returns the
  recording indicator and transcript to view and clears stale saved feedback; Cancel restores the
  saved draft. Color Actions Escape restores editor selection; editor Escape returns to root.

### Tranche 17 — September 14, 2026 (native acceptance in progress)

- **Row 9:** GIF Search now has an explicit GIPHY BYOK connection, bounded search/trending,
  animated previews, keyboard selection, original-animation copy/save, creator/source attribution,
  and Keychain storage. Requests start only on the user's action. Independent review corrected
  suspended credential-change reuse, compact layout, and distinct accessibility labels. Thirty
  isolated tests passed; registry smoke coverage is included in the aggregate run. Live provider
  authentication remains pending an explicitly configured key; generated native acceptance follows.
- **Row 87:** a macOS System Settings catalog registers 27 discoverable navigation intents for
  22 fixed Apple pages, plus an app-opening tool. The six display intents clearly say Opens Displays.
  Dispatch pins the verified system application and provides an honest app-only fallback. Nineteen
  isolated tests passed; current Apple metadata was checked for all destinations. Actual page
  navigation and native compact/keyboard acceptance follow; this feature does not mutate settings.
- **Aggregate verification:** `make verify` passed in
  `/tmp/commandly-video-verify-tranche17-gif-settings.log`, including new GIF registration and
  System Settings application tests. Following the connection-sheet corrections, the final aggregate
  passed in `/tmp/commandly-video-verify-tranche17-final.log`; the clean signed build and deep strict
  signature check passed in `/tmp/commandly-video-native-tranche17-final-clean.log`.
- **Native GIF fixture:** explicit search, three distinct results, arrow/Return copying, Trending,
  Command-K/Escape focus restoration, and native Save/cancel passed using locally generated media.
  The saved GIF reopened with all four 120 × 80 frames intact. Compact density, larger text and light
  appearance fit within the launcher. Connection-sheet inspection found clipped explanatory text
  and stale export feedback; the corrected scrollable sheet and explicit fixture wording passed
  tests/build and the native recheck on September 14. No GIPHY credential/network check
  is claimed.
- **Verification repair:** a pre-existing uninstall integration test finished both Trash operations
  but exceeded its three-second polling budget before the completion callback. The test now awaits
  the model's actual load/uninstall tasks; its route/favorite/ranking assertions remain intact.
  Targeted GIF/uninstall tests and the final full verification passed.
- **Menu catalog sample:** the 137-tool Debug catalog construction/sort measured 1.053 ms in one
  final aggregate sample. This excludes registry assembly and is not a performance SLA.

### Tranche 18 — September 14–17, 2026 (native acceptance in progress)

- **Row 74:** Finder Path now registers an application and Copy Current Finder Path tool. Explicit
  copying reads one selected Finder item, or the current folder when nothing is selected, through
  fixed typed Apple events. It uses the existing Finder-only Automation boundary, contextual consent,
  transient context revalidation and cancellation before clipboard commit. Twenty isolated tests
  passed; combined verification and signed native acceptance follow. Generated fixture results will
  be kept separate from real Finder permission/descriptor evidence. See [Finder Path](FINDER_PATH.md).
- **Native companion authentication harness:** signed standalone fixture clients passed exact-peer
  metadata, local rejection of unimplemented actions, listener revocation/fresh endpoint, revoked
  bootstrap offers, same-team wrong-app rejection and kernel-observed different-audit-session
  rejection. Same-team wrong-helper rejection and helper-exit closure/old-transport terminal state
  subsequently passed. The fresh-offer timeout was traced to launchd's default ten-second respawn
  throttle. On September 17 the reviewed harness allowed fifteen seconds only for its control offer
  after verified helper exit; production bootstrap/bind/metadata deadlines remained five seconds.
  The signed rerun passed explicit fresh connection while the old transport remained terminal in
  `/tmp/commandly-companion-native-harness-respawn/native-correct.log`. These
  use bundled XPC fixtures and do not establish production Mach-name replacement behavior. The real
  companion remains disabled and unregistered; no privacy permission was granted by this harness.
- **Aggregate test repair:** all five Finder Path suites completed in the first aggregate run, but
  the old `launcherOpensApplicationViaOpener` recorder had a lost-wakeup race between checking its
  result and installing its continuation. The stalled run was interrupted. Its recorder is now an
  actor, and the test awaits the launcher's actual confirmation task. Targeted Finder Path and
  launcher-opening tests passed; the full aggregate rerun passed in
  `/tmp/commandly-video-verify-tranche18-final.log`. The clean signed build and deep strict signature
  check passed in `/tmp/commandly-video-native-tranche18-clean.log`.

### Tranche 19 — September 17, 2026 (integration in progress)

- **Row 12:** [Slack Emoji](SLACK_EMOJI.md) now registers a dedicated application and search tool.
  It implements explicit bot-token connection, workspace choice, local name/alias search after
  explicit refresh, static/animated previews, shortcode copy, and original-image copy/save.
  Twenty-seven isolated tests and the root's targeted six Slack suites passed. A separate review
  reproduced reopening during a pending secure write leaving a new session with stale setup. The
  integrated service-level settlement correction passed thirty isolated tests, including fresh-model
  reads during successful/failed writes and independent waiter cancellation. Root `make verify`
  subsequently passed in `/tmp/commandly-video-verify-sept17-slack.log`, including registry integration.
  Real Slack/Keychain acceptance remains open. The initial inventory above preserves the starting gap.
- **Shared keyboard fix:** explanatory screens without a focused SwiftUI input did not receive
  Command-K. The shared Actions footer now also has a native keyboard shortcut. Full verification
  passed in `/tmp/commandly-video-verify-sept17-actions.log`. Native Command-K/Escape passed on
  Finder Path with no text input and Slack with search-field focus; it opened once and restored focus.
- **Finder acceptance setup:** a DEBUG-only `--commandly-live-finder-path` override permits real
  Finder checks while other productivity tools keep generated data. Opening the app still performs
  no Finder read or permission prompt. Generated single-item copy feedback passed on September 17;
  actual Finder Automation acceptance is separate and remains open. The signed live attempt exposed
  a real identity issue: Finder was running but NSRunningApplication supplied no launch date.
  The integrated fix now uses exact kernel birth time and executable checks on a dedicated queue,
  rejecting PID reuse without relying on LaunchServices. Twenty-six isolated tests and the full
  aggregate passed in `/tmp/commandly-video-verify-sept17-finder-identity.log`. Signed native
  acceptance follows; no Automation prompt or grant has occurred.
- **File Search test repair:** the next aggregate run exposed the existing file-copy test's
  one-second polling deadline. The model now retains the copy task and the test awaits its actual
  completion with its original assertion intact. All six Slack suites passed in
  `/tmp/commandly-video-targeted-sept17-slack.log`; the initial per-method selector omitted the
  File Search test. Its corrected selector ran and passed the actual method in 0.088 seconds in
  `/tmp/commandly-video-targeted-sept17-file-copy.log`. The full aggregate with the Slack review fix
  then passed in `/tmp/commandly-video-verify-sept17-slack.log`.
- **Native Slack fixture:** discovery, explicit refresh, static/animated previews, arrows/Return
  shortcode copy, alias search, missing-alias guidance, Command–Shift–C original-image copy, and
  Save/cancel passed. The 719-byte exported GIF reopened with all four 64 × 64 frames and mode 0600.
  Workspace switching cleared the catalog, generated connection setup cleared the secure field,
  and Escape restored search focus. Compact/larger/light UI and scrolling setup controls fit.
  `/tmp/commandly-video-native-sept17-slack-clean.log` records the clean signed build; deep strict and
  exact bundle/team checks passed. The service settlement correction postdates this UI build and
  passed the subsequent aggregate; a new signed build is pending. No live Slack/Keychain or
  VoiceOver claim is made.
- **Native System Settings:** the signed sandboxed app opened real Displays from the catalog and
  Sound and Date & Time through direct tools, verified by the actual destination windows. No OS
  preference was changed. The temporary Commandly layout preferences were restored to Comfortable,
  Default text size, and System theme after the compact acceptance checks.

### Configured keyboard trigger source implementation

[Keyboard Triggers](KEYBOARD_TRIGGERS.md) adds Caps/Hyper tap-hold handling, safe single keys,
double-tap file Quicklinks, and optional literal snippet/emoji keyword expansion through the
authenticated companion. Eight focused reducer/routing tests and strict isolated source/helper/UI
compilation pass. No live input tap, TCC grant, text replacement, registration or native acceptance
was run for this slice. Rows above remain Partial until that behavior is observed on supported hardware.
