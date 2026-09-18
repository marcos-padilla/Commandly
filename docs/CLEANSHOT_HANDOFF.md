# CleanShot screenshot annotation

Screenshot review offers **Open in CleanShot X**. This optional integration requires an already
installed CleanShot X 3.8.1 or later. It sends exactly the reviewed PNG to CleanShot's local annotation
editor. Commandly does not install an app, switch the default URL handler, request another capture,
use the clipboard as a bridge, upload a file, call a cloud API, or read back edits. Copy and Save
remain available if the integration is unavailable.

## Documented boundary

[CleanShot's official URL scheme API](https://cleanshot.com/docs-api) documents
`cleanshot://open-annotate?filepath=<encoded local path>` for PNG/JPEG annotation, with a minimum
version of 3.8.1. The documentation contains no consumed-file acknowledgment or edit-result callback.
Commandly constructs only this command through URLComponents with one `filepath` query item.
Injected tests cover paths containing reserved characters, including strings resembling extra
commands or an upload parameter. No shell or process execution participates.

On the explicit action, LaunchServices resolves the documented scheme. An actor reads bounded
application metadata to check the exact bundle ID `pl.maketheweb.cleanshotx`, CleanShot's name,
declared scheme and supported version. Native Security APIs also require an Apple-anchored signature
from developer team `AFJU4P8ZV4`, with strict bundle and all-architecture verification. The
`kSecCSAllowNetworkAccess` flag is absent, so Commandly requests no certificate-trust network access. The exact
inspected application URL is pinned for `NSWorkspace.open(_:withApplicationAt:configuration:)`,
avoiding a second default-handler lookup after staging the private image. A
different, unsigned, modified, or outdated handler is rejected without creating a screenshot file or opening another app.
The receiving app may ask for its own API access consent; Commandly never grants it automatically.

Identity evidence was taken from the [official signed CleanShot X 4.8.10 release](https://updates.getcleanshot.com/v3/CleanShot-X-4.8.10.dmg)
on 2026-09-14. Its Info.plist identifies `pl.maketheweb.cleanshotx` and registers `cleanshot`; its verified
Developer ID signature identifies “Make The Web Oślizło & Magiera s.c.”, team `AFJU4P8ZV4`, with a
stapled notarization ticket. The disk image was inspected read-only and unmounted; the app was never
installed or launched. Only this evidenced identifier/team combination is accepted. A different
distribution with another identity requires separate authoritative verification before support is added.
SDK 27 `SecStaticCode.h` documents strict validation and the opt-in network flag. Static signature
validation is valid while the installed bundle is unchanged; Commandly pins the inspected app URL,
but cannot protect against concurrent replacement by another process with write access to that app.

An accepted native open means only that macOS accepted the request. The UI does not claim that
CleanShot finished loading or editing the image. Saving or copying the edited result happens in
CleanShot; Commandly does not replace its own reviewed image with an unverified result.

## Temporary-file privacy and lifetime

`CleanShotTemporaryStore` is an actor and performs all image inspection and filesystem work off the
main actor. It validates PNG type, one frame, and dimensions matching the bounded ScreenshotImage
artifact. It writes the original reviewed bytes, preserving their existing sRGB rendering and metadata
removal. The handoff creates a new UUID filename inside Commandly's temporary directory, with
directory permissions 0700 and file permissions 0600. Exclusive creation and no-follow flags reject
name collisions and symbolic-link substitution. The store accepts only its own regular, singly
linked UUID PNGs and never recursively deletes a user folder or follows a file link during cleanup.

At most three unexpired handoffs and 320 MiB total are retained; an individual screenshot remains
bounded to 160 MiB, 8,192 pixels per edge and 40 megapixels. Reaching capacity produces recoverable
guidance instead of deleting another image that CleanShot might still be loading.

Each file gets a ten-minute retirement deadline independent of the launcher view. An injected clock
backs this real lifecycle deadline; tests advance it without sleeping. Pre-dispatch cancellation and
native-open failure remove the staged file immediately. Once native dispatch has begun, cancellation
cannot retract the request, and the lease remains available until its deadline so CleanShot can finish
reading. No arbitrary delay is used to infer that loading is complete.

While Commandly is running and scheduled, expiry removes the file. A suspended process or sleeping
Mac performs cleanup when it can run again. After Commandly quits or crashes, expired owned files
are swept on the next explicit CleanShot handoff; no background daemon is installed and no absolute
wall-clock erasure guarantee is made. Cleanup failure is logged only as a fixed message, without
pixels, paths, URLs, app metadata, or source details, and retried on the next handoff. Removing a
temporary file does not revoke CleanShot's own imported copy/history or securely erase storage.
CleanShot owns subsequent annotation, history, save, clipboard, and cloud actions. Commandly only
requests local annotation.

## Ownership and verification

Infrastructure owns `ScreenshotAnnotation.swift`. `Services/Screenshot/CleanShot*` and
`WorkspaceCleanShotOpener` own URL construction, native app handoff, bounded temporary storage,
clock/lifecycle and dependency assembly. ScreenshotViewModel guards explicit review-only actions,
prevents duplicate work, ignores stale completions and retains the image on failure. ScreenshotView
keeps Copy and Save prominent alongside the optional annotation action. Its title is a VoiceOver
header, and the shared Actions menu also exposes Open in CleanShot X.

The live ScreenshotApplicationServices factory composes the integration. The default initializer
and in-memory fixture use an unavailable annotator, so tests/previews never unexpectedly open an
installed app. No registry or AppRuntime change is required.

Sixteen focused tests cover URL encoding, bounded generated app metadata, recipient version, pinned native dispatch,
unavailable/outdated handlers, no files before intent, exact PNG staging and permissions, count/byte
bounds, expiry, stale cleanup, malformed/mismatched images, symlink substitution, forged cleanup
leases, failed-open retry, cancellation before and after dispatch, and reviewed model actions.
All native app opening is injected. Generated temporary PNGs are the only file inputs. Existing
Screenshot capture, permission, geometry and renderer tests remain unchanged.

All production/UI and sixteen new tests compile with strict Swift 6/MainActor app flags. Thirteen
native URL/opener/storage tests pass in an isolated temporary SwiftPM harness using the same sources.
The three app model tests and coordinated `make verify` remain required after integration. No CleanShot app was found in the inspected standard application directories,
and no real CleanShot launch, API consent, imported-image rendering or edit flow was exercised.
