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

## Rules

- No `XCTAssertTrue(true)` / empty `#expect(true)` style placeholders.
- No real clipboard, Keychain, network, user files, or permission prompts.
- Prefer deterministic providers (`FixedDateProvider`, `FixedUUIDProvider`).
- Prefer Swift Testing for new unit tests.

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
- Documentation registration coverage, structured-content validation, automatic catalog inclusion,
  disabled-app discoverability, live alias/hotkey metadata, full-text search, selection repair, and
  launcher-menu routing
