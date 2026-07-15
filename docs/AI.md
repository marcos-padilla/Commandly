# AI and Finder AI

## Scope

Commandly's AI system is optional and uses **bring your own key (BYOK)**. Commandly does not proxy
requests, sell AI access, or operate a shared provider account. A user connects a provider directly,
validates the credential through a metadata endpoint, chooses a model visible to that credential,
and can then use built-in AI extensions.

The first built-in AI extension is **Finder AI**. It answers questions about files inside folders the
user has already authorized and can propose native filesystem operations. A model never receives a
general filesystem API, raw path authority, AppleScript, or a shell.

This document describes implemented boundaries and deliberate first-release limitations. See
[ADR-0006](decisions/ADR-0006-byok-ai-and-finder-tool-safety.md) for the accepted decision.

## User setup flow

1. Open **Settings → AI**.
2. Choose a supported provider.
3. For a cloud provider, paste an API key. Commandly immediately removes that exact value from its
   in-memory Clipboard History, and the settings draft remains only in memory at this point. Ollama
   instead uses an explicit loopback endpoint and does not require a key.
4. Choose **Validate**. Commandly makes a non-generation metadata request; it does not spend tokens
   merely to test the credential.
5. Commandly lists models returned for that account and marks tool support when the provider reports
   it or the adapter has reviewed compatibility data.
6. Select a model and choose **Save & Use Model**. Only then does Commandly store the cloud key in
   the macOS Keychain and persist the non-secret provider/model selection.
7. Additional provider connections can be saved. One is active at a time. Disconnecting deletes its
   Keychain item and non-secret selection.
8. For Finder AI, open **Settings → Permissions → Manage Folders** and choose one or more specific
   folders. Finder AI stays unavailable when no eligible root remains and links directly to that
   recovery screen; Home, folders above Home, and whole volumes do not count as eligible roots.

Validation reports separate states for invalid credentials, insufficient permission, explicit
billing failures, provider rate-or-quota limiting, invalid local endpoints, provider outage/network
failure, and a valid account with no compatible models. Some providers use HTTP 429 for both traffic
limits and exhausted credits, so that recovery message directs the user to retry and then check
credits/spending limits if it persists. A runtime request may still fail later if the provider changes
quota, region, model availability, or key ACLs.

## Supported providers

Support is an explicit adapter contract, not a claim that every nominally compatible endpoint works.

| Provider | Authentication | Discovery | Initial generation/tool runtime |
|----------|----------------|-----------|---------------------------------|
| OpenAI | Bearer API key | Credential-scoped Models API | Stateless Responses API function tools with bounded encrypted-reasoning replay |
| Anthropic | `x-api-key` | Credential-scoped Models API | Messages API tool use |
| Google Gemini | `x-goog-api-key` | Paginated Models API | Native `generateContent` function calls and responses |
| Mistral AI | Bearer API key | Credential-scoped Models API | Chat Completions with client function tools |
| Groq | Bearer API key | Hosted Models API filtered through a reviewed tool-model allowlist | OpenAI-compatible Chat Completions with local tool calling |
| xAI | Bearer API key | Language Models API | Stateless Chat Completions with client function tools |
| OpenRouter | Bearer API key | User-filtered model catalog | Chat Completions tools with bounded native reasoning replay |
| Ollama | No key for loopback | Installed models from the local daemon | Native local chat/tools |

OpenAI-compatible wire similarities are shared only by a reviewed internal codec. Authentication,
fixed endpoints, discovery filters, error policy, capability evidence, and provider context stay
adapter-specific. A custom endpoint is not treated as supported merely because it accepts an
OpenAI-shaped request.

Cloud hosts are fixed in their adapters and use HTTPS. Ollama is restricted to `localhost`,
`127.0.0.1`, or `::1`; Commandly does not permit arbitrary plaintext remote endpoints and never
downloads a model automatically.

## Package architecture

`AIKit` is a domain-neutral local Swift package. It does not import the Commandly app target,
SearchKit, AppKit, or filesystem services.

It owns:

- `AIProviderID`, provider descriptors, authentication requirements, and provider capabilities
- Credential-scoped `AIModelDescriptor` values and capability-evidence provenance
- A redacting, non-Codable `AICredential`
- Provider configuration containing only a credential wrapper and reviewed non-secret values
- `AIJSONValue` plus a portable, typed JSON Schema subset for tool definitions
- Normalized messages, tool calls, tool results, finish reasons, token usage, and opaque provider
  continuation state
- Sanitized errors and rich validation outcomes
- An injectable HTTP transport whose description redacts headers, query strings, and bodies
- A duplicate-safe provider registry and provider-independent model catalog
- Dedicated provider adapters and deterministic HTTP fixtures in package tests

