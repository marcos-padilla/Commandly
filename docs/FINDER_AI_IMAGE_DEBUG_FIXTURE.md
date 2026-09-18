# Generated Finder AI image acceptance fixture

DEBUG-only `FinderAIImageDebugFixture().services` injects the existing Finder AI view-model,
workspace, tool executor, and local approval coordinator. It adds no alternative conversation view
or fabricated tool execution. The provider label is **Generated Local Fixture · Image Conversion
Script**, and each scripted assistant message explains that this is a generated local demo.

The exact supported prompt is:

> Convert the generated image to a 320-pixel JPEG rotated clockwise.

Any other prompt returns the fixed demo instructions without requesting tools. The fixture's runtime
has no connection store, credential store, provider adapter, HTTP client, network request, or text
reading implementation. It never sends a request to a real provider.

## Behavior and boundaries

Constructing the fixture chooses a fresh UUID path, but creates no files. When Finder AI explicitly
opens, the runtime's selection preparation asks the fixture actor to generate one original 640×360
PNG with geometric shapes and a **GENERATED IMAGE** label. CoreGraphics, CoreText, and ImageIO run on
that actor, away from MainActor. The generated PNG and empty Output folder are under one fresh
`Commandly-Generated-Finder-Image-UUID` directory in the app's system temporary area. The directory
uses 0700 permissions and its generated image 0600. The code never scans prior fixture directories
or overwrites an existing fixture root.

The real workspace receives only this direct generated root, an empty in-memory bookmark store,
empty in-memory search, and an in-memory revealer. It never receives the user's folder store or
search index. DEBUG protected-root overrides refer only to generated boundaries; there is no release
permission change. The actual converter is `NativeImageConversionService`.

The script requests `finder_list_roots`, then `finder_list_directory`, parses the actual opaque UUID
handles from those results, and proposes `finder_convert_image`. The normal approval card shows
`generated-source.png`, Output/generated-converted.jpg, JPEG, a 320-pixel longest edge, clockwise
rotation, and the existing fidelity/privacy information. No image conversion or output write occurs
before **Approve Once**. **Deny** and leaving the application retain the generated input without
conversion. **Approve Once** runs real local conversion through the normal single-use mutation
approval, file authority checks, and exclusive publication path.

Successful native conversion creates a 180×320 JPEG. The script reports success only after its actual
correlated tool result contains one completed output named generated-converted.jpg. Failure or an
existing output produces honest failure text; the fixture does not overwrite it, silently select a
new name, or delete it for retry. Denied turns can be retried normally. To repeat a successful fresh
output test, restart with a fresh fixture instance. Generated files intentionally remain for local
inspection under the OS temporary area; no timed deletion or cleanup of previous runs is claimed.
No user data is stored there by the fixture.

## Root integration

For DEBUG productivity acceptance only, select `FinderAIImageDebugFixture().services` instead of the
live Finder services. No normal-user preference, provider selection, or permission store is changed.
All release configurations continue using live services. The runtime retains the generator, so the
root does not need to store the fixture separately. If useful for local test inspection, the fixture
exposes its actor's immutable `directory`, `source`, and `output` generated URLs; do not log real paths
through any production logger.

The root owns the AppRuntime/CommandlyProductivityDebugFixture integration. This slice changes none
of those files, nor the registry or Finder view/view-model.

## Verification and acceptance

`FinderAIImageDebugFixtureTests` passed all four deterministic tests in an isolated Swift 6 harness
using the actual FinderAIViewModel, FinderAIToolExecutor, FinderAIWorkspaceService, and native image
converter. Only app service/runtime type declarations are mirrored to avoid importing app assembly.
The staged DEBUG sources and tests also compile against the real app modules under strict Swift 6
concurrency and app default MainActor isolation. Logs:
`/tmp/commandly-finder-image-ui-slice/isolated-tests.log` and `compile.log`.

Tests verify lazy generation, the visible generated provider label, exact approval settings and
filenames, no output before approval, real JPEG type/dimensions, unchanged PNG input, single-use
approval, denial then retry, unsupported input without tools, leaving during approval, distinct
fixture roots, only one authorized root, collision preservation, and wrong-provider rejection.
They use generated files only and remove only their own UUID roots. They never use credentials,
clipboard, networking, real folders, or permission prompts.

Combined `make verify` passed in `/tmp/commandly-video-verify-tranche13-companion.log`. Native
acceptance in the signed sandboxed DEBUG app entered the exact prompt, reviewed the exact source,
destination, JPEG, 320-pixel longest edge, clockwise rotation, alpha/metadata treatment, and selected
Approve Once. The normal conversation then reported one completed operation and the actual successful
tool result. The generated JPEG exists with 0600 permissions (7,222 bytes); the generated PNG remains
present (13,153 bytes). macOS denied external command-line content reads of the app container, so
dimensions and unchanged source bytes are supported by the native codec/conversation tests above.
Native Deny/retry remains a separate UI check; it passes in the automated conversation tests. This
establishes the real local tool/UI success path with a scripted provider; it does not establish a real
provider's natural-language planning quality or account/network behavior.
