# Optional System Companion

This implements the foundation authorized by [ADR-0011](decisions/ADR-0011-optional-system-companion.md):
separate helper packaging, an authenticated metadata channel, bounded session/cancellation contracts,
and explicit setup UI. Window control, foreign app menus, selection replacement, keyboard triggers,
and app termination are **not implemented by this foundation**. Their closed request values are
reserved contracts; every such request currently returns `unsupportedOperation` before native work.
A connected helper is not an Accessibility, Input Monitoring, or screen-capture grant.

## User flow

Settings → System Integration starts with **Managed in Companion Setup**. Opening this pane never
registers, connects, starts a helper, or requests privacy access. Companion Setup validates the signed
pair and opens the companion's visible setup app through NSWorkspace. That separate app owns its
LaunchAgent, shows a concrete enable explanation, validates the pair and manifest, and registers only
on Enable Background Service. macOS can require background-item approval, shown in the setup window.
The sandboxed main cannot register an unsandboxed job itself; see the native finding below and
[setup ownership](SYSTEM_COMPANION_SETUP_OWNER.md).

Check Connection is a separate explicit action. It establishes mutual authentication, negotiates the
exact protocol/build, opens a short-lived session, and reads capability metadata. Ready therefore
means **metadata connection verified**, not that a cross-application command works. Main Refresh
rechecks its connection without opening a new one. Disconnect closes only this app's channel; Disable
Background Service in Companion Setup unregisters the agent. Registration errors preserve the actual
macOS state and show a sanitized domain/code. Setup actions are serialized; connection checks are
bounded by a five-second IPC deadline.

The generated Settings fixture labels itself and changes only memory. Its Setup, Check, Disconnect,
and Settings actions never touch SMAppService, XPC, signatures, user documents, or privacy grants.
Text uses shared Commandly sizing, headings and controls have accessibility labels, layout wraps its
buttons, and the shared Settings body scrolls at larger text sizes.

## Package and launch layout

- `SystemCompanionKit` depends only on `Infrastructure` and Apple frameworks. Infrastructure owns
  the public installation, metadata, wire, capability, and typed future-action contracts.
- `CommandlySystemCompanion` is a separate app-shaped helper target with the configured team
  `RLF9X72HRT`, identifier `com.businessmate360.Commandly.SystemCompanion`, hardened runtime, and
  **no App Sandbox entitlement**. It has no additional capability entitlements in this foundation.
- The main app remains sandboxed and retains its existing entitlements unchanged. It already claims
  `group.com.businessmate360.Commandly`; no global Mach lookup exception is introduced.
- Copy phases embed the separately signed helper at
  `Contents/Library/Helpers/CommandlySystemCompanion.app`. The helper's own Copy Files phase embeds
  its LaunchAgent at `Contents/Library/LaunchAgents/com.businessmate360.Commandly.SystemCompanion.plist`
  inside that helper app.
- The plist uses `BundleProgram` `Contents/MacOS/CommandlySystemCompanion`, fixed `--service`
  arguments, and an Aqua login-session
  restriction. It vends `group.com.businessmate360.Commandly.SystemCompanion` through `MachServices`.
  It has no root daemon, shell, direct Process launch, RunAtLoad, KeepAlive, or installer copy step.
  Once explicitly registered, launchd can start it on demand for Check Connection.
- An ordinary argument-free application launch opens visible setup without a listener. The main
  uses NSWorkspace with a new application instance so an existing headless service cannot absorb
  the setup request. It passes no command arguments, environment, Apple events, or private payloads.
- The helper validates its own signature and non-root user/audit session before creating a listener.
  SIGTERM/SIGINT close the listener and invalidate its sessions. Connection invalidation/interruption
  independently clears per-connection work. A forced process exit is ultimately handled by XPC loss.

