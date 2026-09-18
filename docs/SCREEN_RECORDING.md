# Screen Recording

Screen Recording (`screen.recording`) records native video of one explicitly selected window or
display. Its tools are Record a Window (`screen.recording.window`), Record a Display
(`screen.recording.display`), and Stop Screen Recording (`screen.recording.stop`). Opening the
application/tool creates or focuses one independent recorder window; it never begins capture.
The person reviews settings, activates **Choose & Record**, and selects content in the macOS picker.

## Behavior and keyboard

- Audio defaults to off. Optional system audio explicitly excludes Commandly audio. The microphone
  is always disabled, has no toggle, and is never requested. The frozen audio setting remains
  visible while recording, even if a caller changes the next recording's options.
- Choose MP4/MOV, H.264/HEVC, maximum 1080p/720p, and pointer inclusion before recording. Video uses
  SDR at 30 fps, even dimensions, no upscaling, and fits inside the selected resolution while
  preserving aspect ratio. Unsupported native format combinations return a recoverable error.
- The separate movable window stays visible above other windows and survives launcher dismissal.
  Window capture selects only another app's window. Display capture includes everything visible
  on that display, including the controls; the explanation states this before selection.
- Return activates Start, Stop & Review, or Save Video according to state. Native controls support
  Tab/Shift-Tab and named pickers. Command-S opens Save for a reviewed video. Escape and Command-W
  request safe close; a native picker/sheet retains its own keyboard routing.
- Stop remains pending until both `SCStream.stopCapture`/native stream termination and
  `SCRecordingOutput` finalization confirm shutdown. Review never relies only on clicking Stop.
  A failed native stop separately requests removal of the recording output to limit further disk
  writes, while keeping the stream worker and window alive. Retry Stop or the macOS sharing indicator
  can finish it; the UI never falsely claims that capture ended and cannot delete its active file.
- Closing during capture requests Stop and then offers Save Video, Discard, or Keep Open. Cancelling
  Save retains review. Successful Save retains review until discard/close, and a later close cleans
  the temporary copy without asking to save it again. Export failure retains the reviewed video.
- Quit uses the coordinator's completion handshake. Stop recording first, then present save/discard
  if needed; a cancelled quit retains review and never silently restarts capture. Reopening the
  recorder cancels only the pending termination decision. An explicit discard already underway
  continues cleaning its private output.
- The hosting view observes the runtime's shared `AuxiliaryWindowAppearance` and applies
  `commandlyContentSize`. Text-size updates preserve the model and player state and do not focus or
  reorder the window. Larger text expands the minimum layout; no repeated decorative motion runs.
  Native `AVPlayerView` starts paused and plays only through the person's playback action.

## Native ownership and cancellation

`NativeScreenRecordingCaptureService` owns the shared system picker on MainActor for the entire
operation. It checks `isAvailable`/`isActive`, snapshots and restores configuration, limits selection
to one window or display, disallows selection replacement, and removes its observer on terminal
completion. This also prevents the Screenshot application's window/display picker from competing
with an active recording. Region screenshots use their own separate consent boundary.

The exact consent-bearing `SCContentFilter` is retained; it is never reconstructed from display IDs
or window lists. A native `SCStream` receives `SCRecordingOutput` before `startCapture`, so this is
continuous encoded video, not repeated screenshots or a Finder handoff. The implementation neither
enumerates arbitrary screen content nor requests broad capture permission during initialization.

The native worker confines filter/stream/output references to one `OSAllocatedUnfairLock` ownership
region. The Objective-C picker protocol cannot express a Swift `sending` callback parameter; the
initial native-filter retention is the one documented `withLockUnchecked` entry. The chosen filter
is never mutated or returned, replacement is disabled, and all later operations use Sendable lock
closures. Delegate callbacks enqueue only `ObjectIdentifier`, progress, and typed-error values, so
synchronous callbacks cannot reacquire a held lock. No native capture object enters MainActor UI
state, and no new `@unchecked Sendable` conformance is introduced. A serial worker queue performs
configuration/lifecycle calls; encoding belongs to ScreenCaptureKit.

