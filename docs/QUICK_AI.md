# Quick AI

Quick AI is a separate, general text-chat application. It uses configured BYOK connections, streams
provider text as it arrives, and sends completed conversation context with follow-up messages.
Finder AI and its filesystem/tool authority remain separate. This slice addresses video cues 26,
27, and 52; broader voice, browser, attachment, agent, search, and sync requirements remain tracked
in [the video inventory](VIDEO_FEATURE_PARITY.md).

## Interaction

Open **Quick AI** or **Open AI Chat**. Without a configured provider, **Open AI Settings** routes to
the existing validation and model-selection screen. Opening chat and reloading the configured list
read only saved non-secret metadata: no credential lookup, model discovery, or inference occurs.

The header initially lists the saved model for each configured provider; the active connection in
AI Settings supplies the initial choice. **Refresh Models** explicitly contacts the selected provider
with its saved credential to request compatible text models. The disclosure identifies the provider
before the request; Cancel or Escape stops discovery. The searchable picker then offers returned
models from that provider alongside other configured providers. Discovery sends no conversation text
and does not perform a generation request. It reads no key or network data until the user asks to refresh.

Choosing another model or provider affects this chat only. If a conversation or draft exists, the user
confirms starting a new chat before the switch; prior messages are cleared and are not sent to the new
model. The global active provider, saved model, and connection revision remain unchanged. Model catalogs
are held in this view session and discarded on teardown, not persisted. **Reload Saved Connections**
reads only saved metadata and drops catalogs whose connection revision changed.

Discovery failures, empty catalogs, and cancellations keep the current transcript, draft, and choices.
A successful refresh that no longer lists the current model keeps its transcript visible and requires
an explicit model change before sending again. Credential/connection changes disable new requests and
route recovery to AI Settings plus Reload Saved Connections. Errors contain fixed recovery instructions,
never raw provider response bodies. Available models are the supported adapter's compatible subset:
existing curated model and capability rules remain in force, so this is not an unfiltered vendor catalog.

Return sends; Shift-Return inserts a line. The recipient disclosure appears beside the composer.
Replies arrive incrementally, remain selectable, and expose a visible Stop control. Escape cancels
the reply before leaving the application. The Follow Reply toggle controls automatic scrolling so
earlier messages can be read during generation. Suggestions populate the draft without submitting it.

Retry replaces the last failed/stopped pair and resends its original message with the last completed
context. Failed or stopped partial replies remain visibly labeled but are excluded from follow-up
context. Length-limited and refused/filtered responses retain actual returned text with explicit
labels. New Chat and session teardown cancel work and clear conversation state.

## Architecture

| Owner | Responsibility |
| --- | --- |
| `AIKit/AIHTTPStreamingTransport.swift` | Incremental, backpressured, bounded HTTP lines using an ephemeral URLSession and existing same-origin redirect policy |
| `AIKit/AITextStreamingTransport.swift` | Converts an existing adapter's generation request to its reviewed streaming mode and reconstructs a final response for that same adapter |
| `AIKit/AITextStreamCodec.swift` | Provider-specific SSE/NDJSON text fragments, terminal frames, and text-only enforcement |
| `Commandly/Services/AI/QuickAI/QuickAIService.swift` | Configured catalog, revision-bound read-only connection projection, live streaming and inert fixture service |
| `QuickAIApplicationServices.swift` | Focused live/in-memory composition API |
| `Commands/QuickAI/QuickAIViewModel.swift` | Session transcript, incremental presentation, cancellation, retry/reset, selection confirmation, and failure states |
| `Commands/QuickAI/QuickAIView.swift` | Keyboard-focused original chat UI and selectable text |
| `Applications/QuickAIApplication.swift` | Application/tool registration and existing AI Settings navigation |

The existing provider runtime still owns credential access, connection checks, adapter resolution,
request validation, and final completion checks. Existing adapters still own authentication, official
hosts, provider-specific request encoding, model rules, and final response normalization. Streaming
is an opt-in transport bridge used only by Quick AI; Finder AI's existing non-streaming path is unchanged.
No artificial token splitting or delayed animation stands in for streaming.

`QuickAIApplicationServices.live(connectionStore:credentialStore:registry:streamTransport:discoveryTransport:)` composes
production behavior from existing app dependencies. The stream transport defaults to
`URLSessionAIHTTPStreamingTransport`. Explicit discovery reuses `AIKitConnectionService`, the same
model validation boundary used by AI Settings, with an injectable `AIHTTPTransport` for the local
endpoint resolver (the registry already owns its cloud adapters). `.inMemory` is inert with no
configured providers by default; its optional discovered choices support native fixture validation.
The registry registers `QuickAIApplication(services:)`; the runtime fixture should inject an in-memory
service instead of live dependencies. No native network request occurs during construction.

## Connection and privacy boundary

