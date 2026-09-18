# File Browser

File Browser (`files.browser`) is a native launcher application, separate from indexed File Search.
Its Browse Authorized Folders tool (`files.browser.open`) presents the user's existing folder
grants. Return enters a selected folder inside Commandly. Typing filters the current snapshot by
name without any additional disk I/O. Return on a file or package explicitly opens it with macOS.

Command-Up navigates to the parent directory. At the selected root it returns to the authorized
folder list, so navigation never climbs above that root. Escape clears a filter, goes up a folder,
then returns to launcher search. The header Back button returns directly to launcher search.
Command-R refreshes the current directory; returning to a parent preserves the child selection.

## Architecture and lifecycle

`Infrastructure/FileBrowsing.swift` defines opaque root identities, relative locations, one-level
metadata snapshots, typed failures, and the `FileBrowsing` protocol. Absolute paths and file contents are
not part of the public row metadata. `AuthorizedFileBrowserService` is an app-owned actor using
the existing `FolderAccessStoring` dependency and an injectable bookmark/scope resolver.

Each operation resolves the current bookmarks without presenting UI, rejects stale grants, starts
security-scoped access, and balances it on success, cancellation, and failure. Listing and opening
recheck the current grant before completing. Missing authorization offers an explicit route to
Settings → Permissions; expired or unavailable grants, disconnected folders, changed files, and
unsafe paths have distinct user-facing errors. No permission prompt occurs merely by opening the
browser.

Directory work runs off the main actor. One request examines at most 5,000 directory entries and
returns at most 1,000 non-hidden immediate children, sorted with folders first. It reads only names
and bounded metadata, does not recurse, does not read file contents, and does not mutate files.
Cancellation is checked between entries and directory components. A visible truncation notice
explains that name filtering applies to the displayed portion of an oversized directory.

The view model cancels navigation and open tasks when their intent changes, rejects late results
with request identities, coalesces duplicate opens, and clears its displayed snapshot on stop.
The native UI uses shared launcher search, rows, metadata, focus restoration, and keyboard controls.
Selection-specific detail identity prevents reused accessibility content from describing a previous
selection. Labels communicate file/folder/link kinds independently of icons or color.

## Filesystem boundary

- The root comes only from a current folder grant. Untrusted relative locations cannot contain
  traversal, hidden components, separators, NUL, empty components, or more than 64 components.
- Directory descent uses `openat` with `O_DIRECTORY | O_NOFOLLOW`; entries use
  `fstatat(..., AT_SYMLINK_NOFOLLOW)`. Symbolic links are visible as unavailable rows and cannot be
  traversed or opened. Finder aliases remain unavailable, and package descendants are not browsed.
- File opening reacquires the grant, traverses the parent without following links, and compares a
  no-follow file descriptor's device/inode identity to the selected snapshot. A swapped or missing
  item must be refreshed before it can be opened.
- The opener receives an ephemeral file-reference URL after its identity is checked against that
  descriptor. This preserves the selected filesystem object if its pathname changes before macOS
  consumes the URL. It is never persisted; see Apple's
  [file-reference URL documentation](https://developer.apple.com/documentation/foundation/nsurl/filereferenceurl%28%29).

Opening holds the security scope through the injected opener's completion. File Browser does not
upload, log, index, cache to disk, or include its locations in command history. Existing folder
permissions remain the only filesystem authority; no entitlements or dependencies are added.

## Validation and debug fixture

`FileBrowserServiceTests` uses uniquely named temporary directories and a fake bookmark/scope
resolver to cover one-level enumeration, hidden files, symlink/traversal rejection, missing folders,
bounded results, selected-path replacement, revoked/stale grants, cancellation, and balanced scope
cleanup. The fake resolver never requests a real permission. `FileBrowserModelTests` uses suspended
continuations to cover nested keyboard navigation, local filtering, parent limits, cancellation,
late result rejection, stopping, duplicate opens, and explicit Settings recovery.

`FileBrowserDebugFixture` exists only in DEBUG builds. It serves fictional Design Workspace and
Shared Samples directories entirely from memory. Its Open action records a fixture selection but
never calls a system opener or reads a real file. An optional `FileBrowsing` override on
`FileBrowserApplication` permits explicit runtime fixture injection without changing production
authorization. `FileBrowserDebugFixtureTests` verifies nested browsing and the no-op open boundary.

Model/service tests verify their contracts; native rendering, VoiceOver, keyboard shortcuts, and
real signed sandbox grants require separate runtime validation. Network volumes can pause inside
an individual operating-system metadata call; the UI actor remains free, and cancellation takes
effect when that call returns. Live changes require Refresh rather than a background watcher.
