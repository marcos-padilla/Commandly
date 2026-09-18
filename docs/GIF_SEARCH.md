# Animated GIF Search

Video row 9 (0:37) is implemented as a dedicated original Commandly application: explicit remote GIF Search or Trending, native animated preview, source attribution, original animated-data copy, and native Save GIF. It requires the user's own GIPHY API key. No account is created, terms accepted, or credential provisioned by Commandly.

## Provider and setup

The public GIPHY client API supplies up to 24 provider-ordered results per page. Search submits the exact user phrase without correction or enhancement, limited to 50 characters (and a defensive 400 UTF-8 bytes). Empty text makes no request. Trending is an explicit separate action. Maximum Rating is a provider-side API parameter; Commandly does not filter or reorder returned results. Previous/Next fetch fresh pages. There is no mixed-provider grid, local GIF index, favorites database, or search history.

A dedicated `GIPHYCredentialStore` holds a revisioned API key in the existing injected `SecureStoring` Keychain boundary, under `gif-search.giphy.api-key.v1`. Key fields remain ephemeral and are cleared on Save, Done, disconnect, and session stop. The UI never displays an existing key. Saving a key makes no network request; an explicit search establishes whether GIPHY accepts it. The setup sheet links to the provider dashboard and terms. Beta keys currently allow 100 API calls/hour; GIPHY manages production access and pricing. Unauthorized, rate-limited, offline, oversized, and malformed responses produce sanitized recovery messages.

Changing/removing credentials invalidates request generations and cancels outstanding HTTP work. Every catalog/media result must still match the connection revision after suspension. Concurrent initial Keychain reads share a load; a late read cannot restore a replaced key. Refresh reads current saved status and clears results when its revision differs. Runtime must inject one shared catalog/credential service rather than reconstructing it on every registry refresh.

Primary sources verified 2026-09-14:

