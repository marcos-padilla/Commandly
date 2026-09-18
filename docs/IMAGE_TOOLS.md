# Image Tools

Finder AI can also propose these native conversions through an exact, single-use local approval.
See [Finder AI image conversion](AI_IMAGE_CONVERSION.md); the original image is retained and pixels
stay on the Mac.

Image Tools converts an explicitly chosen or dropped still image using Apple's ImageIO and
CoreGraphics frameworks. PNG, JPEG, HEIC, and TIFF are offered only when ImageIO reports an
available encoder. Conversion, aspect-preserving longest-edge resizing (including enlargement),
clockwise quarter-turn rotation, bounded original/output previews, and explicit native export
form the complete workflow. Changing a setting invalidates an earlier output. Export errors retain
the output for another attempt.

The Extract Text and Decode QR modes use local Vision recognition on the same explicitly selected
source. Dedicated launcher tools open these modes and present the picker directly. Text results are
editable before Copy Text; QR payloads remain exact plain text until an explicit copy or reviewed
web-link action. Switching modes keeps the source and conversion settings but clears the prior
conversion/recognition result. Read Again retries recognition; replacing or clearing the source
invalidates outstanding work.

## Ownership and lifecycle

- `Infrastructure/ImageConversion.swift` owns the Sendable contract and typed values/errors.
- `Infrastructure/ImageRecognition.swift` owns the separate text/QR recognition contract and output.
- `Services/ImageTools/NativeImageConversionService.swift` is an actor; synchronous reads, decoding,
  rendering, and encoding occur outside the main actor.
- `ImageToolsImageDecoder` centralizes bounded header validation and orientation-corrected thumbnails
  for both native actors. `NativeImageRecognitionService` uses asynchronous Vision requests.
- `Scenes/Launcher/Commands/ImageTools` owns the MainActor model and SwiftUI view.
- `ImageInspectionViewModel` owns recognition, editable output, QR selection, and link review state.
- `Scenes/Launcher/Applications/ImageToolsApplication.swift` declares Open Image Tools, Choose Image
  to Convert, Extract Text from Image, and Decode QR from Image. The registry injects the converter,
  recognizer, existing pasteboard adapter, and existing URL opener.

The loader balances the selected file's security scope and retains bounded compressed bytes in
memory; the original URL is not persisted. Generation checks reject late results after replacement,
cancellation, settings changes, or session teardown. Cancellation is checked between synchronous
native codec calls, which cannot themselves be interrupted. Session teardown releases source/output
bytes and closes transient controls. Loading and codecs never execute on the launcher search path.

## Bounds and fidelity

Source reads are capped at 64 MiB with a capped FileHandle read as well as a preflight size check.
Headers are checked before decoding: at most 40 million pixels and 16,384 pixels per side. Multi-frame
and multi-page inputs are rejected explicitly. Output permits 1–16,384 pixels on the longest edge,
at most 40 million pixels, and at most 192 MiB of encoded data. Preview images are at most 960 pixels
on the longest edge. Full output rendering can allocate approximately 160 MB at the pixel limit;
temporary native codec buffers are additionally required. The actor serializes these operations.

EXIF orientation is applied before dimensions are presented and transforms are calculated. PNG and
TIFF retain alpha; JPEG and HEIC flatten onto white and use 0.9 quality. Output is newly rendered
8-bit sRGB, so wide gamut/HDR precision is not preserved. Resizing preserves aspect ratio with
integer-pixel rounding; enlarging cannot add image detail.

Vision receives an orientation-corrected raster at most 4,096 pixels on its longest edge. Text
recognition uses the accurate request with automatic language detection and no language correction;
users can edit the output to correct transcription and reading-order mistakes. OCR output and
edits are capped at 64,000 characters without splitting grapheme clusters. QR detection is restricted
to standard `.qr`, with at most 32 distinct payloads, 4,096 characters per payload, and 64,000 total
characters. Oversized/excess payloads are omitted with a visible notice, never truncated into an
apparently valid link. Binary-only payloads are counted and reported. No-match results are distinct
from processing failure. QR generation, camera scanning, screen capture, and other barcode formats
are outside these tools.

`RecognizeTextRequest`, `DetectBarcodesRequest`, `BarcodeObservation.payloadString`, `.qr`, and async
`perform(on: CGImage)` were verified in the installed macOS 27 Vision Swift interface. These APIs
are available from macOS 15, below Commandly's macOS 27 deployment target.

## Privacy and accessibility review

Image loading, conversion, and recognition use no network, clipboard read, Keychain, broad folder
scan, extra entitlement, automatic permission prompt, or source write. Export is an explicit `fileExporter` operation with a sanitized
`-converted` filename. No input paths, pixels, or errors containing private details are logged.
Source GPS/EXIF/comments/embedded thumbnails are not copied; ImageIO may add a fresh color profile.

Copy Text and Copy QR Content explicitly write the selected reviewed value to the system clipboard;
ordinary Clipboard History behavior may subsequently capture that user-requested copy. Recognition
does not itself persist the source, OCR text, or QR payload. All are removed from model state on
session teardown. Native work already in flight may finish internally, but cancelled/stale output
is discarded.

QR values render as verbatim text, without automatic links or payload interpretation. The web-link
review validator admits only HTTP/HTTPS URLs with a nonempty host, valid optional port, no embedded
credentials, no backslashes, and no literal whitespace/control or percent-encoded control characters.
Other payloads remain copy-only. Review displays the full URL and hostname without fetching either;
only the separate Open Link action calls the existing native URL opener. Selection changes, image
replacement, cancellation, and teardown discard pending review. Dispatch consumes and revalidates
the review, preventing accidental duplicate opening or reuse for a different selected payload.

Controls have visible labels and standard keyboard focus. Shared launcher actions support Return,
Command-K, and Escape. The rotation button announces current degrees, dimension input names its
valid range, previews have labels, and checkerboard decoration is hidden from VoiceOver. Invalid
input, encoding failure, save failure, and cancellation retain a recoverable workflow.

Image modes have a labeled segmented picker. OCR uses a standard, labeled TextEditor; QR selection
supports the shared arrow-key navigation and explicit Copy as its Return action. Link review uses
verbatim, selectable destination text and a separate Open Link button. Empty results, output limits,
binary QR codes, and actionable recognition/browser errors are visible without relying on color.

## Verification

`CommandlyTests/ImageToolsApplicationTests.swift` covers injected model behavior, tools, export
recovery, setting invalidation, malformed dimensions, and stale completion cancellation.
`CommandlyTests/NativeImageConversionServiceTests.swift` generates temporary image fixtures for
native codecs, orientation, alpha/white flattening, resize/rotation, source immutability, metadata
removal, and invalid/oversized/multi-frame inputs. Tests do not touch user files or permissions.

`NativeImageRecognitionServiceTests` generates CoreText images and CoreImage QR codes in memory;
tests cover text and exact QR decoding, orientation, blank results, input revalidation, cancellation,
and output bounds. `ImageInspectionViewModelTests` uses injected fakes for editing/copy, no automatic
actions, URL validation/review/dispatch, recoverable errors, mode/source preservation, and stale
completion. `ImageInspectionApplicationTests` executes both tools through the shared search,
application-hotkey, and Command Wheel executor paths and verifies they request explicit input.
