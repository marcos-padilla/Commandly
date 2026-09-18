# Companion channel bound to a helper instance

This extends the optional companion's metadata foundation under [ADR-0011](decisions/ADR-0011-optional-system-companion.md).
It implements a public Foundation anonymous-endpoint bootstrap and a second authenticated handshake.
**No cross-application actions are enabled.** Window/menu/selection/trigger/lifecycle requests remain
locally rejected by both client transport layers and unsupported by the helper engine. The current
usable operation is the existing generated build/capability/status flow, including request-ID echoes.
This does not prove native signing, registration, an OS grant, or future action safety.

The source and fixture tests below are implemented. Signed native acceptance of the bound endpoint's
successful connection, explicit disconnect/reconnect, and service-unregister path passed on September
14, 2026. Separate signed bundled-XPC fixtures passed identifier/session rejection and listener
revocation, then completed helper self-exit and explicit fresh-instance acceptance on September 17.
Registered-service replacement, wrong-team/different-user peers, and other adversarial cases remain pending;
see [native evidence](SYSTEM_COMPANION.md#native-installation-finding-and-corrected-setup-acceptance).

## Why there are two channels

Apple's public signing requirement checks incoming messages and replies. Applying the requirement
to a Mach-name connection does not promise to prevent its first outbound request reaching an
untrusted replacement. The named request therefore contains only protocol/build metadata and generated
UUID challenges, with no target, text, path, command, or action. No later action may use that name.
The requirement is validated with Security and set exactly once before each connection activates.
[Apple signing requirement](https://developer.apple.com/documentation/foundation/nsxpcconnection/setcodesigningrequirement%28_%3A%29)
and the installed macOS 27 SDK's `usr/include/xpc/connection.h`,
`xpc_connection_set_peer_code_signing_requirement`, describe received-message enforcement.

Apple documents `NSXPCListenerEndpoint` as identifying one specific listener and returning to the
original listener when used to create a connection. The Foundation header says listener-endpoint
invalidation cannot be re-established. The C XPC header additionally states that endpoint connections
have no rediscoverable name and become invalid on listener exit, crash, or cancellation. Together,
these support the peer-instance design; applying those guarantees to the complete Foundation flow
still requires the controlled native replacement/crash acceptance below. No private XPC property is
used. [Apple endpoint documentation](https://developer.apple.com/documentation/foundation/nsxpclistenerendpoint),
[endpoint initializer](https://developer.apple.com/documentation/foundation/nsxpcconnection/init%28listenerendpoint%3A%29),
[endpoint connection](https://developer.apple.com/documentation/xpc/xpc_connection_create_from_endpoint%28_%3A%29).

The installed Foundation `NSXPCConnection.h` declares the endpoint `NSSecureCoding` and
`NS_SWIFT_SENDABLE`; connections and listeners themselves are non-Sendable. The endpoint is a directly
typed reply argument, not an element of an arbitrary collection. Apple's XPC guide explains secure
argument classes and when collection-class allowlists are needed.
[Apple XPC interfaces](https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPSystemStartup/Chapters/CreatingXPCServices.html).

## Closed flow and disclosure boundary

| Step | Channel and data | Required before advancing |
|---|---|---|
| Local preparation | No IPC | Valid compiled peer requirements, signed current app, non-root EUID/audit session |
| Bootstrap hello | Named channel: build/version, request UUID, client nonce | Helper authenticates app signer and rechecks kernel EUID/audit session synchronously |
| Listener offer | Named reply: matching hello, listener UUID/server nonce, one secure endpoint | App receives an OS-authenticated exact-helper reply, verifies EUID/session, canonical metadata, expected challenge/build/version/generation/deadline |
| Bind | Endpoint channel only: full ticket plus a new challenge | Helper checks exact app signer, user/session, ticket, first connection/first bind, and its monotonic expiry |
| Bind reply | Endpoint channel only: exact proof echo | App checks exact helper signer, user/session, proof identity, generation, and combined deadline |
| Metadata session | Endpoint channel only: existing closed metadata envelopes | Both gates are ready; engine still requires build/version/session/replay checks |
| Any loss or cancellation | Both connections close | Ticket and session are cleared; same transport instance cannot reconnect |

Bootstrap/proof JSON is canonical and limited to 4 KiB with at most eight nesting levels. Existing
metadata limits remain 256 KiB/request, 512 KiB/reply, eight pending calls, unique request UUID/sequence,
256-request ledger, and five-minute session lifetime. A single five-second monotonic client deadline
covers the complete bootstrap and bind sequence; each reply also checks its deadline directly, so
late callback scheduling cannot extend it. The helper independently expires unbound offers after
five seconds and checks that deadline synchronously during acceptance/bind. The named listener's
four-peer limit permits at most four offers and four corresponding bound peers.

The original `NativeCompanionTransport` stays metadata-only for compatibility. The new explicit
connection factory uses `CompanionBoundTransport(build:)` with `NativeCompanionBoundConnector`.
Constructors and connection-status reads remain inert. The client keeps the named bootstrap connection
for lifetime observation but sends no subsequent request on it. There is no endpoint-to-name fallback,
automatic retry, generic byte-payload echo, or operation that enables reserved actions.

## Ownership, shutdown, and stale work

`CompanionBoundListener` owns the anonymous listener, strong delegate, engine, expiry, and accepted
peer owner. Named interruption/invalidation and helper shutdown revoke the listener and explicitly
invalidate the accepted peer. Endpoint loss invalidates the client instance and both native
connections. Late callbacks are ignored by generation and pending-request identity. Cancellation and
timeout resolve pending continuations once, cancel timeout tasks, and remove retained endpoint objects.

Foundation invokes acceptance on its queue and supplies a non-Sendable connection. A small internal
`CompanionBoundConnectionOwner` uses the OS lock's explicit unchecked-state API for this interop
boundary; it does not add an unchecked Sendable conformance to the native object. The owner never
returns the stored connection. Acceptance/activation and terminal-close state serialize under the
lock; invalidation removes the resource under the lock and closes it outside. Activation callbacks
only invalidate a separate gate and enqueue owner cleanup, avoiding synchronous lock reentry. A
close before acceptance rejects and invalidates the new resource without activation. A close after
acceptance releases exactly that retained peer. Fake-resource tests exercise both orders and races.

The asynchronous `CompanionClient.isConnected` and `SystemCompanionService.installation` recheck
generation after awaiting lower-level state. A disconnect/disable during a suspended check cannot
publish stale Ready or clear a newer checked status. A canceled installation snapshot reports
Unavailable/Canceled; the next explicit refresh reads current registration again.

## Threat analysis and remaining gates

| Threat | Implemented control | Remaining evidence |
|---|---|---|
| Wrong signer or different user/session at the named service | OS receive requirement, kernel user/session check, hello-only disclosure | Wrong-team/different-EUID peers and adversarial production named-service checks |
| Replaced service after bootstrap | Bound Foundation endpoint, no named fallback, ticket/proof equality | Crash/replacement under the registered production Mach name |
| Substituted endpoint or replayed ticket | Authenticated offer, exact fresh proof, one peer/one bind, helper expiry | Native malicious endpoint forwarding and replay/stall cases |
| Disable/quit races with setup or bind | Terminal owner, generation checks, peer invalidation and session teardown | Repeated registered-service connect/disable and process-exit races |
| Timeout callback runs late | Continuous deadline checked at acceptance, bind, and reply receipt | UI remains responsive on native stalled handshake |
| Future private payload sent too early | Both client layers reject all future actions before IPC; engine also refuses | Separate capability review before changing either gate |
| Trusted code compromised, or same-team/exact-bundle attacker has signing authority | Closed metadata surface and no action handlers in this phase | Residual trust boundary; endpoint authentication is not a defense against compromised trusted code |

## Deterministic tests and native acceptance

On 2026-09-14 the isolated Swift 6 suite passed 32 test functions across six suites (18 new,
including parameterized negative cases), with warnings as errors, macOS 14 deployment, and
Apple frameworks only. Receipt: `/tmp/commandly-companion-bound-channel-slice/test-final.log`.
Full integrated verification subsequently passed in tranches 14 and 16; the tranche 16 clean signed
app/helper completed the connection/disconnect/reconnect/unregister acceptance described above.
New tests cover inert construction, exact challenge/instance matching,
wrong-signer/user error propagation, replaced/invalid endpoints, no request disclosure before bind,
local future-action rejection, cancellation, stale bootstrap/bind/metadata replies, terminal
no-rebinding behavior, wire bounds, deadline admission, one-use tickets, retained peer release,
acceptance/close and bind/close races, and stale Ready snapshots. Tests use generated values,
injected transports/clocks, and fake peer resources. The native future-action guard test never
reaches signing or connection creation. None is proof of OS signing or kernel endpoint behavior.

Before any cross-app payload is allowed, a separate reviewed native acceptance must:

1. Run full repository verification, build the current signed app/helper pair, and inspect exact
   bundle/team requirements, main sandbox/group/profile, helper hardened runtime, embedded paths,
   and matching build. Keep the same public requirements; do not add an unsigned test bypass.
2. After the separately reviewed setup-owner correction (a sandboxed main app cannot register an
   unsandboxed SMAppService job), use the generated productivity fixture with the reviewed
   live-companion override. Explicitly enable through the companion's own setup UI, obtain any
   required macOS background-item approval, then Check Connection using the
   bound factory. Confirm Ready/Metadata only, responsive UI, and no privacy prompt or cross-app read.
3. Use generated harness peers to separately test a wrong helper identifier, wrong app identifier,
   wrong team when a suitable identity is available, and different EUID/audit session. The metadata
   check must fail. Record only outcome/counters; do not log private payloads or user data.
4. With a valid bound endpoint, terminate that generated helper instance and start a distinguishable
   replacement registered under the same name. The old transport must fail, must not bootstrap again,
   and must not deliver a generated future-action sentinel. Only a fresh explicit Check may create a
   new instance. Do not replace the production installed helper or register unrelated agents as a shortcut.
5. In the harness, revoke the offered listener before bind; replay an offer and bind; delay each stage
   past five seconds; cancel during each stage; close the named connection immediately before and
   after bound acceptance. Every old instance must stay closed, with no retained accepted peer or late Ready.
6. Disable through Settings and verify actual unregistration and both connection closures. Repeat
   app quit/helper exit and background-item approval denial. Preserve recovery on failure.

Steps requiring another signing identity/login session or a privileged test harness are pending
until available and explicitly authorized. Do not mark them passed from fake-transport results.
The channel remains metadata-only until this evidence and the next capability's target/permission
review are complete.

### Signed bundled-XPC harness — September 14, 2026

Root reviewed and signed generated standalone clients and peers with the existing Apple Development
identity. Each app passed the exact configured team/identifier requirement and deep strict signature
validation. The fixtures register no LaunchAgent and request no privacy grant. An off-tree additive
typed bootstrap-endpoint initializer changes only the first connection destination; all production
self/peer signing, effective-user/audit-session, bound endpoint, timeout and terminal-state checks
remain active. This initializer has not yet been published into the repository.

The native fixtures passed exact-peer metadata; rejection of a generated unimplemented action before
any native exchange; listener revocation and a fresh endpoint; a revoked offer before bind; same-team
wrong-app self/server rejection; same-team wrong-helper rejection; and a kernel-observed different
audit-session rejection. Independent control replies before/after negative cases confirmed that
the peer was alive, avoiding a missing-process false positive. A revoked offer may fail as
Disconnected or Expired Session depending on invalidation delivery, but the case separately requires
completion before the original five-second deadline and zero metadata exchanges.

The September 14 helper-exit attempt confirmed actual control-channel closure and a permanently closed
old bound transport with no second bootstrap. A fresh bundled-service offer from the same still-running client
then timed out. Fixed-step diagnostics isolate that timeout to fresh service discovery, before a new
bootstrap or bind. That attempt remains a recorded failure; the subsequent diagnosis and corrected
bounded acceptance are below. No fixture process remained after the run. Logs are
`/tmp/commandly-companion-native-harness/native-wrong-app.log`,
`/tmp/commandly-companion-native-harness/native-other-session.log`, and
`/tmp/commandly-companion-native-harness-exit-diagnostics/native-correct.log`.

This is not evidence for replacement under the production SMAppService Mach name, a different
signing team/effective user, malicious endpoint forwarding, native replay/stall stages, or any
cross-application action. The actual companion remains disabled and unregistered after its separate
successful enable/check/disconnect/reconnect/disable acceptance.

### Signed bundled-service restart acceptance — September 17, 2026

The archived launchd evidence in
`/tmp/commandly-companion-native-harness-exit-diagnostics/bounded-restart-launchd.json` identifies the
earlier failure: after the generated helper exited, launchd deferred respawn for 10 seconds. The
client's five-second control-offer timeout ended the run before that deferred launch. The installed
macOS 27 SDK's `usr/share/man/man5/launchd.plist.5`, lines 409–414, documents this default throttle.

The reviewed correction is confined to harness control discovery. After authenticated helper self-exit
and an explicit old-transport terminal check, one initial `.offer` on a fresh correct-helper control
client has a typed 15-second deadline. Other commands, helper identities, audit-session exceptions, and
existing connections cannot use that mode. Ordinary control requests and all production bootstrap,
bind, offer-expiry, and metadata deadlines remain five seconds. The 80-second client watchdog remains
unchanged. No retry, synchronization sleep, authentication change, or timeout-as-success was added.

Root reviewed and signed the new outer fixture app with the existing development identity; both
embedded signed peers remained byte-identical. The native run passed all its reviewed cases, including
actual helper process exit, terminal failure of the old bound transport with exactly one bootstrap,
and explicit discovery of a distinguishable fresh process. A new endpoint completed the authenticated
bootstrap/bind/metadata flow, and the old transport stayed terminal afterward. The result log ends with
`HARNESS PASS helper-exit-old-transport-terminal-explicit-fresh-connect` and
`HARNESS PASS reviewed-cases-only`:
`/tmp/commandly-companion-native-harness-respawn/native-correct.log`.
Root's post-run check found no remaining CompanionHarness process. No service was registered or privacy
grant requested. The isolated preparation suite passed 53 tests in 10 suites with strict Swift 6 and
warnings as errors; its receipt is `/tmp/commandly-companion-native-harness-respawn/test.log`.

This proves the signed bundled fixture's explicit fresh-endpoint flow after real process exit. It
does not prove crash/replacement or restart of a registered SMAppService job under the production Mach
name. Wrong-team/different-EUID peers, malicious endpoint forwarding, native replay/stall stages, and
cross-application capabilities remain separate gates. The typed bootstrap-endpoint initializer remains
an off-tree acceptance injection point, not a published production API; production still bootstraps
through its fixed Mach name.
