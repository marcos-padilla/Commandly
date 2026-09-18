# Screenshot

Screenshot (`screen.capture`) is a one-shot, local launcher application. Region, Window, and Display
are independently searchable tools. Opening any entry shows the explanation and selection type;
only **Choose and Capture** starts a picker or permission request. The resulting PNG must be
reviewed before the person chooses Copy, Save, or the optional Open in CleanShot X handoff. No video/audio stream, recording, upload, or AI
request is created.

## Native selection and authorization

- Window and Display use `SCContentSharingPicker.shared` limited to a single window or display.
  The system picker supplies scoped consent for precisely the chosen content; these modes do not
  request a separate broad Screen Recording grant or enumerate other windows. The callback uses
  the returned `SCContentFilter` for `SCScreenshotManager.captureScreenshot(contentFilter:configuration:)`.
- Region uses the existing `PermissionKind.screenRecording` and injected permission service. The
  explanation appears before **Choose and Capture**, an undetermined permission is requested only
  from that action, and denial/restriction offers Settings recovery. The native adapter rechecks
  preflight before selection, after selection, and before returning the rendered image.
- The original AppKit region overlay draws only geometry, without taking a background screenshot.
  Drag in any direction, release to capture, or use arrow keys to create/move a rectangle, Shift and
  arrows to resize, Return to accept, and Escape to cancel. A display-layout change cancels selection.
  All panels close before `SCScreenshotManager.captureScreenshot(rect:configuration:)` runs.
- AppKit bottom-left coordinates become the ScreenCaptureKit top-left global coordinates using the
  primary display’s top edge. Negative origins and displays above/below the primary are preserved.
  The delivered mouse event determines selection coordinates; later pointer movement cannot change
  an already released selection. A geometry/scale/identity snapshot is revalidated before capture,
  after native delivery, and after rendering; display-change monitoring remains active throughout.
  A rectangle spanning displays uses the highest intersecting backing scale, then applies output
  bounds. Gaps between displays follow the system compositor’s screenshot output.
- The launcher becomes transparent and ignores mouse events only while selecting/capturing. Its
  live session is retained and restored for review. Closing/dismissing it cancels work and does not
  reopen a closed window.

Picker configuration is restored after the request. Only one callback is accepted; a Swift `Mutex`
protects the callback gate without `@unchecked Sendable`. Native `SCContentFilter` objects stay in
native callback scope. Only immutable `CGImage` and typed errors cross tasks. Picker cancellation,
permission removal, unavailable/protected content, native failure, and late completion all produce
recoverable results. Cancelled screenshots are discarded even if the native one-shot request cannot
be interrupted internally.

The implementation uses no shell screenshot command, Accessibility grant, Input Monitoring grant,
new entitlement, network request, or screenshot usage-string key. Screen Recording permission is
needed only for the custom region path, not for the user-selected system picker paths. It does not
enable the separately disabled Window Switcher prototype.

## Bounds, artifact, and privacy

`SCScreenshotConfiguration` requests SDR, pointer inclusion only when selected, no window shadows,
no child windows, and `fileURL = nil`. Requested output is limited to 8,192 pixels per edge and
40 megapixels while keeping proportions. Large captures are reduced before a CGImage is returned.
`ScreenshotImageRenderer` performs sRGB rasterization and fresh PNG encoding on a dedicated actor,
with a 160 MiB encoded-output cap and a preview at most 1,280 pixels on its longest edge/8 MiB.
No source metadata is copied. Preview construction in SwiftUI handles only this bounded in-memory
preview; no filesystem access or native capture happens in view rendering.

