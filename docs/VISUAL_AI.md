# Visual AI

Visual AI (`ai.visual`) adds Full Screen (`ai.visual.screen`) and Selected Region (`ai.visual.region`) screenshot context as a separate native launcher application. It reuses Screenshot capture and existing configured AI connections. Opening either tool loads local saved model choices only. No capture, credential read, inference request or permission request happens at open.

## Capture, preview, remove, send

Capture is explicit. Full Screen uses the existing macOS picker to choose exactly one full display. Region reuses Screenshot’s original region overlay and its explicit Screen Recording permission flow. The capture adapter conceals/restores the existing launcher while selecting. This feature introduces no new native capture authority or automatic permission request.

The image is decoded, reduced to at most 2,048 pixels per edge, rasterized to fresh sRGB pixels and encoded as JPEG of at most 2 MiB on a dedicated serial actor executor. A bounded set of compression qualities is tried locally. The UI previews the exact JPEG bytes that Send will use, including reduced resolution/compression, before making Send available. Remove clears the image; Capture Again replaces it. No provider upload, file ID or remote image URL is created.

The destination picker offers saved OpenAI, Anthropic and Gemini models supported by an explicit curated image-capability predicate. New discovery results expose `.imageInput` for the same predicate. Existing saved connections can use that reviewed compatibility knowledge without a metadata request. Unknown or specialized models and other adapters remain unavailable until reviewed. Refresh Models reloads saved local choices; configure/select another model in AI Settings.

Send explicitly discloses that the screenshot and question go to the selected provider under the user’s account. The exact saved connection is pinned and checked before and after the existing credential-backed runtime request, with credential revision validation. Changing a connection invalidates the request result. The normal fixed-host transports, redirect policy and 4 MiB request-body bound remain unchanged.

## AIKit boundary

`AICompletionRequest.imageInput` is optional and defaults to nil. `AIImageInput` is non-Codable, bounded and redacted from reflection/debug output. The new path accepts one text user message plus optional system instructions, no provider continuation state and no tools. It inserts actual inline image bytes into the provider request. Requests for unsupported provider/model pairs fail before dispatch. Text-only payload construction is unchanged.

- OpenAI Responses uses `input_image` with a local data URL. See [OpenAI image input](https://developers.openai.com/api/docs/guides/images-vision).
- Anthropic Messages uses an `image` block with a base64 source. See [Claude vision](https://platform.claude.com/docs/en/build-with-claude/vision).
- Gemini uses a `Part` containing inline image data. See [Gemini image understanding](https://ai.google.dev/gemini-api/docs/image-understanding) and [Content/Part reference](https://ai.google.dev/api/caching#Content).

The model receives no filesystem, browser, clipboard, shell or computer-control tools. Visible text is explicitly treated as untrusted screenshot content. Each submission is independent; no previous prompt, response or screenshot is replayed. Output is requested at 2,048 tokens and locally bounded to 64 KiB, with refused/filtered/length outcomes labeled.

## Cancellation, retention and limits

Cancel stops local capture or provider work and generation checks reject late completion. Data already sent cannot be recalled, and the UI says so. Remove, Back and launcher dismissal clear local screenshot/answer state. No image, prompt, result, connection credential or screenshot metadata is added to persistence or logs. Existing saved connection preferences and Keychain are reused without changes. Provider processing remains subject to that provider’s terms.

Only one display or one region is captured per request. Full Screen does not silently combine multiple displays. Image downsizing/compression may remove fine detail. This is single-turn image analysis, not live screen monitoring, streaming output, chat history, or computer control.

## Verification

September 17, 2026: the copied actual AIKit, Infrastructure, SecurityKit and screenshot adapters plus the Visual AI service/model/view and launcher session conformance compiled with Swift 6 complete concurrency and warnings-as-errors. The app slice additionally uses MainActor default isolation, NonisolatedNonsendingByDefault and MemberImportVisibility. Three focused tests in two suites passed; the provider payload test runs all three real adapter codecs against a recording transport. Generated pixels exercise image preparation and separate Capture/Remove/Send actions.

No native screen capture, TCC, real credential, provider network, or root build was used for this evidence. Root registry/runtime/app-wrapper compilation, final make verify and intentional native/provider acceptance remain separate gates.
