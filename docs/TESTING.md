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

## Rules

- No `XCTAssertTrue(true)` / empty `#expect(true)` style placeholders.
- No real clipboard, Keychain, provider network, user API keys, user files, or permission prompts.
- AI tests use injected HTTP fixtures, `InMemorySecureStore`, fake provider credentials, and
  in-memory or isolated temporary authorized roots. They must not depend on quota, billing, installed
  Ollama models, or a developer's provider account.
- Prefer deterministic providers (`FixedDateProvider`, `FixedUUIDProvider`).
- Prefer Swift Testing for new unit tests.

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
- System resource/application models, protected quit-all behavior, and confirmation flows without terminating real apps
- Recent Downloads ordering/filtering and open/reveal/file-copy actions against temporary files and injected adapters
- Shelf URL staging and metadata enrichment, duplicate suppression, selection and copy-only drag-out
  retention, file/folder/text/image clipboard seeding, private temporary-content ownership and
  cleanup, direct native-share routing, empty-close/drop-sound settings, non-destructive reference
  removal, preview dispatch, semantic homogeneous/mixed item labels, resilient incoming-drop counts,
  outgoing/incoming drag isolation, whole-surface window-drag suppression during item drags,
  repeated-presentation generations, fixed global-shortcut routing, shared launcher/Shelf
  configure-before-activate overlay behavior, cold first-window attachment, pending first-open
  replay, reentrant AppKit attachment/style-mask changes without lost presentation requests,
  sticky cross-Space window roles, launcher outside-click dismissal, launcher centering, and Shelf corner geometry
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
