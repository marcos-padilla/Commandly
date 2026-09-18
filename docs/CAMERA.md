# Camera

Camera is a registered launcher application (`camera.preview`) with Open Camera Preview
(`camera.preview.open`) and Take a Selfie (`camera.preview.selfie`) tools. Search, application/tool
shortcuts, and Command Wheel use the same registered application executor. Both tools open the
screen with the camera off; neither triggers a permission prompt or capture.

## User behavior

1. Choose **Start Camera** after reading the contextual explanation. Commandly checks Camera access
   and requests it only when undetermined. Denied or restricted access never constructs a camera
   input; the screen provides Camera Settings recovery and an explicit retry.
2. Preview the selected camera. When multiple cameras are connected, the picker starts a fresh
   session for the selected device after the previous camera has fully stopped. A cancelled restart
   does not open a replacement camera. **Mirror preview and photo** applies the same horizontal
   reflection to the live preview and the final photo pixels.
3. Choose **Take Photo**. A native still capture runs and the camera session stops before the photo
   enters review. No photo is saved or copied automatically.
4. Review, **Save Photo** through the native PNG export panel, **Copy Photo**, **Retake**, or
   **Discard**. Copy/export errors retain the reviewed photo for retry. Cancelling a save panel
   retains the photo without treating cancellation as failure.
5. **Stop Camera**, Escape during preview/capture, Back, launcher session stop, or disappearance
   cancels pending work, clears frames/photos, and schedules native camera shutdown. A native
   operation already running may finish internally; generation checks prevent its late result from
   restoring cleared content. A system interruption or disconnect stops the stream and offers retry.

Return follows the current primary action: Start Camera, Take Photo when a frame is available, then
Save Photo. Command-K opens the shared actions menu. Buttons, device selection, mirror state, live
camera status, error text, and the reviewed photo have accessible labels. Containers preserve their
children as separate accessibility elements. The screen contains no automatic start or focus task.

## Ownership and concurrency

- `Infrastructure/CameraCapture.swift`: Sendable camera identity, bounded immutable BGRA frames,
  PNG photo values, stream events, typed errors, capture and explicit-copy contracts.
- `Services/Camera/NativeCameraCaptureService.swift`: native AVFoundation actor. A dedicated
  `DispatchSerialQueue` is its custom executor and the video delegate callback queue. Configuration,
  blocking `startRunning`/`stopRunning`, pixel conversion, and capture state stay off MainActor.
  The non-Sendable video delegate processes each native sample synchronously on that queue and
  yields only immutable bounded frame bytes into its Sendable stream. Native sample/pixel buffers
  and AVCaptureSession never cross into an actor closure or UI state. No `@unchecked Sendable`,
  unsafe isolation escape, or `assumeIsolated` is needed.
- `Services/Camera/CameraFrameRenderer.swift`: bounded pixels across the capture/UI boundary.
- `Services/Camera/NativeCameraPhotoProcessor.swift`: a byte-only processing contract and independent
  actor for still-photo encoding. The capture actor tracks the processing task and cancels it on
  Stop or request cancellation, allowing native camera shutdown without waiting for encoding. Only
  immutable image bytes enter the worker; native image objects remain local to its renderer.
  Request identities reject late completion, including a cancelled worker that returns after a retry.
- `Services/Camera/CameraPhotoRenderer.swift`: orientation normalization, optional reflection,
  sRGB rendering and fresh metadata-free PNG encoding on the independent photo worker.
- `Services/Camera/CameraApplicationServices.swift`: initializer-based dependency bundle and
  `.live(permissions:privacySettingsOpener:)` factory; `.inMemory` never accesses hardware.
- `Scenes/Launcher/Commands/Camera`: MainActor session model, native SwiftUI preview/review and
  FileDocument export. Each explicit start owns a fresh capture actor. Stream and photo request
  identities reject stale callbacks; session termination closes its own native session only.
  A restart or device change awaits previous native cleanup before constructing a replacement
  capture actor, with cancellation and generation checks after that wait.
- `Services/SystemPermissionService.swift`, configuration, and `docs/PERMISSIONS.md`: contextual
  Camera permission. Injected preflight/request closures make permission tests independent of TCC.
