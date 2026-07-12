# File Search

## User behavior

`Search Files` is a registered launcher view command. It provides:

- A keyboard-focused query field with cancellable, debounced, progressively delivered search
- Token-based filename matching so ordinary spaces match macOS filename separators such as
  underscores, dashes, and narrow non-breaking spaces
- Filename, folder-name, and Spotlight-indexed file-content matching
- An empty-query `Recent Files` view based on Spotlight last-used metadata
- Filters for all files, folders, documents, images, audio, video, archives, and source code
- Keyboard selection, Return to open, and Command-K actions
- Instant native table previews for CSV files, Quick Look for other supported formats,
  and file metadata
- A reusable searchable actions card on secondary-click or Command-K, with nested Open With,
  macOS sharing, and destination-folder pages
- Open, Finder info/reveal/enclosing-folder, detail toggle, share, move, copy, duplicate,
  Commandly shortcut, clipboard, and Trash actions

The layout follows Commandly's existing command-surface pattern (search/filter header,
result list, preview/metadata detail, and shared footer) and uses DesignSystem tokens.
It is intentionally original rather than a copy of another launcher's UI.

## Architecture

- `SearchKit` owns `FileSearchRequest`, `FileSearchItem`, filter categories, errors,
  and the `FileSearching` contract.
- `SpotlightFileSearchService` is the macOS adapter. It consumes Spotlight gathering-progress
  notifications only after a batch contains an authorized result with a usable path, preventing
  an incomplete metadata batch from being rendered as an empty result set.
- `FileSearchViewModel` owns UI state, cancellation, stale-result rejection,
  selection, nested action-card navigation, and actions on the main actor. Native filesystem
  behavior is injected through `FileActionServicing`. Typed searches run a fast filename/folder pass first
  and enrich it with indexed-content matches afterward; filename hits always stay ahead of
  content-only hits. The lanes use distinct predicates, so content enrichment never repeats the
  filename query.
- `FileSearchView` owns focus and presentation only.
- `CSVPreviewLoader` performs bounded, cancellable off-main file reads and RFC-style parsing;
  `CSVFilePreview` renders the snapshot without waiting for a Quick Look generator.
- `AppRuntime` assembles the real Spotlight service. Tests inject
  `InMemoryFileSearchService` and never query real user files.

## Privacy and permissions

Commandly remains sandboxed. Search is limited to folders the user explicitly chooses
through the existing Files and Folders permission flow. Security-scoped bookmark access
is active only while the file-search surface is alive so Spotlight results, previews,
and actions share the same authorized scope. Selected-folder access is read-write because copy,
move, duplicate, shortcut, and Trash operations require it; those operations occur only after
an explicit action from the user.

Search queries, result paths, filenames, indexed contents, previews, and metadata are
never logged or uploaded. File-content matching uses the on-device Spotlight index;
Commandly does not open and scan every file while the user types.

## Product research and trade-offs

Raycast's documented interaction model informed the useful category-level behaviors:
inline filename search, a richer dedicated list/detail command, recent files, content
search, configurable scopes, and file actions. Raycast v2 documents a custom filesystem
index for names and paths, while its manual says content search uses the operating system
index. Commandly does not copy that implementation or visual layout; on macOS it consumes
Spotlight incrementally and separates the fast name lane from content enrichment.

Commandly uses Spotlight for filename and indexed-content search. Requiring a usable partial batch
keeps the normal interaction lightweight and avoids both premature empty results and a bundled
background crawler, but it has honest limitations:

- Results depend on Spotlight being enabled and having indexed an authorized folder.
- Protected locations and folders the user did not select are not searchable.
- Hidden files are excluded in this release.
- Image OCR is available only when Spotlight has indexed text for that image; Commandly
  does not yet maintain a separate screenshot OCR index.
- External volumes must be selected explicitly and be mounted.

A future custom index would require a separate ADR covering persistence, event watching,
ignore rules, disk-space safeguards, privacy, memory, and measured performance before it
replaces or supplements Spotlight.

## Research sources

- Raycast File Search manual: <https://manual.raycast.com/file-search>
- Raycast v2 technical deep dive: <https://www.raycast.com/blog/a-technical-deep-dive-into-the-new-raycast>
- Apple `NSMetadataQuery`: <https://developer.apple.com/documentation/foundation/nsmetadataquery>
- Apple macOS sandbox file access: <https://developer.apple.com/documentation/security/accessing-files-from-the-macos-app-sandbox>
- Apple `QLPreviewView`: <https://developer.apple.com/documentation/quicklookui/qlpreviewview>
