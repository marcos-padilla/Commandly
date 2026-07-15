# ADR-0006: BYOK AI providers and Finder tool safety

- Status: Accepted
- Date: 2026-07-15

## Context

Commandly needs optional AI features without operating a paid proxy or taking custody of provider
accounts. The first built-in AI extension lets a user ask questions about files and request Finder
operations. That combines two high-risk boundaries: remote disclosure to a user-selected AI
provider and local filesystem mutation initiated by model output.

The launcher already supports built-in applications with an `AI Extension` role. Its generic
application configuration is intentionally non-secret and cannot store credentials. `SecurityKit`
already defines the secure-storage boundary, File Search already limits discovery to explicitly
authorized folders, and arbitrary shell execution is forbidden.

Provider APIs are similar but not interchangeable. Authentication, model discovery, tool-call
correlation, conversation state, capability metadata, and error semantics differ across OpenAI,
Anthropic, Google Gemini, Mistral AI, Groq, xAI, OpenRouter, and local Ollama. A provider key proving
authentication does not prove that every returned model supports client tools.

## Decision

### Provider and credential boundary

- Add a vendor-neutral `AIKit` package for provider IDs, model descriptors, conversation items,
  JSON-schema tools, normalized completion requests/responses and tool calls/results, provider
  state, typed errors, an explicit adapter registry, and injectable HTTP transport. The app target
  owns each extension's bounded agent loop and local capabilities.
- Keep each provider behind a dedicated adapter. Shared wire codecs may be reused where compatible,
  but provider authentication, endpoints, model discovery, capability policy, errors, and native
  conversation state remain adapter-owned.
- Keep provider-native continuation state opaque, redacted, bounded, memory-only, and scoped to its
  provider. OpenAI Responses use `store: false` and locally replay encrypted reasoning plus native
  function-call items for stateless tool continuations. OpenRouter replays the original native
  `tool_calls` with `reasoning_details` (or its plaintext reasoning field) after verifying normalized
  tool-call correlation.
- The first supported provider set is explicit and versioned. It begins with OpenAI, Anthropic,
  Google Gemini, Mistral AI, Groq, xAI, OpenRouter, and local Ollama. Additional providers are added
  as reviewed adapters; Commandly does not claim automatic compatibility with every service.
- Validate cloud credentials with a non-generation metadata request, then fetch models available to
  that credential. Distinguish invalid credentials from insufficient permissions, explicit billing,
  rate-or-quota limiting, no compatible models, network failure, and provider outage. When a provider
  uses 429 for both traffic limits and exhausted credits, give recovery guidance for both.
- Hold a newly entered key only in memory until validation succeeds and the user chooses a model.
  Store cloud credentials as revision-bound generic-password Keychain items through
  `SecureStoring`. Store only non-secret provider ID, selected model ID, random connection revision,
  endpoint choice, and capability snapshot in UserDefaults-backed preferences. Pin each in-flight
  conversation to that revision and recheck it after every provider response so key/account changes
  that overlap an in-flight request fail closed.
- Never infer a provider from a key prefix. Never place keys in logs, errors, plists, UserDefaults,
  source, analytics, crash breadcrumbs, or request descriptions.
- Official cloud endpoints use HTTPS. Plain HTTP is permitted only for an explicitly configured
  loopback Ollama endpoint. Commandly never downloads an Ollama model automatically.

### Privacy and conversation lifetime

- Opening an AI surface does not contact a provider. Network use starts only after explicit setup or
  a submitted prompt.
- The AI settings and Finder AI surface identify the selected provider and explain that prompts and
  tool results are sent to it under the user's provider account and terms.
- Finder search queries only the filename field, applies authorized-root predicates before ranking
  and limiting, then accepts a hit only after locally rescoring its filename. It
  discloses opaque handles plus bounded structured metadata needed for the active turn, not indexed
  snippets or file contents. Absolute local paths and security-scoped bookmark data are never sent.
- File contents remain local unless the user approves an exact, bounded content-share request that
  names the files and destination provider. Content is treated as untrusted tool data and cannot
  grant capabilities or bypass confirmation.
- Conversations, tool arguments, filenames, paths, contents, and tool results are not logged or
  persisted in the initial release. The application keeps only an in-memory session and clears it
  when the launcher session is torn down.

### Finder capability and approval boundary

- A model receives declarative tools only. It never receives `FileManager`, `NSWorkspace`,
  AppleScript, a process API, a shell, a security-scoped bookmark, or a raw-path operation.
- Finder tools use random, conversation-scoped opaque handles. The local executor maps handles to
  URLs, and revalidates current authorization, canonical containment, resource identity, symlink and
  package behavior, destination collisions, and operation limits before planning and execution.
- Approved bounded text reads use a no-follow descriptor and compare the opened regular file's
  identity before and after reading.
- The only filesystem authority is the current set of folders explicitly selected by the user for
  Files and Folders access. Downloads entitlements, uninstall exceptions, the app container, the
  home root, volume roots, and authorization roots do not implicitly become AI mutation authority.
- A mutation source may not equal or contain any current authorization root, including a nested root
  selected inside a broader root. Commandly-owned data and directory/package ancestors that contain
  it are also excluded as mutation sources, so moving or trashing an allowed ancestor cannot change
  a protected descendant indirectly.
