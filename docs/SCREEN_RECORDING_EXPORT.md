# Recording export

The September 14, 2026 generated-recorder UI acceptance reached playback, but Save failed after the
person chose an exact MP4 destination in NSSavePanel. The original exporter opened the destination's
parent and created an arbitrary sibling temporary file. The selected-file grant does not itself
authorize those unrelated names. The error kept the reviewed video available, but prevented the requested save. The replacement
exporter uses the OS-supported safe-save flow, without asking for broader directory access.

`NativeScreenRecordingExporter` receives only the store-owned source, its reviewed file identity,
and the exact selected URL. Its injected `ScreenRecordingExportFileAccess` owns the replacement-
directory lookup, synchronous coordinated write, native publication, and cleanup. The production
adapter requests `FileManager.url(for: .itemReplacementDirectory, in: .userDomainMask,
appropriateFor: destination, create: true)`. Apple documents that the selected destination determines
the volume, avoiding a cross-volume replacement. The replacement directory is set to 0700 and the
exclusive temporary video to 0600. All copying runs on the store actor using a 1 MiB buffer, bounded
by the reviewed byte count and a 512 MiB maximum; EINTR retries do not skip cancellation checks.

Native `NSFileCoordinator` manages publication with `.forReplacing`, whether the selected destination
exists or not. The accessor is synchronous and all file access finishes before it returns. The
implementation uses its supplied URL and refuses an unexpected redirect. An unchanged existing
regular file uses `FileManager.replaceItemAt` with `.usingNewMetadataOnly` to preserve the new 0600
permissions. A missing destination uses same-volume `FileManager.moveItem`, which refuses a new
collision. No delete-then-copy fallback or arbitrary sibling file is used.

The store now pins device, inode, size, modification time, and change time when finalization succeeds.
It rechecks those values after asynchronous playback validation. Export rejects even same-size
source replacement, symlinks, changed destination/staging identity, and post-copy cancellation.
The old source is never removed during export. Safe-save errors retain the original review for
retry. Cleanup failure is surfaced instead of swallowed; if cleanup fails after publication, the
completed destination can exist despite an error. A crash or failed cleanup can retain bytes in the
OS replacement directory. No timed deletion is claimed. OS/file-provider safe-save guarantees do
not imply universal protection from arbitrary unrelated filesystem failures.

## Verification

The isolated Swift 6 harness passed 11 test functions in two suites (18 parameterized cases) using
actual native new-file and existing-file publication, including generated data spanning multiple
buffers. Tests also cover source/destination symlinks, same-size reviewed-source replacement,
source/destination/staging changes while coordination is waiting, a new collision, injected native
coordination/publication errors, cancellation before copying and before publication, a coordination
redirect, cleanup failure, 0600 permissions, unchanged originals, and removed temporary directories.
The existing `ScreenRecordingStoreTests` are included. Log:
`/tmp/commandly-recording-export-slice/isolated-tests.log`.

These tests run on generated files outside the app sandbox. They do not establish NSSavePanel grant
behavior in the signed app. Combined `make verify` passed in
`/tmp/commandly-video-verify-tranche12-final.log`. On September 14, the signed sandboxed app's actual
Save dialog successfully created `/tmp/commandly-recording-ui-20260914.mp4`, then replaced that same
generated file after the native replacement review. The resulting 11,388-byte MP4 has 0600 permissions.
The generated video also played in the direct native AVPlayerView review. Real picker/capture/audio
acceptance remains separate. No real screen content, network, user video, clipboard,
permission prompt, or AVPlayerView code is used or modified by the exporter tests.

## Primary references

- [NSSavePanel](https://developer.apple.com/documentation/appkit/nssavepanel): the selected file is
  added to the app's sandbox for saving; this is not a grant for arbitrary sibling names.
- [FileManager replacement](https://developer.apple.com/documentation/foundation/filemanager/replaceitemat(_:withitemat:backupitemname:options:)):
  documents safe replacement, same-volume requirements, and the recommended replacement directory.
- [Replacement directory lookup](https://developer.apple.com/documentation/foundation/filemanager/url(for:in:appropriatefor:create:)):
  destination volume selection and cleanup expectations; also verified in the installed macOS 27
  SDK `Foundation.framework/Headers/NSFileManager.h`, lines 192–211 and 744–773.
- [Coordinated writes](https://developer.apple.com/documentation/foundation/nsfilecoordinator/coordinate(writingitemat:options:error:byaccessor:))
  and [forReplacing](https://developer.apple.com/documentation/foundation/nsfilecoordinator/writingoptions/forreplacing):
  synchronous accessor lifetime, provided URL, and replacement coordination for both creation and replacement.