The production transport uses an ephemeral URL session with no cookie, credential, or URL cache,
rejects cross-origin redirects, and enforces 4 MiB request and 32 MiB response-body guards.
Provider-native state is opaque, redacted, memory-only, and can be returned only to the same
provider. This prevents the common mistake of reducing a tool conversation to plain role/text pairs
and losing OpenAI encrypted reasoning/function-call items, Gemini thought signatures, correlation
IDs, or other provider-specific continuation material. OpenAI requests keep `store: false`; tool
continuations manually replay only bounded native output items retained for the active in-memory
tool chain rather than relying on a provider-stored response. OpenRouter likewise retains the exact
native `tool_calls` together with `reasoning_details` (or the provider's plaintext reasoning field)
and replays that bounded state only when the normalized tool-call sequence still correlates.

OpenAI and OpenRouter tools currently declare `strict: false`. AIKit's portable schemas allow
optional object properties, while strict function-schema modes can require every property to be
listed as required and represent optional values through nullable required fields. The portable
schema can adopt strict mode later only after it can express and validate that distinction without
changing Finder tool semantics. Commandly still validates every tool name and argument locally.

The app target owns:

- Keychain-backed `SecureStoring`
- Non-secret connection preferences
- Settings state and views
- Active-provider composition
- Finder authorization, opaque resource handles, native tools, approval coordination, and UI

## Secrets and local persistence

Cloud API keys are generic-password Keychain items scoped to Commandly's bundle-based service name.
They use device-only, when-unlocked accessibility. Keychain failures are mapped to fixed error cases
that do not include an account, key, raw status payload, request, or response.

UserDefaults stores a versioned non-secret payload containing:

- Provider ID
- Selected model ID and display name
- A random configuration revision used to pin an in-flight conversation
- Explicit local endpoint, when applicable
- Capability snapshot used for UI/runtime gating
- Active provider ID

It never stores a key, prompt, response, conversation, tool arguments, filename, path, bookmark,
content, or provider error body. Conversation state is held in memory for the current launcher
session and is cleared when that session ends.

The Keychain record is bound to the same revision as the non-secret connection record. Updating a
key or model rotates that revision. The runtime compares the pinned revision and Keychain record
both before sending and after receiving a completion, so a response that overlaps a connection or
credential rotation is discarded instead of carrying stale context into a newly selected account.

## Network and disclosure behavior

Opening Commandly, Settings, or Finder AI does not send an inference request. Provider traffic starts
after explicit validation or after the user submits a prompt.

For a cloud provider, the following can leave the Mac during a Finder AI conversation:

- The user's prompt
- The Finder AI system/tool instructions
- Bounded structured metadata returned by a tool, including an item's display name and relative
  location inside an authorized root. Automatic local-index search queries filenames only, applies
  the authorized-root filter before ranking/limiting, and locally rescores the filename. It returns
  metadata and opaque handles, never an indexed snippet, hidden absolute-path match, or file contents.
- An exact bounded text payload only after a separate content-share approval
- Tool success/failure results needed for the model to continue a multi-step request

Absolute local paths, security-scoped bookmarks, API keys in message content, and unapproved file
contents are not sent. The selected provider processes disclosed data under the user's provider
account and terms. Ollama traffic stays on the explicitly configured loopback endpoint, subject to
the locally installed Ollama software.

Tool output and file contents are untrusted input. Text inside a filename or document cannot grant a
new capability, approve a plan, change tool policy, or ask Commandly to execute another interface.

## Finder AI local authority

Finder AI uses only folders selected through Commandly's existing **Files and Folders** flow. The
Download read entitlement, application-uninstall exceptions, and Finder Automation entitlement do
not become AI authority.

Each conversation creates a session. The Finder workspace actor issues random IDs for authorized
roots and discovered items and keeps the URL mapping locally. Model tools accept only these IDs.
Handles expire when the session ends and cannot be used across sessions.

Before every read plan or mutation, Commandly rechecks:

- The session and handle still exist
- The item remains inside a current authorized root by a path-component boundary and canonical
  relationship
- The root and resource identity have not changed
- The requested operation has the needed read/write capability
- The destination is an authorized directory
- The destination is not the source or its descendant
- Names contain no traversal, separator, control, hidden-name, or overlong component
- Collision behavior is exact and non-overwriting
- Keep-both name selection is cancellable and tries at most 1,000 alternatives
- Approved text is opened with a no-follow descriptor and the open file's identity is checked before
  and after its bounded read
- The item is not `/`, a volume root, the user home root, an authorization root, or Commandly's own
  data

An outer authorized folder does not make a nested authorization root mutable: an item that equals or
contains another current authorization root is rejected as a mutation source. Likewise, Commandly's
owned data stays excluded when it sits below a broader authorized folder; the owned subtree and any
directory/package source whose lexical or physical subtree contains that data cannot be moved,
renamed, duplicated, or trashed. This prevents a permitted operation on an ancestor from indirectly
changing a protected descendant.

Symbolic links and Finder aliases are treated as leaf items. Their targets are not traversed.
Packages are opaque items; package descendants are not listed or read. A whole package can be moved
or trashed only as an explicitly reviewed item.

## Finder tool catalog

Read/query tools are bounded and may run automatically after a submitted prompt:

- List authorized roots
- Search filenames in the existing local file index; results include a locally recomputed
  root-relative location
- List one directory level
- Fetch bounded metadata for known handles
- Reveal a known item in Finder

Text reading has a separate two-stage boundary: the model can request a bounded read plan, but only
the local approval coordinator can approve and read it. The approval names the provider and items.
The first release decodes UTF-8 text; if a byte cap cuts a multi-byte scalar, Commandly trims only that
incomplete trailing scalar and marks the result truncated.

Mutation tools create an exact local plan:

- Create folder
- Rename
- Duplicate
- Copy
- Move
- Move to Trash

A model cannot execute a plan. The user reviews an exact, expiring plan and the local UI issues a
single-use, non-Codable approval value. Any item identity change, collision, authorization change,
expiry, edit, or previous use invalidates approval.

Permanent deletion, emptying Trash, overwrite/merge, recursive arbitrary paths, automatic sharing,
opening executable content, permission/ownership changes, package traversal, symlink traversal,
AppleScript, process launch, and shell execution are not tools.

## Agent loop

Finder AI performs a bounded provider/tool loop:

1. Add the user's prompt to the in-memory transcript.
2. Ask the active model for text or typed tool calls.
3. Validate every provider response, finish reason, tool name, and top-level argument object locally.
   Unknown tools, malformed calls, and mismatched tool/finish states reject the provider turn;
   recognized calls that fail local argument or workspace validation return a sanitized correlated
   tool error. No model value is interpreted as a path or command.
4. Execute bounded read-only tools, or pause on a content/mutation approval.
5. Return normalized results to the same provider with the correct tool-call correlation state.
6. Continue until the model produces an answer or the configured tool-round limit is reached.

One turn owns the session at a time. Each turn is capped at eight provider rounds, 24 total tool
calls, and eight calls per round. The prompt is capped at 64 KiB, the transcript at 64 messages and
1 MiB, aggregate tool results at 512 KiB, and provider output is requested with a 2,048-token cap.
Cancelling or leaving Finder AI cancels provider work, approval waits, and pending tool work. A
filesystem call already in progress may finish; itemized reports distinguish completed, failed, and
cancelled operations and do not claim rollback or atomicity. Length-limited, content-filtered, and
refused terminal responses retain any returned text but are labeled honestly; an unknown finish
reason or a tool-call/finish-reason mismatch rejects the turn. If an approved Finder mutation
execution returns but a later call prevents that provider tool turn from being recorded completely,
the UI keeps its activity visible and requires the user to clear the conversation before another
prompt. Finder may already have changed, so the model must not continue with an incomplete
transcript.

## Adding a provider

1. Confirm a native Apple networking implementation is sufficient; do not add an SDK by default.
2. Review official authentication, model-discovery, tool-calling, state, rate-limit, and error docs.
3. Add a stable provider ID and dedicated `AIProviderAdapter`.
4. Keep the official TLS host fixed unless the provider is the reviewed loopback-only local adapter.
5. Implement free validation/model discovery and preserve `401`, `403`, explicit billing,
   rate-or-quota-limit, network, and server distinctions. Do not claim a finer distinction when a
   provider uses the same status for traffic limits and exhausted credits.
6. Report capability evidence as provider-reported, curated, or compatibility-layer evidence.
7. Normalize tools using only the portable JSON Schema subset and validate arguments locally.
8. Preserve native tool correlation and opaque continuation state.
9. Add deterministic transport fixtures for authentication headers, discovery pagination/filtering,
   tool calls/results, malformed payloads, status mapping, and cancellation.
10. Add the adapter to the explicit catalog only after its tests pass and update this document.

## Adding an AI extension

1. Define the user behavior, local data boundary, disclosure policy, tool effects, and approval policy.
2. Keep extension-specific types and services out of `AIKit`; inject them behind typed app/domain
   protocols.
3. Return opaque local handles rather than ambient identifiers such as paths, database keys, or
   credential references.
4. Classify every tool as read-only, mutating, or destructive and enforce confirmation outside the
   model.
5. Bound calls, results, bytes, duration, and recursion; support cancellation.
6. Register a native launcher application with kind `AI Extension` and structured documentation.
7. Add unit tests that never use a real key, provider network, Keychain, permission prompt, or user
   file.
8. Review privacy, accessibility, sandbox capabilities, prompt-injection resistance, and partial
   failure reporting before enabling the extension.

## Initial limitations

- Provider responses are non-streaming in the first vertical slice; the UI still exposes explicit
  working and cancellation states.
- Finder AI does not expose arbitrary binary-file reading or image/PDF upload.
- Operations are confirmed one exact plan at a time; there is no persistent “always allow” mode.
- Batch filesystem operations are not transactional.
- Conversations are not searchable, synced, or restored.
- Protected locations and folders not explicitly selected remain unavailable.