- [GIPHY Search endpoint](https://developers.giphy.com/docs/api/endpoint/search/) defines exact-query input, client-side calls, pagination, ratings, and limits.
- [API quick start](https://developers.giphy.com/docs/api/quick-start-guide/) describes user-created keys, beta limits, and attribution requirements.
- [API best practices](https://developers.giphy.com/docs/api/) prohibit URL rewriting, partner media caching without separate approval, proxying, reordering, and mixed-provider result grids.
- [API terms](https://support.giphy.com/hc/en-us/articles/360028134111-GIPHY-API-Terms-of-Service) require GIPHY plus creator/source attribution and prohibit constructing a retained GIF index from the service.
- GIPHY's [desktop sharing guide](https://support.giphy.com/hc/en-us/articles/360020072732-How-to-Share-a-GIF-on-Facebook) describes saving a selected GIF; its [Threads guide](https://support.giphy.com/hc/en-us/articles/5960085935258-How-to-share-GIFs-on-Threads) describes copying and pasting GIF data.

The implementation treats transient buffers required for current display and explicit user copy/save as distinct from a partner-operated media cache or local GIF database. This is an implementation interpretation of the documented sharing flows, not a claim of special provider approval. No retained media cache is implemented. Content remains subject to provider/content-owner terms; attribution does not transfer ownership.

## Network and privacy boundary

Infrastructure exposes framework-neutral GIF catalog, connection-state, and export protocols. `GIPHYCatalogService` creates requests only to `https://api.giphy.com/v1/gifs/search` or `/trending`. `URLComponents` encodes the key and exact query once. Keys are never added to media requests. API responses are limited to 2 MiB; preview downloads to 8 MiB; original animation downloads to 32 MiB. Declared and actual byte counts are checked. Rejected, oversized, and cancelled responses explicitly cancel the underlying URLSession task.

The transport uses an ephemeral session with no URL cache, cookies, credential storage, or redirect following. Media is fetched directly from validated HTTPS URLs on GIPHY's documented media hosts (`media.giphy.com`, numbered `media0`–`media4` hosts, and `i.giphy.com`). Original path and query parameters are preserved. User info, non-443 ports, fragments, non-GIF media paths, HTTP, and other hosts are refused. Unsupported media URLs remain unavailable rows in the original result position instead of silently filtering the page. Source attribution links are opened only by explicit user action; requests do not automatically follow a source URL.

GIPHY receives submitted search terms, the API key on API calls, requested media URLs, and ordinary network metadata including the client IP address. Commandly adds no user IDs or analytics pingbacks, and never logs keys, queries, response bodies, GIF bytes, or request URLs. GIPHY's own media URL parameters remain intact. No clipboard or local file content is read for search. Selecting a result fetches only that result's preview. No extra thumbnails or background trending request is made at launch.

Search/selection/query/rating/connection changes cancel superseded work. Late searches cannot replace a new query's results, and a late original download cannot copy a previously selected GIF. Rapid Return during a search/export coalesces rather than duplicating calls or side effects. A fresh query clears prior results immediately but sends nothing until submitted. Stopping a session clears transient connection/sheet state. Reopening that model waits for an already-authorized Keychain mutation to settle before loading fresh connection state; the retired operation cannot reopen its sheet or publish stale success.

## Native animation and export

`GIFAnimationDecoder` performs ImageIO parsing/decoding on an actor. It validates GIF type, complete source data, dimensions, and multiple frames; static or non-GIF payloads cannot masquerade as animated exports. Original validation allows up to 1,000 frames and 16,777,216 pixels per frame with an 8,192-pixel dimension cap. Preview decoding allows 400 frames, thumbnails up to 360 pixels, and at most 48 MiB of retained decoded frame storage. Native frame timing is bounded to avoid pathological zero/infinite intervals. A SwiftUI timeline displays immutable decoded `CGImage` frames, pauses when requested, and shows a still frame under Reduce Motion. Selection changes release the earlier animation; there is no repeating detached task, arbitrary synchronization sleep, or recurring window.

Copy and Save fetch the original GIF only for that explicit action. Copy writes exact GIF bytes under `com.compuserve.gif` (`UTType.gif`), without inserting a URL or still image fallback. Some receiving apps flatten GIF clipboard input; the interface recommends a saved .gif file in that case. Save validates animation before presenting `NSSavePanel`, holds the selected file's security scope while writing, and closes the panel if its operation is cancelled.

`NativeGIFFileWriter` writes on its actor into the OS-provided item replacement directory, not an assumed writable sibling. It flushes the complete file, coordinates the exact selected destination, rejects symlinks/nonregular destinations and changed file identities, and commits using Foundation safe-save operations. Existing content survives failures before commit. Cleanup errors propagate. A failure after successful commit is specifically described as temporary cleanup failure so the user knows the selected GIF file was saved. No automatic sharing or message sending is implemented. The original GIF bytes are not retained by the model after export; user-selected output and the system clipboard remain until changed by the user/system. Clipboard History may capture an explicit copy if enabled.

## Attribution and accessibility

The app displays the official static Powered By GIPHY attribution mark in light/dark appearance, plus the returned creator/source where available. Original resource provenance and hashes are in `Commandly/Resources/GIPHY/ATTRIBUTION.md`. Only the attribution mark comes from GIPHY; the app layout, text, controls, and generated test animation are Commandly originals. It does not imply provider endorsement.

Native search, rating picker, result List, buttons, secure setup field, and Save panel are keyboard accessible. Return submits a new search, then copies the selected GIF from completed Search or Trending results; editing the query or rating clears the selection before another Return can act. Arrow keys move results; Command–Shift–C copies; Escape cancels the nearest setup/search/download operation before Back leaves. Reduce Motion shows a still preview and disables playback in both the preview and Actions menu; turning it off leaves playback paused until explicitly started. Native source links require explicit activation. Each result exposes its title, creator/source, and distinct supplied description, so equal provider descriptions cannot hide different choices from VoiceOver. Preview panels use a stable selected-item accessibility identity and contain their text/actions. The results list and preview use the remaining launcher height, including compact density; success text appears once in the shared launcher status area. Motion, busy, errors, and success each have text feedback, and Commandly text-size tokens are used throughout.

## Verification and limits

Tests use generated multi-frame ImageIO GIFs, in-memory secure storage, controlled continuations, local URLProtocol responses, and private temporary export paths. They do not call GIPHY, touch real Keychain/clipboard, accept terms, use user credentials, or fetch third-party media. Tests check exact query/URL handling, provider ordering, unsafe hosts and pagination, concurrent key loads/replacement, stopped connection mutation recovery, status/MIME/declared/actual response limits and direct redirect-delegate refusal, cancellation and late results, Trending Return and Reduce Motion actions, multiple decoded frames/timing, original byte copy, native new-file Save and existing-file replacement/reopen, symlink rejection, and failed atomic replacement preserving existing contents.

`GIFSearchDebugFixture.services(exporter:)` offers an explicitly labeled generated UI mode. Its moving-circle GIF is constructed locally with Core Graphics and ImageIO, its catalog/credentials are fake, and its default exporter exercises the real native copy/save UI with generated bytes. It is not evidence of successful live GIPHY search.

Integrated `make verify` passed in `/tmp/commandly-video-verify-tranche17-gif-settings.log`; the clean
signed build passed in `/tmp/commandly-video-native-tranche17-clean.log` and passed deep strict code
signature validation. Native generated acceptance passed search/Trending, Down/Return copying,
Command-K action search and Escape focus restoration, native Save cancellation, and compact/light
appearance with larger text. Native Save produced `/tmp/commandly-generated-gif-tranche17.gif`,
954 bytes with mode 0600; ImageIO reopened all four 120×80 frames. The generated copy used the real
system pasteboard. No GIPHY key, network request, or third-party media was used.

Native review found the connection sheet's long explanations clipped at larger text sizes. It now
scrolls below a fixed Done header, wraps the complete explanations, separates connection state from
actions, clears unrelated export feedback, and explicitly labels generated connection state. Its
follow-up aggregate/native acceptance is pending. Actual user-key authentication and live provider
search remain separate checks. Missing credentials must show setup honestly; production never
silently substitutes generated data.
