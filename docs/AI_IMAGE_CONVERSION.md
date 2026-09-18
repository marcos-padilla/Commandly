# Finder AI image conversion

Finder AI can now propose and execute a real image conversion through `finder_convert_image`. The
model plans the task through a typed tool; the existing ImageIO/CoreGraphics converter performs the
pixel work locally only after exact local approval. A natural-language answer alone never performs
the conversion. This implements the video's Ask AI to Convert an Image example inside the existing
Finder AI application, rather than adding a separate AI provider or a simulated image editor.

## Workflow

Configure Finder AI and authorize specific folders through the existing Permissions flow. Submit a
request such as “Convert photo.png to JPEG in Output, with a 1,200 pixel longest edge.” The model
searches/lists first to obtain opaque source and destination handles. It may then propose one
conversion with a native format, exact new filename, optional aspect-preserving longest edge, and
clockwise rotation in zero through three quarter turns. There is no raw-path, URL, shell, overwrite,
or implicit output-location argument. Available native encoders are checked before a plan is shown.

The local approval card names the exact source and destination, output filename, format, size,
rotation, transparency treatment, metadata removal, and sRGB rendering. Approve Once issues the
existing non-Codable, expiring, single-use mutation authority. Deny or cancellation does not grant
that authority. The original image remains unchanged. An existing output name fails; the tool never
overwrites it or silently picks a different filename.

The result is reported only after native conversion and exclusive output publication complete. Its
bounded provider result contains operation status and filenames, not pixels, bookmarks, or absolute
paths. Finder AI can list the authorized destination to obtain a resulting handle and reveal it with
its existing reveal tool. Failure and cancellation retain the existing itemized mutation report
semantics. An image output already committed before cancellation is reported as completed; no
rollback is promised.

## Authority, byte boundary, and concurrency

The implementation follows accepted ADR-0006 and reuses Finder's existing mutation approval and
incomplete-approved-turn replay guard. No execute or approve tool is added to the model catalog.
`FinderAIImageConversionRequest` contains only opaque handles, one filename component, and typed
`ImageConversionOptions`. Its preview is local-only; source image data is not read to prepare it.

`ImageDataConverting` is a byte-only Infrastructure protocol. `NativeImageConversionService` now
conforms to it as well as `ImageConverting`; its original source-based entry delegates to the same
byte conversion implementation. Finder supplies no URL to the converter and gets no implicit
filesystem authority from it. There is no new ImageIO algorithm or alternate renderer to drift away
from Image Tools.

`FinderAIWorkspaceService` remains the actor that owns source authorization, handles, identity,
plans, and local writes. It holds the current security scope while working, validates a regular
image source and authorized directory, and rejects package/alias/symlink traversal in image directory
components. Source and destination root identities are pinned by device/inode. The source is opened
with `O_NOFOLLOW`, checked through `fstat` before and after a bounded read, and never reopened by the
converter. Directory components are walked using `openat` and `O_DIRECTORY | O_NOFOLLOW`.

After awaiting the codec, the workspace checks cancellation, session lifetime, plan expiry, current
folder authorization, source identity, destination identity, and collision again. The root refresh
also rereads the current session after its bookmark-store await so an ended conversation cannot be
restored from a stale snapshot. The existing approved-plan nonce is consumed before execution and
cannot be reused after any outcome.

`FinderAIImageFileIO` pins the opened directory descriptors and their physical `F_GETPATH` spellings.
This matters on macOS because Foundation can retain `/var` while the descriptor reports
`/private/var`; comparing those two spellings directly incorrectly rejects legitimate temporary
folders. Physical paths are used only for local identity/relocation checks and never logged.

Output is written in chunks of at most 1 MiB to an exclusive random `.commandly-image-UUID.tmp`
file with owner-only permissions, synced, revalidated, and published through
`renameatx_np(..., RENAME_EXCL)`. A competing output or symlink is never replaced. Cancellation and
failure attempt to unlink only the temporary inode that this operation created. If permissions or
filesystem failure prevent cleanup, a typed error states that an incomplete temporary file may
remain in the approved destination; the app does not claim cleanup succeeded. A crash or force quit
can also leave that temporary file. User-created completed output is never automatically deleted.