Each conversation pins provider ID, selected model ID, and the original saved connection revision.
A discovered selection contains an immutable private metadata grant tied to the entire original saved
connection. The ordinary saved-pair initializer cannot authorize an arbitrary model. The read-only
runtime projection substitutes the explicitly chosen discovered model into a local preference snapshot,
then verifies the original source connection before every read. It never writes preferences or changes
the global active provider. Discovery checks the revision-bound credential and source connection before
its request and repeats those checks after its response; stale choices cannot be used for generation. Before each visible text fragment, the service checks the saved connection
and revision-bound credential. The runtime also repeats its final connection/credential checks.
Rotations, disconnects, or changed models stop the response, remove provisional text, and require
a new chat. Canceled or superseded tasks cannot update a later session.

The application has no tool executor, file/screen/clipboard/calendar access, or attachment importer.
Only explicitly submitted text and completed conversation context are sent. Cloud traffic uses the
existing fixed HTTPS adapters; Ollama uses the existing validated loopback endpoint. Credentials stay
behind the existing secure-store boundary and do not enter the model or view. Provider-generated tool
payloads are rejected; no tool is run. Hidden reasoning fields are not displayed as the answer.

Prompts, replies, draft text, retry state, and conversation context are memory-only. They are not logged,
persisted, uploaded elsewhere, or added to search/command history. Session teardown clears them.
Native keys, request bodies, provider error bodies, tokens, and private response text are not included
in logs or status messages. URLSession has no cookie store, credential cache, or URL cache, and retains
the existing same-origin redirect restriction.

Discovery retains at most 256 compatible models per configured provider, deduplicates IDs, and rejects
empty/whitespace/control-character identifiers or names and strings over 1 KiB.

The model bounds each prompt to 64 KiB, transcript to 64 displayed/provider messages and 1 MiB including
reserved response capacity, and response text to 256 KiB. Provider output requests cap at 2,048 tokens.
The streaming path limits the wire response to 4 MiB, a line/frame to 512 KiB, and parsed events to
32,768. Async callbacks provide backpressure; there is no unbounded event buffer or timer-based fake
stream. Stopping cancels the local HTTP request and ignores subsequent events. Provider-side processing
and billing after cancellation remain subject to that provider.

## Reviewed streaming protocols

These are explicit adapter capabilities verified through deterministic protocol fixtures, not live
account/model availability claims. A saved model can still reject a request because of availability,
quota, permission, or capability, and the UI directs the user to retry or choose a configured model.

- OpenAI uses Responses text/refusal deltas and the final response event; its existing adapter retains
  `store: false`. [Official streaming guide](https://platform.openai.com/docs/guides/streaming-responses).
- Anthropic uses message/content-block events and a final message-stop marker. [Official streaming
  documentation](https://platform.claude.com/docs/en/build-with-claude/streaming).
- Gemini uses `streamGenerateContent` SSE with candidate text and finish reasons. [Official generation
  reference](https://ai.google.dev/api/generate-content).
- Mistral uses streaming chat-completion deltas and a completion marker. [Official chat API](https://docs.mistral.ai/api).
- Groq uses incremental Chat Completions deltas. [Official text-generation documentation](https://console.groq.com/docs/text-chat).
- xAI uses SSE chat chunks. [Official streaming documentation](https://docs.x.ai/developers/model-capabilities/text/streaming).
- OpenRouter supports SSE comments and a repeated terminal reason in its final usage frame, which the
  parser accepts without treating it as a second answer. In-stream errors fail the turn. [Official
  streaming specification](https://openrouter.ai/docs/api_reference/streaming).
- Ollama uses newline-delimited chat messages and an explicit final done marker. [Official chat API](https://docs.ollama.com/api/chat),
  [streaming guide](https://docs.ollama.com/capabilities/streaming).

## Verification

`AITextStreamingTests` covers every reviewed provider wire format using its existing final adapter
decoder, genuine incremental callbacks, outgoing streaming mode, SSE comments/multiline frames,
OpenRouter's usage frame, malformed/missing terminal frames, in-stream errors, unexpected tools,
output bounds, and callback cancellation. `QuickAIServiceTests` verifies no credential/network access
on open, selected non-active connections without global preference changes, text-only requests,
stale revisions, credential rotation between visible fragments, explicit official-adapter model
metadata requests, use of a discovered model without saving preferences, rejection of undiscovered
model IDs, stale discovery grants, credential rotation during discovery, and bounded capability filtering. `QuickAIViewModelTests` covers
incremental rendering state, follow-ups, cancellation/stale callbacks, retry, selection confirmation,
revision invalidation, reset/teardown, bounds, and length-limit presentation. `QuickAIApplicationTests`
covers session creation and AI Settings routing. `QuickAIModelPickerTests` covers explicit discovery,
model-switch confirmation/context clearing, preserved drafts/transcripts on failure and empty results,
cancellation/stale results, teardown, removed models, and changed saved connection revisions.

All tests use fixture credentials, transports, events, and controlled continuations. They never contact
a real provider, read Keychain, access user data, or wait for arbitrary wall-clock delays. The parent
task runs the coherent package/application tests and full verification after integration. No live
provider account or model has been exercised by this implementation task.

Current limits: plain text response presentation; provider-adapter model subset; ephemeral sessions;
no web browsing, attachments, tools, agent execution, voice, persistent chat history, search, or sync.
Those are remaining product requirements, not silently excluded scope.
