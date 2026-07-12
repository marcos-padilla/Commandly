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