## Limits and fidelity

The shared native converter enforces 64 MiB compressed input, at most 40 million pixels, at most
16,384 pixels per side, and exactly one frame/page. Output allows an optional longest edge from 1 to
16,384 pixels, at most 40 million pixels, and at most 192 MiB encoded data. Native codecs are
synchronous within their actor; cancellation is checked between calls and before publication.
Internal encoder and full-raster working memory may exceed compressed-byte limits. Conversion is
not performed on the main actor or on the launch/search path.

PNG, JPEG, HEIC, and TIFF are offered through the reviewed native formats; unsupported encoders fail
clearly. PNG/TIFF preserve alpha. JPEG/HEIC composite transparency on white at 0.9 quality. EXIF
orientation is respected; rotation happens in clockwise quarter turns. Output is newly rendered
8-bit sRGB, so HDR/wide-gamut precision is not preserved and enlargement cannot create new detail.
Source GPS, EXIF comments, PNG descriptions, and embedded source metadata are not copied. ImageIO
may add fresh technical dimension/color metadata.

## Privacy and accessibility

The provider receives the user's submitted prompt and ordinary bounded Finder tool metadata under
its existing connection disclosure. Neither source nor output image pixels are sent to the provider;
this feature does not add image upload, OCR, visual interpretation, arbitrary edits, AI background
removal, or a network client. No clipboard, Keychain, automatic permission request, source mutation,
process launch, shell, or third-party dependency is added. The normal separate text-content share
approval remains unchanged.

The existing approval card has verbatim local source/destination rows, explicit conversion details,
Approve Once and Deny buttons, and the existing confirmation and cancellation keyboard flow. New
conversion details are grouped for accessibility and explain lossy/metadata behavior before writing.
Native UI acceptance passed with the clearly labeled generated provider and real local converter.
A real-provider end-to-end turn remains separate; the fixture does not establish provider behavior.

## Verification

The isolated test harness compiles actual staged sources under Swift 6 strict concurrency and runs
existing Finder workspace and tool regressions alongside generated image tests. The final isolated
run passed all 40 tests in six suites (`/tmp/commandly-ai-image-conversion-slice/isolated-tests-final.log`).
Production and test sources also strict-compile against the app modules. Combined `make verify`
passed in `/tmp/commandly-video-verify-tranche12-final.log` and again with the conversation fixture
in `/tmp/commandly-video-verify-tranche13-companion.log`. The signed sandboxed native app showed
the exact approval card, accepted Approve Once, and reported one completed conversion. The generated
output exists with 0600 permissions. macOS denied external command-line content inspection of the
app container; output dimensions and unchanged source bytes are established by the generated native
codec tests, rather than claimed as a separate external inspection. See
[FINDER_AI_IMAGE_DEBUG_FIXTURE.md](FINDER_AI_IMAGE_DEBUG_FIXTURE.md).

New suites: `FinderAIImageConversionTests`, `FinderAIImageFileIOTests`, `FinderAIImageToolTests`, and
`NativeImageDataConversionTests`. Tests cover every encoder available on this Mac, actual rotation
and resize, unchanged source bytes, source metadata demonstrably present before conversion and
absent afterward, 0600 output, native malformed/oversized/multi-page rejection, exact settings and
filename validation, approval/replay, sanitized result disclosure, cancellation/expiry/session/root
changes while a noncooperative converter is pending, source/destination symlink replacement,
post-approval collisions, descriptor-walk rejection, directory relocation before commit, and cleanup.
Existing Finder mutation, scoped handle, content-share, protected-root, and provider-tool schema
regressions are rerun. Tests use only generated temporary files, injected services, and local native
codecs; they do not use real providers, credentials, user files, clipboard, or permission prompts.

The byte-only ImageIO APIs are the same APIs reviewed in [Image Tools](IMAGE_TOOLS.md). Descriptor
flags and `renameatx_np`/`RENAME_EXCL` were verified against the installed macOS 27 SDK's Darwin
headers (`sys/fcntl.h`, `sys/stdio.h`); the exclusive publication and no-follow behavior are also
exercised using generated local files.
