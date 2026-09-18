# ADR-0008: Window Switcher through public macOS APIs

- Status: Rejected
- Date: 2026-07-18
- Rejected: 2026-07-18

## Context

Commandly needs a keyboard-first way to inspect and switch among an application's individual
windows, with optional visual previews and contextual controls. A supplied reference project
demonstrates the same broad product category, but it is licensed under GPL-3.0 and contains behavior
that depends on private or unsupported macOS surfaces. Commandly's implementation and interface must
remain original.

The first proposal assumed that documented Accessibility, Core Graphics event-tap, AppKit, and
ScreenCaptureKit APIs could provide this runtime while Commandly kept its App Sandbox entitlement.
That assumption is not a valid release boundary. Apple's
[App Sandbox guidance](https://developer.apple.com/documentation/security/protecting-user-data-with-app-sandbox)
lists use of Accessibility APIs in assistive apps and terminating other running apps among the
activities incompatible with App Sandbox. Commandly is sandboxed, while the proposed switcher must
enumerate and control windows owned by other applications and includes a graceful-quit action.

Input handling has a separate constraint. A Core Graphics event tap receives the subscribed global
key-event stream and must inspect and reject unrelated events immediately; it does not receive only
the configured shortcut. Apple's
[`CGEventTapOptions` documentation](https://developer.apple.com/documentation/coregraphics/cgeventtapoptions)
distinguishes a passive listener, which cannot modify or divert events, from an active filter, which
can discard them. A sandbox-compatible listen-only design would still need the user's
[Input Monitoring approval](https://support.apple.com/guide/mac-help/control-access-to-input-monitoring-on-mac-mchl4cedafb6/mac)
and cannot suppress Option-Tab or replace Command-Tab. Active cross-application suppression has not
been established as a supported sandbox design.

## Decision

Reject registration or activation of the privileged Window Switcher runtime in the sandboxed
Commandly production app.

- Keep the App Sandbox enabled.
- Keep the current Infrastructure contracts, in-memory adapters, prototype app-target adapters,
  presentation model, settings schema, UI, and deterministic tests only as foundation/prototype
  work. Their presence is not evidence that the feature works in a signed sandboxed build.
- Do not register Window Switcher in the production launcher registry, install its event tap, start
  Dock Accessibility traversal, enumerate/control another application's windows, request Screen
  Recording for its thumbnails, or expose its Quit action from the sandboxed production runtime.
- Continue to require original presentation, settings, copy, symbols, layout, and motion. Do not copy
  or adapt source, assets, icons, branding, marketing text, tests, or an exact interface layout from
  the GPL-licensed reference project.
- Continue to forbid `CoreDock`, `SkyLight`, `MediaRemote`, private Core Graphics Services symbols,
  undocumented Dock/Spaces notifications, private visual-effect materials, AppleScript, shell
  fallbacks, and other private frameworks.

A future implementation requires a new accepted ADR covering one of these materially different
distribution and trust models:

1. a separately signed, non-sandboxed companion/helper with a narrow authenticated IPC contract,
   explicit Accessibility and Input Monitoring explanations, independent lifecycle/upgrade rules,
   and threat-model review; or
2. a direct-distribution Commandly build with App Sandbox disabled, including explicit security,
   privacy, signing, notarization, update, and product-distribution approval.

Neither option is authorized by this ADR. Apple documents helper separation as one possible response
to sandbox violations, but the helper's signing, launch mechanism, sandbox status, data exchange, and
distribution still require design and review; see
[Discovering and diagnosing App Sandbox violations](https://developer.apple.com/documentation/security/discovering-and-diagnosing-app-sandbox-violations).

## Retained prototype boundary

If a future ADR authorizes a privileged runtime, the existing prototype's clean-room and privacy
constraints remain useful requirements:

- Package boundaries own content-free Sendable snapshots, session-local identities, typed actions,
  failures, and enumeration/control protocols. They must not expose `AXUIElement`, AppKit views,
  event taps, or capture-framework objects.
- Window titles, thumbnails, queries, ordering, pointer positions, and input state are ephemeral
  private data and must never be logged, persisted, uploaded, or added to command history.
- Screen Recording is optional thumbnail authority, separately explained and requested only after
  explicit user intent. Captures are bounded and memory-only.
- Enumeration, control, current-Space classification, Dock traversal, and action support remain best
  effort even outside the sandbox. Unsupported or stale targets must return typed failures.
- The implementation may not claim complete cross-Space inventory or movement, Dock locking/click
  interception, universal Command-Tab replacement, universal media/lyrics/calendar integration,
  private WindowServer blur, or exact behavior for incomplete Accessibility trees.

## Consequences

- The sandboxed Commandly app does not currently provide a usable Window Switcher workflow. A
  launcher definition, settings page, panel, adapter, or passing test double must not be documented
  as a shipping feature.
- Screen Recording alone does not make the prototype functional; it supplies pixels, not authority
  to enumerate or control another application's windows.
- Automated tests remain valuable for contract, state, privacy, filtering, selection, geometry, and
  teardown behavior, but they cannot validate an unavailable production integration.
- The former signed-build manual matrix is now a future companion/direct-distribution acceptance
  matrix. It must not be run or reported as validation of the current sandboxed app.
- Disabling App Sandbox or adding a privileged helper would expand Commandly's authority and change
  its distribution model, so either choice requires explicit approval rather than an implementation
  detail hidden inside this feature.

## Rejected alternatives

- Treat public API as equivalent to sandbox compatibility: an API can be public while its use is
  incompatible with App Sandbox.
- Ship the prototype and rely on failure states: knowingly registering a core workflow whose needed
  cross-app authority is unavailable would violate Commandly's no-false-claims rule.
- Copy or translate the reference project's implementation, assets, settings layout, or tests:
  incompatible with Commandly's originality and license boundary.
- Link or invoke private Dock, Spaces, WindowServer, blur, or media frameworks: undocumented,
  brittle, and outside the security model.
- Silently disable App Sandbox or embed a broadly privileged helper: both materially change the
  product's security and distribution posture and require a separate accepted decision.
- Require Screen Recording for the entire feature: capture authority does not resolve the sandboxed
  Accessibility/control boundary.
