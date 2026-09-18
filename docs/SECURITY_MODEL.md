# Security Model

## Future risk areas

| Risk | Why it matters | Foundation stance |
|------|----------------|-------------------|
| Malicious extensions | Third-party code can steal data or crash the app | No loading yet; manifests only |
| Command injection | User text interpolated into shells | Forbidden; typed launcher parsers may produce only validated `CommandReference` values for registered tools |
| Unsafe shell execution | Broad process APIs are dangerous | Not implemented; avoid |
| Credential leakage | Provider keys can authorize paid requests and private account access | Hold unsaved keys only in memory; persist validated cloud keys only as Keychain generic-password items through `SecureStoring` |
| Cloud AI disclosure | Prompts, metadata, tool results, or contents can reveal private activity | Name the selected provider, minimize structured output, require exact content-share approval, and never send absolute paths or bookmarks |
| Prompt/tool injection | Model output or file text may try to acquire local authority | Treat all model/content text as untrusted data; accept only typed bounded tools and enforce capability checks locally |
| Clipboard exposure | Clipboard may contain passwords | Never log pasteboard contents; Clipboard History enrichment stays in memory, while explicit Shelf text/image imports use an owner-only per-board temporary directory that is deleted on cleanup |
| Window activity exposure | A future window switcher could expose titles, thumbnails, documents, accounts, conversations, browsing activity, and global input | Keep the sandbox-incompatible Window Switcher runtime unregistered and disabled. Retain only foundation contracts/prototypes/tests; require a new threat model and distribution decision before any privileged helper/runtime, and keep all future window/query/image/input state ephemeral |
| Local image disclosure | Selected photos may contain private people, places, or metadata | Background Remover processes only explicitly picked or dropped images with Apple Vision on device, retains bounded previews and output in memory for the active session, never logs or uploads image data, and exports only after an explicit save action |
| Shelf reference exposure | Dropped URLs and materialized clipboard content can disclose private names, paths, or contents | Keep external references in memory, confine owned content to a private temporary directory, hold security scope only while staged, never log payloads or paths, and perform sharing/mutation only after explicit user action |
| Unsafe cleanup classification | A stale app helper, active cache, or important duplicate path could be mistaken for disposable data | Keep Library matching conservative and bounded, leave caches unchecked, preserve one exact duplicate, expose paths/sizes/categories, require local confirmation, move to Trash only, and report partial results |
| Unsafe URLs | OpenURL can be abused | Validate before opening |
| Remote SVG content | Public catalog assets can change outside Commandly | Accept catalog assets only from fixed HTTPS SVGL hosts, bound response sizes, disable preview JavaScript, and fetch only after the user opens Logos |
| Malicious Markdown | Documents can contain scripts, remote resources, traversal links, oversized images, or parser stress cases | Escape raw HTML, render with a strict CSP in a nonpersistent web view, block implicit network loads, bound source/images, and open only validated user-activated links |
| Path traversal | File APIs may escape intended roots | Validate and constrain paths |
| Excessive permissions | Hard to revoke trust | Least privilege; contextual prompts |
| Insecure updates | Tampered builds | Distribution design deferred |

## Hard rules

- Never directly execute user-entered shell strings.
- Application-owned typed commands must target one declared tool, encode arguments with CommandKit
  value types, and reuse that tool's permission, confirmation, revalidation, and execution path.
- Validate URLs before opening.
- Restrict Logos catalog requests to `api.svgl.app` and SVG asset requests to HTTPS `svgl.app` URLs.
- Validate file paths and keep access scoped.
- Store secrets in Keychain (via `SecureStoring`), never UserDefaults or source.
- Redact sensitive values in logs (`SensitiveValue`, logging policy).
- Never include credentials, prompts, provider bodies, tool arguments, filenames, paths, or file
  contents in logs, analytics, or crash breadcrumbs.
- Never persist or log Storage Cleaner paths, filenames, bundle identifiers, hashes, scan results,
  selected duplicate scopes, or cleanup selections.
- Require an exact local confirmation for AI content disclosure and filesystem mutations.
- A model must never receive raw path authority, security-scoped bookmarks, AppleScript, process
  launch, a shell, or a general filesystem interface.
- Use least privilege entitlements.
- Do not request permissions at launch.
- Do not use private `CoreDock`, `SkyLight`, `MediaRemote`, WindowServer, Spaces, or visual-effect APIs.

## Launcher tools and inline local discovery boundary

Application tools are reviewed first-party entry points, not a plug-in or general automation
surface. A parsed launcher phrase creates a typed reference to one tool owned by the same registered
application. It cannot acquire a separate shortcut, call a process API by itself, or bypass the
tool's runtime checks. The Port Manager phrase `kill port <number>` only seeds the existing local
review flow; graceful termination still requires an explicit confirmation and revalidation of the
selected listener and owning process.

Root Clipboard History matching uses only stored capture-time previews, text, source application,
classification labels, and already-enriched searchable text; it does not reread the live pasteboard
or rerun OCR while typing. Root File Search uses only the existing authorized local index. Private
clipboard rows and file rows are excluded from autocomplete and shared command history. Their query,
value, filename, path, content, and result metadata remain subject to the existing no-log/no-upload
rules.

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

## Storage Cleaner boundary