Apple documents Mach/XPC service names as one child of an app-group ID, including communication
between a sandboxed and nonsandboxed process. Its current DTS guidance says the nonsandboxed server
does not need the group entitlement simply to vend that endpoint. The helper does not access any
shared container or group Keychain. This avoids granting it unrelated group data access.

## Signing and consent evidence

The signing policy binds the peer to `anchor apple generic`, the compiled team ID, and the exact
main/helper identifier. `SecRequirementCreateWithString` validates each static requirement before
Foundation sees it. Each `NSXPCConnection` sets its peer requirement exactly once before activation;
the listener delegate applies the corresponding main-app requirement to each accepted connection. No private audit token, PID-only
signature check, self-reported caller identity, environment override, or unsigned development bypass
is present. Current-process validation makes an ad-hoc app or helper fail closed.

The public XPC header defines signing enforcement on received messages/replies, not prevention of
initial outbound disclosure to an untrusted Mach-name replacement. This phase therefore sends only
metadata/build and opaque request/session IDs. The live `CompanionBoundTransport` authenticates a
bounded bootstrap reply carrying an anonymous listener endpoint and verifies that bound endpoint
with a fresh challenge before admitting metadata. See [the bound channel](SYSTEM_COMPANION_BOUND_CHANNEL.md).
All future action payloads still fail locally before transmission. Bound-channel tests passed, but
native connection acceptance remains required before enabling private text or action dispatch.

`getaudit_addr` supplies the process's public audit-session identifier. Incoming connections and
outgoing replies compare the kernel-reported EUID and audit session with that non-root context.
Incoming messages recheck the public current connection synchronously before hopping to the engine.
A missing/unavailable session identifier is a prerequisite failure, not a reason to skip validation.

Preflight verifies the signed main/helper bundles, their matching `CFBundleVersion`, the main's sandbox
and existing app-group entitlement, and an embedded main provisioning profile. Profile **presence**
is a runtime prerequisite, not proof that Apple authorized its claim: signed-build inspection and a
real sandbox-to-agent handshake are still acceptance gates. Release builds must increment their
build number and keep the app/helper build and wire version coordinated. Updating the signing team
requires updating the compiled policy and both target settings together.

Read-only inspection on 2026-09-14 confirmed that the root task's development main app passed the exact
Apple-anchor/team/bundle requirement. Its embedded profile authorized the existing group and team;
that development profile expires on 2026-09-21 at 17:56:36 UTC. An earlier `make verify` artifact was
ad-hoc because verification deliberately disables signing. These are different artifacts. Neither
inspection proves that the new helper has been signed, registered, or accepted by launchd.

The first actual registration attempt failed before a helper process started. No privacy prompt or
cross-app operation was performed. Before corrected live activation, inspect the freshly built **pair**, actual embedded
paths/entitlements/profiles, and signing. Then use the explicit Enable and Check Connection flow on
controlled local data. Check wrong-team/wrong-identifier peers, user/session mismatch, app-group
lookup, approval denial, helper crash/reconnect, and disable/unregister. Developer ID notarization and
App Store suitability are not established by a development build.

## Wire and authority limits

The metadata request selector accepts and returns Data; the bootstrap additionally returns a native
anonymous listener endpoint. Data envelopes carry canonical sorted JSON, not an
arbitrary object graph or selector name. The decoder rejects noncanonical/duplicate/unknown keys,
unknown enum cases, malformed structures, nesting deeper than 16, oversized bodies, out-of-range
lifetimes, and unbound action handles before dispatch. Requests are at most 256 KiB, replies 512 KiB,
and reviewed text 64 KiB UTF-8. Future window/menu collection limits are 200/500 respectively; no
collection implementation exists yet.

The server admits at most four connections and eight ordinary in-flight requests
per peer, with two reserved cancellation/close admission slots. The engine negotiates protocol 1 and
an exact build before creating a random session token. Sessions expire after five continuous-clock
minutes. A request UUID and sequence are both unique for the connection; after 256 requests the
connection expires instead of evicting history and making old requests replayable.

