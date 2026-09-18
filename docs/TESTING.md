# Testing

## Layers

1. **Package tests** (`Packages/Tests`) — contracts, pure logic, in-memory adapters.
2. **App unit tests** (`CommandlyTests`) — composition root, routing, view-model wiring.
3. **UI tests** (`CommandlyUITests`) — optional smoke checks; skipped by default in the shared scheme.

## Commands

```bash
make test
swift test --package-path Packages
make verify
```

File Search also has an opt-in deterministic macOS UI validation scheme:

```bash
xcodebuild \
  -project Commandly.xcodeproj \
  -scheme CommandlyUIValidation \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath .derivedData \
  test
```

Its DEBUG-only launch fixture creates sandbox-local CSV and text files, then exercises the production
filesystem scanner, SQLite FTS index, view model, CSV preview, live content query, and right-click
actions panel. It also rapidly changes selection across native Quick Look snapshots to cover preview
cancellation and stale-result handling. The normal `Commandly` scheme keeps GUI automation skipped
so `make verify` remains safe for non-interactive environments.

Command Wheel adds deterministic package/app coverage for the command pipeline, profiles,
persistence, geometry, state, shortcuts, input lifecycle, Settings transactions, and execution
parity. Its panel/Settings accessibility smoke checks belong in the same opt-in GUI scheme; they are
not implied by `make verify`. The exact commands, suite-to-risk map, manual display/Space/focus
matrix, performance method, and per-implementation execution record are in
[Command Wheel Testing](COMMAND_WHEEL_TESTING.md).

Window Switcher foundation work uses deterministic Infrastructure and app-target doubles for
enumeration, control, thumbnail, permission, and input behavior. `make verify` must not query real
Accessibility trees, install a real event tap, capture another application's pixels, move/close a
real window, or trigger a TCC prompt. Tests must also verify that sandboxed production composition
does not register the application or start its privileged coordinator. Passing prototype tests does
not establish App Sandbox compatibility or a usable workflow. The system-integration matrix below is
reserved for a future explicitly authorized non-sandboxed runtime. See
[Window Switcher](WINDOW_SWITCHER.md).

Markdown Preview keeps parser, sanitization, configuration, file-type, and renderer tests in
`MarkdownPreviewKit`. App tests use temporary files and injected loaders/watchers/web controllers;
they must not read user documents or open external URLs. The Quick Look extension has an isolated
unsigned build check, but registration, Finder lifecycle, provider conflicts, and extension
accessibility require the signed manual matrix in [Markdown Preview](MARKDOWN_PREVIEW.md).

## Rules

- No `XCTAssertTrue(true)` / empty `#expect(true)` style placeholders.
- No real clipboard, Keychain, provider network, user API keys, user files, or permission prompts.
- No real Accessibility enumeration/control, Screen Recording capture, global event tap, Dock AX
  traversal, or mutation of another application's windows in automated tests.
- AI tests use injected HTTP fixtures, `InMemorySecureStore`, fake provider credentials, and
  in-memory or isolated temporary authorized roots. They must not depend on quota, billing, installed
  Ollama models, or a developer's provider account.
- Prefer deterministic providers (`FixedDateProvider`, `FixedUUIDProvider`).
- Prefer Swift Testing for new unit tests.

## Required application-tool and inline-search coverage

The application/tool architecture is not complete without deterministic tests for:

- Built-in and user tag normalization, deduplication, bounded persistence, legacy-alias discovery,
  and Settings filtering
- Default Open tools, specialized tool ownership, hierarchy ordering, duplicate/misowned tool
  rejection, inherited enablement, and application/tool shortcut planning
- Preservation of a tool's full `CommandReference` arguments through search, shared execution,
  launcher presentation, and Command Wheel assignment
- Background-tool allow-listing versus ordinary session presentation, with injected service and
  shortcut adapters only
- Exact typed-command acceptance and malformed, out-of-range, trailing-token, command-substitution,
  and shell-fragment rejection
- Port Manager's zero/one/multiple-listener entry states plus explicit confirmation and stale-owner
  revalidation; automated tests must never terminate a real process
- Inline Clipboard History ranking and six-row bound using an isolated pasteboard/store, without
  rerunning capture enrichment
- Inline File Search ten-row bound, debounce cancellation, stale-result rejection, failure
  isolation, and Open routing with an in-memory search service and URL opener
- Exclusion of private Clipboard History and Files rows from autocomplete and shared command history

## Required AI coverage

The AI vertical slice is not complete until deterministic tests cover these categories without
claiming live-provider compatibility:

- `AIKit` value semantics, redaction, JSON/schema validation, duplicate provider registration,
  native continuation-state correlation, bounded agent rounds, and cancellation
- Provider-specific authentication and metadata/model discovery fixtures, pagination/filtering,
  capability-evidence provenance, malformed payloads, and sanitized status mapping
- Explicit runtime/catalog behavior for OpenAI, Anthropic, Gemini, Mistral, Groq, xAI, OpenRouter,
  and loopback Ollama, including each adapter's native authentication, discovery, and tool wire form