Storage Cleaner is an explicit local maintenance surface, not a background daemon. Opening it starts
a bounded scan of reviewed real-user Library locations through the same temporary home-relative
exception already disclosed for application uninstall. Leftover classification accepts only
reverse-domain identifier names, protects installed bundle/helper prefix relationships, and excludes
Apple identifiers, Commandly, shared group containers, hidden entries, symbolic links, and ambiguous
human names. This deliberately produces false negatives. Identifier absence still cannot prove that
a helper is unused, so every result exposes its category, parent path, and size for review.

Third-party cache roots remain unchecked by default. Duplicate discovery obtains one ephemeral
user-selected folder, skips hidden files, packages, symbolic links, unreadable items, and empty
files, then uses file size only as a prefilter before incremental SHA-256 comparison. Selection
logic must keep at least one file in every exact-match group. The folder grant, paths, names, bundle
identifiers, metadata, hashes, results, and selection state remain memory-only and must not enter
logs, analytics, crash breadcrumbs, preferences, File Search's index, command history, or a network
request.

No scan mutates the filesystem. The user must request Review Cleanup and approve an exact local
count and byte total before the existing native adapter moves only selected paths to Trash. There is
no permanent deletion, Trash emptying, overwrite, helper/process termination, shell, AppleScript, or
privileged escalation. Cancellation and partial failure are not transactional: earlier items may
already be in Trash, and the result must say so without claiming rollback or a complete disk sweep.
See `docs/STORAGE_CLEANER.md`.

## Window Switcher boundary

Window Switcher is foundation/prototype work, not an active sandboxed runtime. Apple's
[App Sandbox guidance](https://developer.apple.com/documentation/security/protecting-user-data-with-app-sandbox)
lists assistive Accessibility API use and terminating other running apps as incompatible activities.
Because the prototype enumerates/controls other applications' windows and models graceful Quit,
production Commandly must not register it, start its Accessibility/Dock adapters, install its active
event tap, or request Screen Recording for thumbnails.

The prototype event tap receives the subscribed global key-event stream and filters unrelated events
immediately; the OS does not deliver only the configured gesture. Apple's
[`CGEventTapOptions` documentation](https://developer.apple.com/documentation/coregraphics/cgeventtapoptions)
distinguishes passive listeners from active filters that can discard events. A sandbox-compatible
listen-only monitor would require Input Monitoring and could not suppress Option-Tab or replace
Command-Tab. Active cross-app suppression is not an established sandbox boundary.

The privacy model remains a requirement for any future authorized runtime. Every value obtained from
another application's Accessibility tree or screen content is private. Window titles, application/
window ordering, minimized and full-screen state, thumbnails, queries, pointer positions, and input
state must exist only in the active session; they must not enter UserDefaults, Application Support,
command history, logs, analytics, crash breadcrumbs, or network requests. Screen Recording must
remain a separate optional thumbnail grant with size-bounded memory-only captures and immediate
revocation cleanup. Applications can omit or reject Accessibility attributes/actions, so failures
must remain explicit rather than assumed success.

Current-Space filtering and Dock/Command-Tab behavior would remain best-effort interpretations of
documented public information even outside the sandbox. Commandly does not use `CoreDock`,
`SkyLight`, `MediaRemote`, private Core Graphics Services symbols, private blur/material APIs,
AppleScript, or shell execution for this feature. It also does not copy GPL-licensed source, assets,
symbols, copy, or UI from the supplied reference project.

A separately signed non-sandboxed companion/helper or a direct-distribution build with App Sandbox
disabled requires a new accepted architecture, threat-model, signing, update, IPC, permission, and
distribution decision. See [Window Switcher](WINDOW_SWITCHER.md) and rejected
[ADR-0008](decisions/ADR-0008-window-switcher-public-api-boundary.md).

## Markdown Preview and Quick Look boundary

Markdown Preview treats every selected document, relative image, search query, link, outline entry,
and rendered page as private untrusted input. The host reads only a file chosen or dropped by the
user. The Quick Look extension reads only the URL Finder supplies for that preview. Neither surface
scans surrounding folders, uploads content, logs paths or text, executes document code, or grants a
document shell, process, clipboard, AI, or arbitrary filesystem authority.

The shared renderer escapes raw HTML and creates the complete page itself. Its Content Security
Policy blocks remote resources, frames, forms, objects, workers, and network connections; only a
renderer-owned nonce script may expose bounded search, source, zoom, and anchor hooks. Both surfaces
use a nonpersistent `WKWebsiteDataStore`. User-activated web and email links leave the page through
the reviewed URL-opening boundary, while relative Markdown links must remain beneath the active
document directory and use a supported extension.

Local images are optional and fail closed. Only PNG, JPEG, GIF, and WebP files reached through
descriptor-relative, no-follow traversal beneath the document directory may be inlined. Reads
revalidate stable file identity and size before and after access. Limits are 32 images, 2 MiB per
image, 8 MiB total, 16,384 pixels per dimension, 64 million pixels per frame, 256 frames, 128 million
decoded pixels per image, and 256 million decoded pixels per document. The host source limit is
8 MiB. Quick Look reads at most 500 KiB of source and adds a visible truncation notice at a line
boundary. Invalid encodings and binary-looking input are reported rather than lossy-decoded as
executable markup.

The App Group contains only the versioned, non-secret renderer configuration needed to keep the host
and Quick Look appearance consistent. It never contains file URLs, bookmarks, content, queries,
scroll state, recent documents, or exports. Host scroll memory is digest-keyed in the host defaults
domain and bounded. See [Markdown Preview](MARKDOWN_PREVIEW.md) and
[ADR-0009](decisions/ADR-0009-markdown-preview-quick-look-boundary.md).

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
