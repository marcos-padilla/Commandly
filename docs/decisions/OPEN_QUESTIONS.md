# Open Questions

## Persistence backend

**Question:** Should durable storage use SwiftData, Core Data, SQLite (e.g. GRDB later), or file-based Codable stores?

**Current state:** Only contracts + `InMemoryPersistenceStore`. No backend selected.

## Final license

**Question:** Open-source license vs proprietary/commercial?

**Current state:** Temporary all-rights-reserved `LICENSE` (Copyright 2026 Commandly).

## Global hotkey registration approach

**Question:** Carbon/HotKey APIs vs other event taps; Accessibility implications.

**Current state:** Not implemented.

## Extension model

**Question:** Declarative manifests, signed native bundles, XPC, and/or JS?

**Current state:** Experimental models only; see `docs/EXTENSIONS.md`.

## Updater

**Question:** Sparkle vs custom vs Mac App Store only?

**Current state:** Undecided; see `docs/DISTRIBUTION.md`.

## Minimum macOS version long-term

**Question:** Remain on macOS 27-only or expand support downward once features stabilize?

**Current state:** Preserved from project template: `MACOSX_DEPLOYMENT_TARGET = 27.0`.