`ScreenRecordingLifecycle` requires start and output-start signals before publishing Recording,
and requires both shutdown and output-finalization before publishing a terminal event. Cancelled
operations cannot publish review. The MainActor model blocks a replacement session until cancelled
prepare/begin/finalize work settles, native cancellation completes, and the exact owned file is
removed. Stream termination triggers native cancellation as a second safety boundary. No arbitrary
sleep, global monitor, recurring window, or automatic capture is used.

## Bounds and output privacy

The defaults stop at 600 seconds or a reported 384 MiB, checked every 500 ms, while reserving
768 MiB of available storage before capture. ScreenCaptureKit has no hard output-write cap:
encoder buffering and finalization may exceed the early threshold. A finalized file must be a
non-symlink regular video, playable via AVFoundation, nonempty, and at most 512 MiB before review.
Oversized/unplayable/failed output is discarded. Disk availability can change during capture; native
errors are handled and no finite preflight can guarantee other processes will not exhaust storage.

`NativeScreenRecordingStore` is an actor. It creates a 0700 private UUID directory under the user's
system temporary directory and uses a 0600 lifetime `.owner` lock. Native output stays behind that
private directory and is set to 0600 after finalization. Only tracked UUID destinations can be
finalized, exported, or discarded. Discard unlinks the specific file without following a symlink.

A separate maintenance lock serializes cleanup and creation. On explicit next preparation only,
unlocked UUID directories with the ownership marker are removed; symlinks, arbitrary siblings,
and another process's locked directory are preserved. Normal discard/close removes video bytes.
The empty leased directory persists until a later preparation/process cleanup; a crash/force quit
can retain video bytes until the next explicit recording start. This is not a timed deletion claim.

Save uses `NSSavePanel` and the exact destination's security scope. A selected-file grant does not
authorize arbitrary sibling temporary names. `NativeScreenRecordingExporter` therefore requests an
OS `itemReplacementDirectory` on the destination volume, streams the reviewed source into a 0600
file there with at most 1 MiB per buffer, and syncs it before publication. It coordinates the selected
URL with `NSFileCoordinator` using `.forReplacing`, then uses `FileManager.replaceItemAt` for an
existing regular destination or `moveItem` for a new destination. No directory permission is requested.

The source's regular-file identity, size, modification/change times, and inode are pinned at review
and checked through `O_NOFOLLOW` descriptors before and after copying and before publishing. A changed
source, destination, staged output, or redirected coordination URL fails. Existing symlinks are not
followed or replaced. Cancellation before publication preserves the previous destination; after
commit the completed output is not reported as undone. Replacement directory cleanup is attempted
on success, cancellation, and failure. Cleanup errors are propagated; a process crash or filesystem
failure may leave temporary bytes, and a cleanup error after publication can accompany a completed
export. The reviewed source remains available for retry. Explicit exports are never deleted by
Commandly. No whole-video `Data` is read on MainActor. Recording source titles, IDs, paths, pixels,
audio, error descriptions, or content are never logged or persisted in history. There is no clipboard,
AI, network, Photos, microphone, or third-party recorder integration. See
[Recording export](SCREEN_RECORDING_EXPORT.md) for the save boundary and acceptance evidence.

## Integration

Infrastructure owns `ScreenRecording.swift`. Native services, lifecycle gate/configuration, and
private storage belong to `Commandly/Services/ScreenRecording`. UI, model, window, and retained
coordinator belong to `Commandly/Scenes/ScreenRecording`. Application and live documentation
registrations are isolated under `Scenes/Launcher/Applications`.