`Infrastructure/ScreenshotCapture.swift` defines the selection/request, capture/copy protocols,
typed errors, and immutable `ScreenshotImage`. The artifact retains PNG bytes, preview bytes,
dimensions, category, and an ephemeral UUID. It deliberately contains no window title, display ID,
source position, private URL, or permission/capture handle. It is not Codable and is not persisted
by the feature. This is the explicit image-data boundary reused by the separate [Visual AI](VISUAL_AI.md) consumer.
Screenshot itself does not attach or upload an image. Visual AI requires its own Capture, exact
provider-bound preview, destination disclosure, and explicit Send action.

Copy writes the ordinary system clipboard only after the reviewed-image action, including normal
Clipboard History behavior when enabled. Save writes only through the native PNG export panel with
a static safe filename. Errors retain the reviewed image for retry. Discard, New Screenshot, Back,
launcher dismissal, and view disappearance clear image bytes. No selection, image, permission
payload, device identity, or source content is logged or recorded in command history. A dispatched CleanShot handoff keeps its
private temporary copy on its own ten-minute deadline; see `CLEANSHOT_HANDOFF.md`.

## Ownership and integration

- Infrastructure owns `ScreenshotCapture.swift` contracts.
- `Services/Screenshot` owns native picker/capture, region selection, coordinate math, image
  rendering, dependency assembly, and explicit clipboard writes.
- `Scenes/Launcher/Commands/Screenshot` owns the MainActor model and SwiftUI review/export flow.
- `Scenes/Launcher/Applications/ScreenshotApplication.swift` owns application/tool registration
  declarations and `Documentation/ScreenshotDocumentation.swift` provides live help.
- Root assembly injects `ScreenshotApplicationServices.live(permissions:privacySettings:)`; previews
  and tests use `.inMemory`. No dependencies touch capture APIs or permissions at construction.
- `#if DEBUG` `ScreenshotDebugFixture.services` generates an 800×450 geometric screenshot labeled
  “GENERATED SCREENSHOT” only after Capture. It never selects/captures a real screen or reads/writes
  the system clipboard. Existing explicit productivity-fixture wiring may use it for UI acceptance.

## Verification

Tests use generated pixels and injected permission/capture/copy dependencies only. They do not
activate native selection UI, grant permission, access actual screen metadata/content, save files,
or touch the real clipboard. CleanShot tests create only generated PNGs in isolated temporary folders
and inject handler lookup, dispatch, and a manually advanced expiry clock. Coverage includes negative/stacked display origins, reverse drags,
mixed Retina scales, aspect/output bounds, sRGB PNG preview encoding, native configuration,
error mapping, all shared executor entry paths, no launch side effects, region-only permission,
denial/revocation, cancellation during permission checks, noncooperative stale capture, exact
explicit copy, save/copy recovery, dismissal cleanup, and the generated debug fixture.

Native adapters and the production UI draft compile with Swift 6 complete concurrency checking,
MainActor default isolation, and the app’s upcoming-feature flags. Coordinated targeted app tests
and `make verify` are required after integration. Actual native screen capture, system picker
behavior and consent dialogs require a separate intentional user-authorized acceptance test;
generated tests do not establish those physical/system behaviors.

## Primary API references

- [Apple: What’s new in ScreenCaptureKit, WWDC23](https://developer.apple.com/videos/play/wwdc2023/10136/)
  explicitly describes system-picker filters for one-shot screenshots.
- [Apple: What’s new in privacy, WWDC23](https://developer.apple.com/videos/play/wwdc2023/10053/)
  explains selected-content consent without separate broad screen permission.
- [SCContentSharingPicker](https://developer.apple.com/documentation/screencapturekit/sccontentsharingpicker)
- [SCScreenshotManager](https://developer.apple.com/documentation/screencapturekit/scscreenshotmanager)
- [SCScreenshotConfiguration.sourceRect](https://developer.apple.com/documentation/screencapturekit/scscreenshotconfiguration/sourcerect)
- Installed macOS 27 SDK headers `SCScreenshotManager.h`, `SCContentSharingPicker.h`, `SCStream.h`,
  and `SCError.h` provide the exact API availability, point/pixel units and native error definitions.