Metadata work has a maximum five-second continuous deadline. Cancellation and session/connection
invalidation cancel the cooperative handler and discard later results. The client transport's own
independent deadline closes the entire channel on timeout/cancellation; the server then clears all
associated sessions. Late callbacks cannot resurrect a closed connection or negotiated session.
There are no logs, persisted handles, captured titles/text, raw key-event streams, shell commands,
AppleScript, arbitrary AX attributes/actions, user-selected paths, or network endpoints in the wire.

## Integration

1. Apply the focused off-tree Package/project patches, then publish the new owned files. The helper
   target is an app dependency and Copy Files signs it on embedding. Keep the main entitlements intact.
2. Retain `SystemCompanionApplicationServices.live()` in AppRuntime, or `.inMemory()` for generated UI.
   Construction is inert. Inject `.settings` into `SettingsRootView` and route a System Integration
   pane there; the prepared shared patch includes searchable sidebar metadata.
3. On actual runtime teardown call `.manager.disconnect()` without unregistering the user's enabled
   background item. XPC process loss is the final session invalidation boundary. This foundation has
   no native activity requiring an extra deferred-termination approval step.
4. An app/helper update requires unregister/register through the supported explicit Disable/Enable
   flow in Companion Setup. Before uninstall, disable the companion first. A failed unregister does not imply a stopped
   launchd registration; show recovery and retain the app until it is resolved. Native privacy grants
   are managed independently, and this foundation never requests them.

## Verification

Fourteen package tests passed in an isolated temporary SwiftPM workspace with the actual shared
production sources and fake transports, registration, metadata, and clocks. They cover canonical
wire validation, payload/depth limits, syntax-validated signing requirements, user/session mismatch
policy, build/protocol/reply identity mismatch, honest future capability rejection, complete replay
ledger bounds, expiry, cancellation, timeout, invalidation, stale-reply rejection, initial inertness,
approval state, and unregister failure. Tests do not register, start, or connect to a native helper.

The separate helper target built successfully in an isolated Xcode project for arm64 and x86_64 with
code signing disabled; its executable was not run. Shared package and UI/settings test sources passed
strict Swift 6 typechecking with warnings as errors. The generated Settings tests and full integrated `make verify` passed in
`/tmp/commandly-video-verify-tranche13-companion.log`. The signed build passed in
`/tmp/commandly-video-native-tranche13-build.log`; the main and embedded helper both passed strict
code-signature validation against their exact identifier/team requirements. Main sandbox and
provisioning-profile presence, helper hardened runtime with sandbox disabled, and the embedded
LaunchAgent BundleProgram path were inspected. Native Settings in the explicitly labeled in-memory
fixture passed Disabled → enable explanation → Enabled/Connection Unchecked → Check Connection →
Ready/Metadata Connection → Disable → Disabled. No helper registration, process activation, or
actual native metadata handshake is claimed by that generated setup flow.

## Primary Apple references