Runtime constructs one `ScreenRecordingCoordinator(capture: NativeScreenRecordingCaptureService(),
storage: NativeScreenRecordingStore(), makeWindow: { ScreenRecordingWindowController(appearance:
auxiliaryWindowAppearance) })` and injects it into `ScreenRecordingApplication(presenter:)`.
Constructors do not touch the picker, filesystem, screen metadata, or permissions. The app delegate
must call `requestCloseForTermination(completion:)` first: this stops recording and obtains the
person’s Save/Discard decision while retaining the review/window. Then perform the existing
Floating Notes termination handshake. If either rejects quitting, call `cancelPendingTermination()`,
reply false, and retain the stopped review (an explicitly discarded video remains discarded). Only
after all documents approve, await `commitPreparedTermination()` to clean and close the recorder;
reply true only if it succeeds. A failed native Stop never approves phase one and there is no
force-quit API. Preparation is pinned to the exact model generation, artifact identity, and settings.
Changing or starting a session in the already-visible recorder invalidates the old approval, even
without another launcher invocation. Commit first cleans the approved session without closing the
window, then rechecks its cancellable intent and idle state on the same MainActor turn as closing.
Reopening controls during cleanup cancels that close and cannot discard a later session. Do not
resume capture or discard an unsaved video on an unrelated note update.

Tests instantiate fake capture/store/window ports and generated temporary bytes, never real screen
content, microphones, system permission prompts, global input monitors, or user files. Required app
suites are `ScreenRecordingModelTests`, `ScreenRecordingNativeTests`, and
`ScreenRecordingStoreTests`, and `ScreenRecordingDebugFixtureTests`, followed by `make verify`. An isolated Swift package mirrors the
source for full Swift 6 compilation and deterministic tests while the root app build is coordinated
separately. Compilation/tests do not establish native system-picker consent or physical capture
behavior; that requires intentional live acceptance after integration.

## Generated acceptance fixture

In DEBUG productivity fixtures, inject `ScreenRecordingDebugFixture.capture()` and pass
`sessionLabel: ScreenRecordingDebugFixture.label` to the coordinator. It never opens a picker or
captures screen/audio. Explicit Stop generates a one-second 640×360 H.264 movie from original
CoreGraphics shapes and a GENERATED RECORDING label. AVFoundation's async pixel-buffer receiver
provides backpressure; generation runs on its actor with cancellation between frames and no sleeps.
The actual private artifact store validates and exports this generated movie. Its test verifies
playback acceptance, dimensions, nonzero bytes, and zero audio tracks. The same runtime appearance
and window/model/navigation paths remain in use; the visible generated-demo label prevents
mistaking fixture video for physical capture.

## Primary API references

- [SCRecordingOutput](https://developer.apple.com/documentation/screencapturekit/screcordingoutput)
- [SCRecordingOutputConfiguration](https://developer.apple.com/documentation/screencapturekit/screcordingoutputconfiguration)
- [SCRecordingOutputDelegate](https://developer.apple.com/documentation/screencapturekit/screcordingoutputdelegate)
- [SCContentSharingPicker](https://developer.apple.com/documentation/screencapturekit/sccontentsharingpicker)
- [SCStreamConfiguration](https://developer.apple.com/documentation/screencapturekit/scstreamconfiguration)
- Installed macOS 27 SDK `SCRecordingOutput.h`, `SCContentSharingPicker.h`, `SCStream.h`, and `SCError.h`
  establish configuration availability and the recording/finalization callback contract.

- [AVAssetWriter pixel-buffer receiver](https://developer.apple.com/documentation/avfoundation/avassetwriter/inputpixelbufferreceiver(for:pixelbufferattributes:))

## Native acceptance finding

On September 14, 2026, the generated fixture reached Stop and then crashed when SwiftUI's
`VideoPlayer` instantiated its `_AVKit_SwiftUI` view. The crash report showed failed superclass
metadata lookup for `AVPlayerView`, and the debug binary linked the overlay without native AVKit.
The review now wraps `AVPlayerView` directly through `NSViewRepresentable`, which gives the linker
an explicit native class reference and owns pause/player cleanup. Automatic frame analysis and
the sharing-service button are disabled for this local review. Rebuild and native replay must pass
before that crash is considered fixed. This finding was outside the earlier generated-file/model tests.