- `Composition/LauncherApplicationRegistry.swift` and `Application/AppRuntime.swift`: registration
  and shared live permission injection.

## Privacy and bounds

AVCaptureDeviceInput construction can itself prompt for access, so native input creation is guarded
by previously authorized `.video` access after the model's explicit Start flow. Construction of the
application, services, session model, or view performs no device discovery, input creation, or
permission query. Camera uses `com.apple.security.device.camera` and a contextual
`NSCameraUsageDescription`; it adds no microphone entitlement or audio input.

The adapter prefers 1280×720 capture, falls back to the supported medium session preset, and
supports built-in and external video cameras discovered through public AVFoundation APIs. Preview
processing emits at most 12 updates per second and buffers only the newest frame. Each immutable
preview is at most 960 pixels per edge with exactly four bytes per pixel. CI processing uses
explicit bounded integer destination dimensions to avoid floating-point rounding adding a pixel.

Photo processing rejects encoded input above 64 MiB, multiframe input, dimensions above 16,384 per
edge, or more than 40 megapixels. It normalizes orientation and downsamples to at most 4,096 pixels
on the longest edge, creates a preview at most 960 pixels on the longest edge, and freshly encodes
sRGB PNG data capped at 80 MiB per output. Source EXIF/GPS, comments, orientation, and embedded
thumbnails are not propagated. A color profile can be included for accurate display.

Frames, device identifiers/names, and reviewed photo bytes stay in memory for the camera session.
They are not logged, persisted, uploaded, or put into command history. Explicit Copy Photo writes
only PNG bytes to the ordinary system clipboard, including normal Clipboard History behavior when
enabled. The app never reads the clipboard for this feature. The save panel is the sole file-write
boundary; there are no temporary photo files or automatic exports. See
[Permissions](PERMISSIONS.md) for denial, restriction, and Settings recovery.

## Verification

Automated tests use only generated image bytes and injected dependencies. They never grant real
Camera access, discover or open a real camera, record audio, read/write the real clipboard, or save
real user files.

- `CameraPermissionTests`: seven mocked permission-state, explicit-request, cancellation and
  authorization-mapping cases.
- `CameraPhotoRendererTests`: eight generated-image tests for orientation, exact mirroring,
  metadata removal, preview/output bounds, malformed input and cancellation.
- `CameraFrameRendererTests`: three generated-pixel/bounds tests across the immutable preview
  boundary.
- `CameraViewModelTests`: deterministic permission/capture/stream/export/copy tests, including
  noncooperative late operations, camera shutdown before photo review, waiting for shutdown on
  restart and device changes, and Escape while a replacement waits for cleanup.
- `NativeCameraPhotoProcessingTests`: generated-byte tests on the actual callback/worker/stop path
  through a DEBUG-only entry point that never discovers or opens camera hardware. Suspended fake
  rendering proves Stop and caller cancellation complete without waiting for encoding; cancelled
  late output cannot finish a newer request, and encoding errors permit retry.
- `CameraApplicationTests`: shared search/shortcut/Command Wheel execution of both tools and the
  application without implicit permission, camera, or clipboard access.

The native capture actor and pixel renderers were separately compiled to an object with Swift 6
complete concurrency checking, MainActor default isolation, and the app’s upcoming-feature flags
against the installed macOS 27 SDK. Coordinated app tests and `make verify` are required for final
integration acceptance. Physical device behavior and the macOS consent dialog require a separate
manual test with an intentional user-approved camera start; automated coverage does not establish
that a physical camera or permission grant works.

`#if DEBUG` `CameraDebugFixture.services` supports native UI acceptance without hardware or TCC.
Its explicit Start creates a 640×360 geometric frame containing “GENERATED CAMERA FIXTURE,” a coral
square on the left and a cyan circle on the right. It keeps the frame stream open until Stop and
uses the same native photo renderer for mirrored/unmirrored capture. Its copier is a safe no-op;
its permission/settings dependencies are in-memory. It is selected only by the existing explicit
productivity debug-fixture runtime, never by normal live assembly. `CameraDebugFixtureTests`
verifies this generated preview, mirroring, and stream shutdown without touching the system camera.