- Read-only metadata tools may run without a second prompt after the user submits a Finder AI
  request. Content disclosure, create, rename, duplicate, copy, move, and Trash require a local,
  exact, expiring confirmation. Approval is single-use and cannot be represented in model JSON.
- Natural-language “delete” maps only to Move to Trash. Permanent deletion, emptying Trash,
  overwrite/merge, arbitrary sharing, package traversal, symlink traversal, permission changes,
  and shell or script execution are not exposed.
- Plans display exact sources, destinations, collision behavior, item counts, relevant warnings,
  and whether a batch can partially succeed. A stale or changed plan must be reviewed again.
- Approved batches run a full preflight and then repeat the relevant authorization, identity,
  destination, and collision checks immediately before each action. A failing action is itemized;
  later independent actions may still run, while cancellation marks pending work cancelled. Reports
  distinguish completed, failed, and cancelled items without implying rollback.
- Tool rounds, result counts, directory entries, mutation item counts, content bytes, duration, and
  output size are bounded. Cancellation propagates through provider and tool work. Completed,
  failed, and cancelled mutations are reported honestly; no rollback or atomicity is
  implied.
- Provider finish reasons are checked against whether tool calls are present. Truncated,
  content-filtered, and refused terminal output is labeled rather than presented as complete. If an
  approved mutation execution returned but the provider tool turn cannot be recorded completely,
  Finder may already have changed; the conversation fails closed and requires a clear before it can
  continue.

### Composition and presentation

- Register a built-in `AI Extensions` group and a Finder AI launcher application. This is native,
  reviewed app code and does not change `ExtensionKit`'s prohibition on loading external code.
- Add a dedicated AI settings pane for provider connections and active-model selection. Secret
  fields do not enter the generic launcher-application schema.
- Finder AI becomes ready only when both a validated tool-capable selection and at least one eligible
  authorized folder are available. A zero-root state disables prompts and routes to Permissions.
- UI state remains on `@MainActor`; networking, decoding, provider state, and filesystem work live
  behind injected `Sendable` services/actors. Leaving the application cancels active inference and
  pending tool work.
- Add the App Sandbox outbound-network client entitlement. No new TCC prompt occurs; filesystem
  grants remain contextual and user selected.

## Consequences

- Users pay providers directly and can revoke a key without a Commandly account.
- A provider outage, quota, region, or model capability change can still make a previously validated
  configuration unavailable; runtime errors must not be misreported as an invalid key.
- Supporting a new provider requires a tested adapter and explicit catalog entry, but not changes to
  Finder tools or launcher routing.
- Opaque state and local approvals add implementation complexity, but keep provider wire formats and
  model output outside the filesystem trust boundary.
- Metadata and approved content can leave the Mac. The product must present that fact clearly and
  cannot describe Finder AI as offline or local-only when a cloud provider is active.
- Keychain protects stored credentials at rest; each cloud provider still receives its credential
  over the authenticated API connection for each request. The loopback Ollama adapter has no key.

## Rejected alternatives

- One universal “OpenAI-compatible” client: compatibility gaps are material and would create brittle
  tool loops and misleading model support.
- Storing keys in launcher configuration or UserDefaults: violates the security model and ADR-0005.
- Testing a key with a paid generation: wastes user quota and conflates authentication with model
  behavior.
- Giving the model raw paths or a general Finder/AppleScript bridge: bypasses scoped authorization
  and makes prompt injection materially dangerous.
- A blanket “always allow” switch for mutations: a future model mistake would retain ambient write
  authority.
- Permanent deletion as a tool: unnecessary for the requested workflow and not safely recoverable.
- Persisted transcripts in the first release: requires a separate retention, encryption, deletion,
  and search-privacy decision.

## Primary API references

- [OpenAI model listing](https://developers.openai.com/api/reference/resources/models/methods/list),
  [function calling](https://developers.openai.com/api/docs/guides/function-calling), and
  [stateless reasoning preservation](https://developers.openai.com/api/docs/guides/reasoning#preserve-reasoning-without-stored-responses)
- [Anthropic model listing](https://platform.claude.com/docs/en/api/models/list) and
  [tool use](https://platform.claude.com/docs/en/agents-and-tools/tool-use/how-tool-use-works)
- [Gemini models](https://ai.google.dev/api/models) and
  [function calling](https://ai.google.dev/gemini-api/docs/generate-content/function-calling)
- [Mistral models](https://docs.mistral.ai/api/endpoint/models) and
  [chat completions](https://docs.mistral.ai/api/endpoint/chat)
- [Groq API reference](https://console.groq.com/docs/api-reference),
  [OpenAI compatibility](https://console.groq.com/docs/openai), and
  [local tool calling](https://console.groq.com/docs/tool-use/local-tool-calling)
- [xAI language models](https://docs.x.ai/developers/rest-api-reference/inference/models),
  [Chat Completions](https://docs.x.ai/developers/model-capabilities/legacy/chat-completions), and
  [function calling](https://docs.x.ai/developers/tools/function-calling)
- [OpenRouter model catalog](https://openrouter.ai/docs/guides/overview/models),
  [tool calling](https://openrouter.ai/docs/guides/features/tool-calling), and
  [reasoning-token preservation](https://openrouter.ai/docs/guides/best-practices/reasoning-tokens)
- [Ollama model listing](https://docs.ollama.com/api/tags) and
  [native tool calling](https://docs.ollama.com/capabilities/tool-calling)
