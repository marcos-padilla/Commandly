# Companion-owned Service Management setup

This corrects the first native registration failure while preserving the accepted optional-companion
architecture and the main app's sandbox. The signed development main app's direct `SMAppService`
registration returned status Not Found and registration error 1. The bounded system transaction
identified the unsupported sandboxed-owner/unsandboxed-job combination. No helper was registered or
launched by that attempt. The subsequent user-approved corrected native Enable → Check → Disable
flow passed; see the acceptance evidence below.

Apple DTS documents that macOS 14.2 and later block a sandboxed app from registering an unsandboxed
job; an unsandboxed app may register an unsandboxed job. The API resolves a LaunchAgent plist in the
**calling app's** `Contents/Library/LaunchAgents`, with `BundleProgram` relative to that app. The
companion is therefore now both the visible setup owner and the headless agent executable.
[Apple DTS: supported combinations](https://developer.apple.com/forums/thread/802443),
[Apple: agent plist ownership](https://developer.apple.com/documentation/servicemanagement/smappservice/agent%28plistname%3A%29).

## User flow and ownership

1. Commandly → Settings → System Integration offers **Companion Setup**. It validates the signed
   containing app/helper and opens the embedded companion as an independent application through
   `NSWorkspace`. Opening setup does not register, start a listener, or grant a privacy permission.
2. The companion shows its own registration status and an explicit **Enable Background Service**
   explanation. Confirming Enable validates its signature, non-root login session, signed containing
   app/build, sandbox separation, and narrow bundled LaunchAgent manifest, then calls `SMAppService`
   from that unsandboxed owner. Login Items approval remains controlled by macOS.
3. Return to Commandly and explicitly choose **Check Connection**. Only this action attempts the
   authenticated bound-endpoint metadata path. **Ready — Metadata Connection** describes this
   channel; no cross-app capability or TCC permission is implied.
4. **Disconnect** in Commandly closes only its channel. It does not stop the registered service or
   revoke permissions. Use **Disable Background Service** in Companion Setup to unregister the
   per-user job. Close keeps registration; disable before uninstalling or changing the embedded job.

The main app does not construct the registration adapter. Its `CompanionMainService` reports
**Managed in Companion Setup** when registration is unknown; it does not infer Disabled, Enabled,
or approval from a failed connection. Refresh reads cached/live channel state without starting an
IPC connection. Old main-app enable/disable method calls fail explicitly with `unsupportedOperation`.
The owner service still has a typed Enable/Disable API; the two meanings are not conflated.

No automatic helper installation, root daemon, shell, Process/NSTask launch, legacy plist copying,
new app-group data access, private API, broad Mach exception, or privacy prompt is introduced.
The helper's visible setup UI contains no user content and is not an IPC action surface.

## Launch and package layout

The main app still embeds the signed helper at
`Contents/Library/Helpers/CommandlySystemCompanion.app`. Move the existing LaunchAgent Copy Files
phase from the main target to that helper target. The resulting job plist is:

```
Commandly.app/Contents/Library/Helpers/CommandlySystemCompanion.app/
  Contents/Library/LaunchAgents/com.businessmate360.Commandly.SystemCompanion.plist
```

Its fixed values are `BundleProgram = Contents/MacOS/CommandlySystemCompanion` and
`ProgramArguments = [CommandlySystemCompanion, --service]`. The label, one app-group Mach service,
Aqua login-session restriction, and Interactive process type remain unchanged. No RunAtLoad,
KeepAlive, root UserName, or file-output keys are allowed by the manifest validator. The installed
`launchd.plist(5)` SDK manual documents BundleProgram as the executable and ProgramArguments as the
argument vector. [Apple package layout](https://developer.apple.com/documentation/servicemanagement/updating-helper-executables-from-earlier-versions-of-macos).

No arguments means visible setup. Only the signed LaunchAgent passes `--service` to choose the
headless listener, which performs its own signature/configuration checks. The helper's Info.plist
uses `LSUIElement` instead of `LSBackgroundOnly`; setup selects a regular application activation
policy and creates its one original native window. Service mode never creates NSApplication or UI.
There is no new target or package dependency.

The installed `NSWorkspace.h` explicitly says a sandboxed caller's OpenConfiguration arguments are
ignored, so the main app passes no arguments or workaround. It requests a new application instance
to avoid a running headless agent absorbing the UI launch, retains the returned setup-app handle
for subsequent activation, and prohibits substitution by another installed app copy. The helper
restores its own minimized window when activated. The normal application-launch API is distinct
from spawning a sandbox-inheriting child.
[Apple independent GUI launch guidance](https://developer.apple.com/forums/thread/735493),
[Apple sandbox inheritance](https://developer.apple.com/library/archive/documentation/Miscellaneous/Reference/EntitlementKeyReference/Chapters/EnablingAppSandbox.html).

Signed native acceptance on the installed macOS release verified this nested companion owning its
own job. Other supported releases still need their own acceptance; compilation alone is insufficient.

## Failure, lifecycle, and accessibility

The owner handles the state returned after a registration error. If macOS already created an Enabled
or Needs Approval registration, that state is retained instead of falsely reporting total failure or
re-registering. Failed unregistration does not report Disabled. Errors store only a fixed
`CompanionError` and an allowlisted NSError domain plus bounded numeric code; no localized error,
underlying userInfo, path, token, or log output is retained. Unknown domains become “Other macOS error.”

Setup commands serialize. Cancellation while signature validation is pending prevents later
registration. The setup window blocks close/quit while an authorized native setup operation is in
progress and explains why, so a completion/error remains visible. There is no invented timeout that
claims to cancel a registration already submitted to macOS. Unregister uses the native asynchronous
completion; the operating system controls termination of the actual job. Refresh remains available
after a failure, as does Login Items recovery.

The helper UI uses native semantic fonts, scrollable content, wrapping action groups, header traits,
explicit labels/identifiers, an accessible enable confirmation, keyboard navigation, Escape to close,
and Cmd-Q. It keeps its strong AppKit delegate/window/model for the event loop. No background service
is started by opening that UI. The main page retains shared Commandly text scaling and settings
layout. Its generated fixture simulates opening setup, checking metadata, and disconnecting in memory.

## Evidence and acceptance

The isolated Swift 6 build compiles the real package and helper executable with warnings as errors;
42 test functions across eight suites pass (ten new setup/main tests). Tests cover inert state,
explicit owner registration, pending approval, failed unregistration, diagnostic sanitization,
signature failure, cancellation/concurrent setup calls, narrow manifest/mode parsing, main no-register
semantics, and stale generation/channel snapshots. Receipt:
`/tmp/commandly-companion-setup-owner-slice/test-final.log`. The helper executable was built but never run.
The revised main services/settings/test sources separately pass strict UI typechecking against the
current app module and updated Infrastructure contracts. Full integrated verification and a clean
signed build subsequently passed in `/tmp/commandly-video-verify-tranche16-setup-owner.log` and
`/tmp/commandly-video-native-tranche16-setup-owner.log`. Exact main/helper signing requirements,
deep strict verification, effective entitlements, and helper-owned packaging were checked.

Native acceptance verified inert setup opening, explicit registration owned by the helper,
sandboxed main Ready/Metadata through the bound factory, Disconnect, explicit reconnect, and
actual unregistration/headless-process termination. Main Refresh cleared the former Ready state;
a subsequent Check failed cleanly with setup recovery. Setup Close terminated its UI process.
No privacy grant occurred. The helper was left disabled and unregistered. This proves the tested
registration/metadata/shutdown path, not wrong-signer, replacement, or future native capabilities.

For the already approved controlled acceptance:

1. Apply the reviewed new files, owned existing-file patch, root UI/factory patch, and copy-phase
   move. Build clean output, inspect both signatures and effective entitlements, and verify the job
   plist is inside the helper, not just the obsolete main-bundle location. Incremental artifacts may
   retain stale removed output; do not mistake an old plist for the new ownership structure.
2. Launch the signed main with the existing generated-productivity/live-companion acceptance mode.
   Open Companion Setup; confirm the separate visible window appears and no background job is
   registered just from opening it. Confirm no TCC prompt and no headless-mode UI.
3. Use the user's approved explicit Enable flow in that window. Record actual status and only
   sanitized diagnostic domain/code on failure. Handle macOS background-item approval through its UI.
4. Return to Commandly and explicitly Check Connection through the bound factory. Verify the
   endpoint metadata handshake, then exercise stale endpoint/crash/disable cases in the separate
   [bound-channel acceptance](SYSTEM_COMPANION_BOUND_CHANNEL.md). Mock peers are not native auth proof.
5. Finish the approved test with **Disable Background Service in Companion Setup**, verify actual
   unregistration and channel loss, then close setup. Commandly Disconnect alone is insufficient.

Do not grant Accessibility, Input Monitoring, or any other new privacy permission in this acceptance.
Do not introduce a registration bypass, remove the main sandbox, or claim cross-app actions from a
successful metadata handshake. Release signing/notarization and broader capability acceptance remain
separate work.