- [App Groups entitlement and IPC namespace](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.application-groups)
- [Apple DTS: sandbox-to-Mach-service app-group authorization](https://developer.apple.com/forums/thread/820631)
- [SMAppService](https://developer.apple.com/documentation/servicemanagement/smappservice)
- [Updating to the Service Management API](https://developer.apple.com/documentation/servicemanagement/updating-your-app-package-installer-to-use-the-new-service-management-api)
- [Public peer signing requirement](https://developer.apple.com/documentation/foundation/nsxpcconnection/setcodesigningrequirement(_:))
- Installed macOS 27 SDK headers: Foundation `NSXPCConnection.h`, ServiceManagement `SMAppService.h`,
  Security `SecCode.h`/`SecStaticCode.h`, and public `bsm/audit.h` (`getaudit_addr`; private audit-session
  Mach-port APIs are not used).

## Focused native acceptance launch

DEBUG `--commandly-productivity-fixture --commandly-live-companion` keeps unrelated productivity
services generated/in-memory but uses the real signed companion setup. The second flag alone does
not register or connect anything: use Companion Setup, its Enable Background Service, and then
Check Connection in the main app. The System
Integration pane does not show the generated-setup label in this mode. Release builds do not have
this override. It is intended for signed native acceptance without loading live clipboard, Finder,
AI, recording, or display test data.

## Native installation finding and corrected setup acceptance

The first real Enable attempt in the signed app failed with SMAppService error 1 and remained
Not Installed; no helper process started. The bounded OS transaction identified the cause:
a sandboxed registering app cannot register a non-sandboxed executable. This is the documented
macOS 14.2+ restriction in [Apple DTS guidance](https://developer.apple.com/forums/thread/802443).
The setup owner is now the companion's own visible non-sandboxed app, preserving the main app
sandbox. Forty-two isolated package tests and an isolated helper build passed. The earlier
direct-registration path is historical and is not used by the main. See the amended
[ADR-0011](decisions/ADR-0011-optional-system-companion.md).

On September 14, 2026, integrated `make verify` passed in
`/tmp/commandly-video-verify-tranche16-setup-owner.log`; clean signed build passed in
`/tmp/commandly-video-native-tranche16-setup-owner.log`. Both exact team/identifier requirements
and deep strict bundle validation passed. Effective entitlements retain the main sandbox and no
helper sandbox; the helper-owned LaunchAgent manifest was inspected in the clean product.

The user-approved native acceptance passed: opening Companion Setup left the job absent;
explicit Enable reported Enabled and `launchctl` confirmed Service Management registration owned
by the helper. Main Check Connection reached Ready — Metadata Connection and started its separate
headless process. Disconnect cleared the channel; an explicit second Check reached Ready again.
Setup Disable reported Disabled, removed the launchd job, and terminated the headless process.
Main Refresh cleared Ready; checking the disabled helper failed with recovery guidance. Closing
setup terminated its UI process. No additional macOS privacy permission was requested or granted.
The test leaves the helper disabled and unregistered. Separate bundled-fixture results are recorded
below; registered-service replacement and cross-app capability validation remain incomplete gates.

### Signed bundled-fixture acceptance — September 17, 2026

The reviewed signed bundled-XPC harness passed exact-peer metadata, local rejection of a generated
future action before native exchange, listener revocation/fresh endpoint, revoked-offer rejection,
and same-team wrong-helper rejection. Earlier separate fixtures passed wrong-app self/server and
kernel-observed different-audit-session rejection. On September 17, the correct-client fixture also
completed real helper self-exit, a permanently terminal old transport with no second bootstrap, and
an explicit new authenticated endpoint/metadata session from a distinguishable fresh process. The
old transport stayed terminal after that fresh connection. Root found no remaining CompanionHarness
process after the run. Receipt: `/tmp/commandly-companion-native-harness-respawn/native-correct.log`.

The earlier five-second fresh-offer failure was traced to launchd's recorded 10-second respawn
throttle. Only the harness's initial control offer on a fresh correct-helper connection after verified
exit receives a typed 15-second discovery deadline. Ordinary control requests and production
bootstrap/bind/metadata deadlines remain five seconds; the 80-second harness watchdog is unchanged.
No retry or timeout-as-success was introduced. Strict Swift 6 preparation passed 53 tests in 10 suites
with warnings as errors (`/tmp/commandly-companion-native-harness-respawn/test.log`).

This fixture registers no service and requests no privacy grant. It does not establish restart or
replacement of a registered SMAppService job under the production Mach name. Wrong-team/different-EUID
peers, malicious endpoint forwarding, native replay/stall cases, and cross-app actions remain pending.
The typed bootstrap-endpoint injection used by the off-tree fixture is not published in the root
source; the production path still uses its fixed Mach service. See
[the bound-channel evidence and limits](SYSTEM_COMPANION_BOUND_CHANNEL.md#signed-bundled-service-restart-acceptance--september-17-2026).
