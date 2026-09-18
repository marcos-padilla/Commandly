# ADR-0011: Optional system companion for cross-application features

- Status: Accepted — product owner approved implementation on 2026-09-14
- Date: 2026-09-14
- Related: [ADR-0008](ADR-0008-window-switcher-public-api-boundary.md), [video requirements](../VIDEO_FEATURE_PARITY.md)

## Accepted decision

Build an **optional, separately signed, non-sandboxed per-user companion** while keeping
the main Commandly app sandboxed. The companion would supply narrowly typed cross-application window,
application-menu, selected-text, and configured keyboard-trigger operations. It would run with the
logged-in user's authority, never root, and remain unregistered until the person enables System
Integration in Commandly. This is an architecture proposal, not an installed helper or a working
permission claim. No new helper target, launch registration, permission, or entitlement is added by
this document. The product owner explicitly approved the proposed optional companion in this task;
actual registration and native privacy grants still follow the point-of-use consent flow below.

The video goal includes behavior that the existing sandboxed app cannot truthfully supply: complete
window control/switching, foreign-application command discovery, external text replacement/expansion,
and global key remapping. Graceful/force application quit also needs a supported release boundary.
ADR-0008 explicitly requires a new accepted decision before a helper or unsandboxed distribution.
Passing existing prototype tests does not remove that constraint.

## Proposed product behavior

1. A System Integration settings page explains the exact additional access and shows Not Installed,
   Disabled, Needs Approval, Ready, Version Mismatch, or Unavailable. The default is Disabled.
2. Enable opens the verified companion’s visible setup application. That non-sandboxed application
   owns its bundled per-user LaunchAgent and explicitly registers it through `SMAppService`. macOS
   retains its own background-item approval. Nothing is copied into system LaunchDaemons or run as root.
3. Each capability is off until activated. Window/menu/selection commands explain Accessibility at
   the point of use. Global input monitoring/remapping has its own explanation and toggle. Screen
   pixels remain under the existing separate, explicit capture boundary.
4. Disable stops configured event taps and active sessions, invalidates the channel, and unregisters
   the service. A revoked OS grant immediately disables dependent actions with Settings recovery.
5. The main sandboxed app remains usable without the companion. It must not expose a silently broken
   privileged command as if it works; unavailable commands show the concrete prerequisite.

Acceptance of this ADR authorizes implementation of that optional architecture. It does not approve an
actual Accessibility/Input Monitoring grant, live text replacement in user documents, new privileged
capabilities, App Store submission, or a notarized release. Those actions keep their own review and
native consent boundaries.

## Target, launch, and distribution boundary

Proposed first-party executable: `CommandlySystemCompanion`, embedded in the application bundle,
with bundle identifier `com.businessmate360.Commandly.SystemCompanion`. The companion app owns
a LaunchAgent plist in its own Contents/Library/LaunchAgents directory. It uses a bundle-relative
executable location and `SMAppService.agent(plistName:)` from that non-sandboxed setup process.
The sandboxed main app opens the verified companion with NSWorkspace application launching; it
never registers the non-sandboxed job itself. Its lifecycle must not depend on spawning `Process` from the sandboxed app:
directly launched helpers inherit that sandbox, as Apple's sandbox guidance explains.

The agent's Mach service must use a sandbox-compatible app-group namespace whose entitlement and
registration behavior are proved in the signed development build before integration is enabled.
Do not add a global Mach-lookup exception or make an unverified service-name assumption. If the chosen
app-group transport cannot be established, return to this ADR for a reviewed alternative.

Both components use hardened runtime and the same configured signing team. A production companion
must be signed and embedded with the app, included in notarization, and covered by the app's update
process. Do not add an independent downloader or self-updater. On incompatible protocol/build versions,
stop sessions and require a matching installation. Re-register changed executable/plist versions
through the supported Service Management lifecycle. Uninstall instructions include explicit service
unregistration and permission recovery. App Store suitability is not established by this design;
direct Developer ID distribution is the initial validation target, without removing the main sandbox.

## Authenticated IPC and authority

Use public Foundation XPC. Before activating each direction, apply exactly one static, validated
`NSXPCConnection.setCodeSigningRequirement` binding the peer's Apple signing anchor, configured team,
and exact bundle identifier. Validate the requirement syntax with Security before passing it to the
API, because malformed requirements cause a fatal error. Check the expected effective user/session
and reject mismatches. Do not trust a caller-supplied PID, bundle identifier, team name, filesystem
path, or self-reported capability. Do not use the private `auditToken` property or race-prone PID-only
code-signature checks. Unsigned/ad-hoc development builds fail closed for real privileged operations;
unit tests use injected transports rather than weakening production peer authentication.

The channel accepts a versioned bounded envelope and a closed operation enum. Proposed wire values:
protocol version, request UUID, capability, operation, session token, and bounded typed arguments.
Replies are typed result values/errors. Limits start at 256 KiB/request, 512 KiB/reply, eight in-flight
requests, 200 windows, 500 menu entries, and 64 KiB reviewed text. Per-operation deadlines/cancellation
and session invalidation are mandatory. Larger workloads require pagination or a reviewed contract,
not relaxed arbitrary payloads. Unknown operations/versions and malformed values are rejected before
performing native work.

