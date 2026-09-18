# Open Questions

## Persistence backend

**Question:** Should durable storage use SwiftData, Core Data, SQLite (e.g. GRDB later), or file-based Codable stores?

**Current state:** Only contracts + `InMemoryPersistenceStore`. No backend selected.

## Final license

**Question:** Open-source license vs proprietary/commercial?

**Current state:** Temporary all-rights-reserved `LICENSE` (Copyright 2026 Commandly).

## Global hotkey registration approach

**Question:** When should a future global-input feature use Carbon hot keys versus a narrowly scoped
event tap?

**Current state:** Launcher, registered application/tool, and Command Wheel shortcuts share Carbon
`RegisterEventHotKey` registration and do not require Accessibility. Shelf's default shortcuts are
owned by its two registered tools rather than a separate runtime route. The proposed Window Switcher
active event tap would receive the subscribed global key-event stream, filter unrelated events
immediately, and suppress its configured gesture. That runtime is rejected and unregistered because
its event suppression and cross-application Accessibility boundary is not an established App
Sandbox design. A listen-only monitor would require Input Monitoring and could not suppress or
replace Command-Tab. New features do not inherit an event-tap exception. See the rejected
[ADR-0008](ADR-0008-window-switcher-public-api-boundary.md).

## Window Switcher privilege and distribution model

**Question:** Should Window Switcher use a separately signed non-sandboxed companion with narrow
authenticated IPC, or should Commandly have a separately approved direct-distribution build without
App Sandbox?

**Current state:** Neither model is authorized. The sandboxed production app keeps Window Switcher
unregistered and disabled. A decision must cover threat modeling, signing/notarization, Mac App Store
eligibility, update ownership, Accessibility and Input Monitoring explanations, IPC authentication,
failure/revocation behavior, and migration before implementation resumes. See
[ADR-0008](ADR-0008-window-switcher-public-api-boundary.md).

## Extension model

**Question:** Declarative manifests, signed native bundles, XPC, and/or JS?

**Current state:** Experimental models only; see `docs/EXTENSIONS.md`.

## Updater

**Question:** Sparkle vs custom vs Mac App Store only?

**Current state:** Undecided; see `docs/DISTRIBUTION.md`.

## Minimum macOS version long-term

**Question:** Remain on macOS 27-only or expand support downward once features stabilize?

**Current state:** Preserved from project template: `MACOSX_DEPLOYMENT_TARGET = 27.0`.
