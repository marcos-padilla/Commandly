# Security Model

## Future risk areas

| Risk | Why it matters | Foundation stance |
|------|----------------|-------------------|
| Malicious extensions | Third-party code can steal data or crash the app | No loading yet; manifests only |
| Command injection | User text interpolated into shells | Forbidden; no arbitrary shell execution |
| Unsafe shell execution | Broad process APIs are dangerous | Not implemented; avoid |
| Credential leakage | Provider keys can authorize paid requests and private account access | Hold unsaved keys only in memory; persist validated cloud keys only as Keychain generic-password items through `SecureStoring` |
| Cloud AI disclosure | Prompts, metadata, tool results, or contents can reveal private activity | Name the selected provider, minimize structured output, require exact content-share approval, and never send absolute paths or bookmarks |
| Prompt/tool injection | Model output or file text may try to acquire local authority | Treat all model/content text as untrusted data; accept only typed bounded tools and enforce capability checks locally |
| Clipboard exposure | Clipboard may contain passwords | Never log pasteboard contents; Clipboard History enrichment stays in memory, while explicit Shelf text/image imports use an owner-only per-board temporary directory that is deleted on cleanup |
| Shelf reference exposure | Dropped URLs and materialized clipboard content can disclose private names, paths, or contents | Keep external references in memory, confine owned content to a private temporary directory, hold security scope only while staged, never log payloads or paths, and perform sharing/mutation only after explicit user action |
| Unsafe URLs | OpenURL can be abused | Validate before opening |
| Path traversal | File APIs may escape intended roots | Validate and constrain paths |
| Excessive permissions | Hard to revoke trust | Least privilege; contextual prompts |
| Insecure updates | Tampered builds | Distribution design deferred |

## Hard rules

- Never directly execute user-entered shell strings.
- Validate URLs before opening.
- Validate file paths and keep access scoped.
- Store secrets in Keychain (via `SecureStoring`), never UserDefaults or source.
- Redact sensitive values in logs (`SensitiveValue`, logging policy).
- Never include credentials, prompts, provider bodies, tool arguments, filenames, paths, or file
  contents in logs, analytics, or crash breadcrumbs.
- Require an exact local confirmation for AI content disclosure and filesystem mutations.
- A model must never receive raw path authority, security-scoped bookmarks, AppleScript, process
  launch, a shell, or a general filesystem interface.
- Use least privilege entitlements.
- Do not request permissions at launch.

## AI credential and disclosure boundary

The optional BYOK system connects directly to the provider selected by the user. Commandly does not
operate a shared account or proxy. When the concealed field changes, Commandly removes that exact
value from its in-memory Clipboard History; it repeats the exclusion immediately before validation.
A newly entered cloud key otherwise remains in the AI settings model's memory until a non-generation
validation/model-discovery request succeeds and the user chooses a model. The saved key is a
generic-password Keychain item with device-only, when-unlocked
accessibility. Fixed `SecureStoreError` cases omit the key, logical account, raw Keychain status,
request, and response.

UserDefaults may store only versioned non-secret connection metadata: provider ID, model ID and
display name, a random connection revision, reviewed capability evidence, active provider, and an
explicit local endpoint. It must not contain a key, prompt, response, conversation, tool arguments,
filename, path, bookmark, file content, or provider error body. Initial conversations and opaque
provider continuation state are in memory only and are cleared when the Finder AI launcher session
ends. OpenAI inference remains stateless with `store: false`; bounded encrypted reasoning/function
items are replayed locally for a correlated tool chain rather than depending on a stored response.

Cloud inference can disclose the submitted prompt, system/tool instructions, bounded item display
metadata, and tool results to the selected provider under the user's account and terms. Automatic
search queries filenames only, applies authorized-root predicates before ranking and limiting, and
accepts a hit only after locally rescoring its filename. It returns opaque handles plus a locally
recomputed root-relative location and bounded metadata, never a snippet, hidden absolute-path match,
or file contents. Exact bounded file text may leave the Mac only
after a separate approval that names both the items and provider. Absolute paths, bookmarks, and
unapproved contents never leave the Mac. Ollama is restricted to an explicit loopback endpoint;
plaintext arbitrary remote endpoints are rejected.

## Finder AI capability boundary

Finder AI is built-in reviewed code, not externally loaded extension code. A conversation-scoped
workspace actor maps random opaque handles to resources under the current user-selected folder
scopes. Handles expire with the session. Before planning or executing work, the local boundary
revalidates authorization, canonical containment, resource identity, symlink/package behavior,
destination validity, collisions, names, counts, and size limits. Downloads access, uninstall
exceptions, Finder Automation, volume roots, the home root, authorization roots, and Commandly's own
data do not become AI mutation authority. Mutation sources that equal or contain a nested current
authorization root are rejected. Commandly-owned subtrees and directory/package ancestors that
contain them are also mutation-protected, even when the user authorized a broader parent folder.
Approved text reads use a no-follow descriptor and compare the opened regular file's identity before
and after the bounded read.

Bounded metadata queries may run after the user submits a prompt. Content reads and create, rename,
duplicate, copy, move, or Trash operations require an exact, expiring, single-use local approval
that cannot be represented in model JSON. A changed resource or plan invalidates approval. “Delete”
means Move to Trash; permanent deletion, emptying Trash, overwrite/merge, arbitrary sharing,
package/symlink traversal, permission changes, AppleScript, process launch, and shell execution are
not tools.

The initial provider runtime is non-streaming but remains cancellable. Cancellation can stop pending
provider/tool work; a filesystem operation already in progress may finish. Results distinguish
completed, failed, and cancelled items and never imply transactionality or rollback. Approved
batches are preflighted as a whole and the relevant safety checks run again immediately before each
action. If an approved mutation execution returns but cancellation, a limit, or a later tool failure
leaves the provider turn incomplete, Finder may already have changed; local activity remains visible
and the conversation must be cleared before it can continue. See `docs/AI.md` and ADR-0006.

## Shelf boundary

Shelf accepts concrete file and folder URLs after an explicit drop or paste and accepts an explicit
clipboard import of plain text or a standalone image. A staged external reference is not copied and
is not written to preferences, Application Support, or logs. Imported text/image bytes are
materialized beneath an owner-only, per-board directory in Commandly's temporary container so they
can use the same URL-based action pipeline. Owned files are deleted when their items leave Shelf,
and the directory is deleted when the board closes or is replaced.

Security-scoped access is released when an external reference leaves the board or the board closes.
Native sharing hands URLs to the service the user chooses; that service controls recipients,
sign-in, and network transfer. Copy, move, duplicate, rename, and Trash actions affect filesystem
items and must report sandbox, scope, conflict, and operation failures rather than implying success.

Shelf does not execute scripts or shell commands and does not hold cloud-provider credentials.
Promised files, rich-text preservation, arbitrary pasteboard representations, hosted links,
transformations, and background folder monitoring remain outside the implemented boundary.

See also `SECURITY.md` and `docs/PERMISSIONS.md`.