The companion creates random session-scoped handles for native targets. Every action revalidates
the process identity, target existence, current capability grant, session, and requested action.
Snapshots expire when the app changes or the session closes. Connection loss stops event taps and
clears windows/menu/selection/input state. No operation accepts shell text, AppleScript, a command path,
arbitrary AX attribute/action names, raw key-event streams, or unrestricted filesystem/network access.

## Initial capability contracts

| Capability | Read operations | Explicit write/control operations | Required safeguards |
|---|---|---|---|
| Window navigation | Bounded original window summaries | Activate, minimize, close, approved layout | Session-bound handles; stale-window/process checks; no universal Spaces claims |
| App commands | Current app's bounded accessible menu tree | Invoke one reviewed enabled menu action | App-switch invalidation; identity/path fingerprint; no arbitrary AX action |
| Selected text | Explicit current editable selection snapshot | Replace exact unchanged selection with reviewed text | Reject secure/password fields; revalidate app/element/range/content; preserve host Undo where supported |
| Configured triggers | Only state needed for configured Hyper/single/double-tap/expansion triggers | Dispatch typed configured command or bounded reviewed expansion | Secure Input handling; timeout/state reset; no unrelated event persistence; per-feature opt-in |
| App lifecycle | Bounded running-app summaries | Explicit graceful/force quit and reviewed rules | Protect system/own components; process-reuse checks; honor refusal/unsaved-document outcomes |

The keyboard event tap necessarily receives subscribed key events before filtering them; this is
disclosed. Unrelated events are passed through immediately and never logged, transmitted to the main
app, or retained. Automatic snippet matching keeps only a bounded active suffix when expansion is
explicitly enabled, clears it on app/field/secure-input changes, and never operates in secure fields.
No AI provider receives these inputs through this companion. Adding AI automation over a capability
requires a separate exact-action approval and disclosure boundary.

Focus app blocking may build on reviewed capability contracts later. Website filtering, network
extensions, dictation/audio, arbitrary extension execution, sync/accounts, and unattended remote
control are outside this companion proposal and are not implied by approval.

## Threat model and review gates

| Threat | Required control and evidence |
|---|---|
| Unrelated local app impersonates Commandly | Bidirectional OS-enforced signing requirement; wrong-team and wrong-bundle integration tests |
| Malformed or replayed IPC causes control | Closed schemas, hard bounds, request/session binding, idempotence and stale-token tests |
| App switch, PID reuse, or edited selection redirects an action | Native identity and exact state revalidation immediately before mutation; deterministic race tests |
| Key monitoring becomes ambient collection | Capability opt-in, minimal bounded state, Secure Input tests, no raw-event IPC/logging/persistence |
| Disconnection leaves active interception | Invalidation-driven teardown and cancellation; signed-process crash/reconnect tests |
| Compromised trusted main app abuses granted capabilities | Narrow operation surface and user-visible capability toggles reduce scope; same-signer compromise remains a material residual risk |
| Update swaps or mismatches privileged code | Verified embedded signing/protocol identity; no runtime code download; reject mismatched versions |

Before production registration: implement fake-transport/adapter tests; audit source for forbidden
APIs and private-data logging; run `make verify`; validate signed sandbox-to-agent registration and
mutual authentication on a generated test app; inspect effective signing/entitlements; exercise
permission denial/revocation, lock/unlock, helper crash, disable/unregister, and stale-target rejection.
Only then activate individual feature integration for intentional live acceptance. Full privacy,
accessibility, lifecycle, and distribution evidence belongs in the relevant feature docs.

## Alternatives and consequence

Keeping the current sandbox-only boundary leaves the affected video requirements pending. Removing
App Sandbox from the whole app broadens the authority of every existing network/parser/UI component;
that is a separate decision and is not proposed here. Private APIs, broad AppleScript/shell fallbacks,
root daemons, and silent permission prompts remain forbidden.

The optional companion adds real packaging, authentication, upgrade, recovery, and testing work. It
does not guarantee support for every app, protected field, window, Space, or shortcut. Unsupported
targets must be reported honestly rather than emulated by an unsafe fallback.

## Primary sources checked

- [Apple: sandbox violations and helper separation](https://developer.apple.com/documentation/security/discovering-and-diagnosing-app-sandbox-violations)
- [Apple: SMAppService](https://developer.apple.com/documentation/servicemanagement/smappservice)
- [Apple: NSXPCConnection peer signing requirements](https://developer.apple.com/documentation/foundation/nsxpcconnection/setcodesigningrequirement%28_%3A%29)
- Installed macOS 27 Foundation `NSXPCConnection.h` confirms the public code-signing method and
  the effective-user/session properties; it does not expose a public audit-token property.

## Native registration correction — 2026-09-14

The first signed native acceptance failed before any helper started. The exact Service Management
transaction reported that its target must be sandboxed because its registering app is sandboxed
(`/tmp/commandly-companion-registration-transaction.log`). [Apple DTS documents this rule](https://developer.apple.com/forums/thread/802443):
sandboxed owner → non-sandboxed job is unsupported from macOS 14.2 onward. Signature checks and
mock registration tests did not expose this platform restriction.

The accepted main-sandbox/optional-per-user-companion decision is preserved. Setup ownership moves
into the separate non-sandboxed companion app, which may register a non-sandboxed per-user job.
The main app validates and explicitly opens that setup UI; the companion registers only after its
own visible user action. This revised packaging/launch/status/disable flow remains subject to signed
native acceptance. The initial direct-registration implementation is not a working installation path.