- Non-streaming generation/tool responses, working/cancellation UI state, quota/provider failure,
  and preservation of the same provider's opaque continuation state across tool rounds
- BYOK setup ordering: key held only in memory before validation, model choice required before save,
  Keychain write/delete, and non-secret provider/model preference round-trip
- Secret hygiene: keys and authorization headers absent from descriptions, errors, fixtures,
  UserDefaults, logs, and failure output
- Finder root/handle lifetime, canonical containment, resource-identity revalidation, symlink and
  package leaf behavior, collision/name limits, and prohibited protected roots
- Exact content/mutation planning, expiring single-use approval, stale-plan rejection, partial
  failure reporting, and natural-language delete mapping only to Move to Trash
- Rejection of unknown/malformed tools, raw paths, permanent deletion, overwrite/merge, arbitrary
  sharing, AppleScript, process launch, and shell execution
- Ephemeral conversation cleanup plus cancellation of provider, approval, and pending tool work when
  the launcher application stops

## What foundation tests cover

- Deterministic UUID/date providers
- Command ID equality and duplicate registration
- Search query normalization
- In-memory persistence round-trip
- Permission state doubles
- Extension manifest validation
- App container bootstrap and router updates
- Typed launcher-application hierarchy, duplicate/missing-parent rejection, and branch-free dynamic session launch
- Alias discovery, inherited enablement, schema-driven session defaults, and preferences persistence
- Clipboard create/edit/append workflows and calculation-history lifecycle
- Timer drift, pause/resume/reset, focus presets, and shared application-session lifetime
- Transactional Productivity Library persistence, safe Quicklinks, clipboard templates, and sharing data
- Offline emoji/text/color/dictionary/font/typing logic with injected native boundaries
- Window-layout catalog geometry, custom persistence, and application dispatch without real permission prompts
- Window-switching query-option filtering, process-scoped identity use, titleless/windowless
  representation, activation/minimize/close/quit routing, and typed missing-window/query failures
  through the in-memory Infrastructure adapter
- Window Switcher prototype definition, modeled Accessibility availability requirement, all 28
  schema defaults and nine generic sections, selection parsing, numeric clamping, exclusion-term
  normalization, documented numeric bounds, legacy configuration-field decoding, presentation
  lifecycle with doubles, plus production-registry/coordinator absence while sandboxed
- Screen Recording permission preflight without prompting, authorized/denied/not-determined state,
  request-marker ordering, already-authorized short circuit, Settings refresh, denied-state recovery
  routing, and the System Settings Screen Capture privacy-pane URL through injected closures/doubles
- System resource/application models, protected quit-all behavior, and confirmation flows without terminating real apps
- Storage Cleaner registration, conservative installed-app/Apple identifier exclusions, bounded
  Library categorization, isolated exact-duplicate hashing, cache opt-in recommendations, one-copy
  duplicate selection, and confirmed Trash routing without scanning or mutating real user files
- Recent Downloads ordering/filtering and open/reveal/file-copy actions against temporary files and injected adapters
- Background Remover registration, injected processing success, transparent PNG naming, and recoverable no-foreground failures without Vision, network, or user-file access
- Markdown Preview parsing and sanitization, renderer configuration migration/clamping, file-type
  coverage, traversal/link/image rejection, shared non-secret preferences, bounded host loading,
  stale-load cancellation, watcher/scroll behavior, export state, and launcher registration without
  opening a user file, external URL, Finder, or print panel
- Shelf URL staging and metadata enrichment, duplicate suppression, selection and copy-only drag-out
  retention, file/folder/text/image clipboard seeding, private temporary-content ownership and
  cleanup, direct native-share routing, empty-close/drop-sound settings, non-destructive reference
  removal, preview dispatch, semantic homogeneous/mixed item labels, resilient incoming-drop counts,
  outgoing/incoming drag isolation, whole-surface window-drag suppression during item drags,
  repeated-presentation generations, tool-owned default shortcut routing, shared launcher/Shelf
  configure-before-activate overlay behavior, cold first-window attachment, pending first-open
  replay, reentrant AppKit attachment/style-mask changes without lost presentation requests,
  sticky cross-Space window roles, active-desktop display re-homing with observer teardown,
  display-geometry clamping, late async Shelf teardown safety, launcher outside-click dismissal,
  launcher centering, and Shelf corner geometry
  (including displays with negative origins), rounded AppKit hosting-layer masking, custom shadow
  ownership, and file-action routing through in-memory or isolated named-pasteboard adapters
- Documentation registration coverage, structured-content validation, automatic catalog inclusion,
  disabled-app discoverability, live alias/hotkey metadata, full-text search, selection repair, and
  launcher-menu routing
- Typed command references/arguments, atomic catalog replacement, availability resolution, shared
  search/hotkey/wheel execution, installed-app opener identity, invocation-source attribution,
  execution-once behavior, bounded durable privacy-safe history, and sanitized failures
- Command Wheel defaults, rooted profile/page/slot validation, context selection/conflicts,
  current-schema round trip, previous-schema migration, corrupt/future data handling, collision-safe
  imports, unavailable references, editor transactions, and assignment/replacement behavior
- Command Wheel radial boundaries for 4/6/8/12 slots, dead/neutral/submenu regions, hysteresis and
  final flick samples, keyboard traversal, negative-origin/gapped/scaled displays, clamping to the
  actual center, session generations, stale-task rejection, input/monitor teardown, and dynamic
  provider freezing

Shelf's opening fade/scale, live launcher/Shelf state retention while changing Spaces, control hit
testing during whole-surface movement, and reduced-motion presentation still require targeted macOS
UI/VoiceOver review in addition to the deterministic unit coverage above. Command Wheel likewise
requires manual hold/release timing, temporary focus restoration, full-screen/Space placement,
display-disconnect cancellation, VoiceOver, contrast/transparency, and leak review; deterministic
geometry and lifecycle tests cannot prove those system behaviors.

## Video feature acceptance fixtures

For repeatable library and clipboard UI checks, a Debug build accepts
`--commandly-show-launcher --commandly-skip-onboarding --commandly-productivity-fixture`.
This launches two temporary sample library items and a separate named pasteboard with two sample
clipboard entries. Library persistence and clipboard copying are isolated from the user's data;
file search and Schedule use in-memory services, and Camera uses a generated geometric preview/photo
with simulated authorization and a no-op copier. The fixture skips clipboard monitoring,
auto-quit, and global shortcut registration. The flag has no effect in Release.

Exercise snippet named inputs and Cancel/Copy focus, tag filtering/editing, clipboard pin/rename/
collection controls, immediate row/detail updates, and repeated back/open cycles. Inspect both
rendered output and the accessibility tree: model tests alone did not detect macOS accessibility
label recursion or stale text after selection. Use generated image fixtures for Image Tools and
injected calendar snapshots for Schedule. Camera's generated coral square/cyan circle fixture supports
preview, mirrored capture, retake, copy feedback, and native PNG export checks without using a camera.
Live system permission and external-account acceptance
remain separate from these isolated flows; record their exact artifact and observed results in
`VIDEO_FEATURE_PARITY.md`.

## Window Switcher future runtime matrix

Do not run or report this matrix as validation of current sandboxed Commandly. It becomes an
acceptance matrix only after a new ADR authorizes a separately signed non-sandboxed companion/helper
or a direct-distribution build with App Sandbox disabled. Run it against that exact signed artifact;
do not add permission-dependent cases to shared CI.

| Area | Required manual cases |
|------|-----------------------|
| Architecture and signing | Verify the exact authorized helper/direct-distribution topology, code signatures, entitlements, IPC authentication, launch/update ownership, sandbox status, and production feature gating before any functional result is accepted |
| Accessibility | Never granted, grant from the explicit explanation, deny, revoke while open, and grant again; verify enumeration/control stops safely while unrelated features remain usable |
| Input Monitoring and event filtering | Verify the global key-event stream is filtered immediately, unrelated events pass unchanged and are not retained, active filtering fails closed, and a passive listen-only fallback neither suppresses nor claims to replace system shortcuts |
| Screen Recording | Never granted, deny, grant, revoke while thumbnails are visible, and grant again; verify title/icon fallback and that dismissed/revoked images do not remain visible or cached |
| Option-Tab | First invocation, repeated Tab, Shift-Tab reverse, key repeat, modifier release, Escape cancel, rapid reopen, target closes mid-cycle, shortcut conflict, secure input, and event-tap timeout/re-enable |
| Command-Tab replacement | Disabled default, explicit enable/disable, forward/reverse/release/cancel, system fallback when unavailable, and VoiceOver/Full Keyboard Access coexistence |
| Window states | Multiple windows per app, titleless, minimized, hidden app, windowless app setting, full screen, transient dialogs/sheets, unsupported action, target quit, and stale AX element |
| Displays and Spaces | Single display, negative-origin secondary display, current-display filter, display disconnect, resolution/scaling change, current desktop, full-screen Space, and a window on another Space; verify no cross-Space movement or completeness claim |
| Dock hover | Feature off/on, delay, Pin/Unpin and hover dismissal, Dock left/bottom/right, auto-hide, magnification, multiple displays, Dock restart, non-window Dock items, and changed/unavailable AX hierarchy; failure must disable only the best-effort preview path |
| Pointer and focus | Hover enter/exit, rapid target changes, outside click, action buttons, launcher/panel focus restoration, and no pointer history retained |
| Accessibility UI | VoiceOver names/order/actions, keyboard-only route, Larger Text, Reduce Motion, Reduce Transparency, Increased Contrast, light/dark appearance, and thumbnail-free parity |
| Performance/lifetime | Cold and warm presentation, rapid cycling, window-notification bursts, thumbnail memory bound, idle CPU with previews off/on, repeated open/dismiss, permission churn, and observer/event-tap teardown |

Record the authorized architecture/ADR, artifact signature and sandbox status, macOS version,
hardware, display/Space arrangement, grants, settings, result, and any application-specific AX
limitation. Dock-hover and Command-Tab replacement pass only as best-effort surfaces on the tested
configuration; the record must not generalize them to other artifacts or macOS releases.
