# File Search

## User behavior

`Search Files` is a registered launcher view command. It provides:

- A keyboard-focused query field with cancellable, debounced local-index search
- Token-based filename matching so ordinary spaces match macOS filename separators such as
  underscores, dashes, and narrow non-breaking spaces
- Filename, path, folder, Finder-tag, metadata, and enriched file-content matching
- An empty-query `Recent Files` view based on Spotlight last-used metadata
- Filters for all files, folders, documents, images, audio, video, archives, and source code
- Keyboard selection, Return to open, and Command-K actions
- Instant native table previews for CSV files, cancellable static Quick Look representations for
  other supported formats,
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
- `PersistentFileSearchService` owns session scope resolution, corruption recovery, status updates,
  and FSEvents monitoring. It never creates a Spotlight query while the user types.
- `FileIndexScanner` enumerates authorized folders directly and commits bounded metadata batches.
  Hidden files, packages' descendants, temporary files, and common dependency/build noise are skipped.
- `FileIndexDatabase` owns one actor-confined SQLite connection in WAL mode. FTS5 external-content
  triggers index normalized names, paths, Finder tags, metadata, and extracted contents.
- `FileContentExtractor` runs after the core scan and caps all work. It reads supported text and PDFs,
  uses Spotlight metadata only as optional enrichment, and applies on-device Vision OCR to bounded images.
- `FileSearchViewModel` owns UI state, cancellation, stale-result rejection,
  selection, nested action-card navigation, index-progress observation, and actions on the main actor.
  Native filesystem behavior is injected through `FileActionServicing`. One FTS snapshot query covers
  all enabled fields atomically; filename matches rank above tags, metadata, and content.
- `FileSearchView` owns focus and presentation only.
- `CSVPreviewLoader` performs bounded, cancellable off-main file reads and RFC-style parsing;
  `CSVFilePreview` renders the snapshot without waiting for a Quick Look generator.
- `QuickLookSnapshotPreview` requests immutable, cancellable thumbnail representations. It does not
  embed or mutate `QLPreviewView`, avoiding that view's private KVO and scrolling lifecycle inside a
  rapidly changing launcher selection.
- `AppRuntime` assembles the real Spotlight service. Tests inject
  `InMemoryFileSearchService` and never query real user files.

## Privacy and permissions

Commandly remains sandboxed. Search is limited to folders the user explicitly chooses
through the existing Files and Folders permission flow. Security-scoped bookmark access
is activated when File Search is first used. It remains active while the in-process FSEvents monitor
keeps the local index current, and is released when the process exits or scopes change. Selected-folder access is read-write because copy,
move, duplicate, shortcut, and Trash operations require it; those operations occur only after
an explicit action from the user.

Search queries, result paths, filenames, indexed contents, previews, and metadata are
never logged or uploaded. The derived SQLite index stays in Commandly's Application Support
directory and is never synced. Commandly does not open and scan files while the user types.

## Product research and trade-offs

Raycast's public v2 technical description informed the architecture category: a direct filesystem
scanner, local index, background process isolation, and filesystem-event updates replaced its earlier
Spotlight-dependent search. Commandly independently implements the same general systems pattern with
native Swift actors, system SQLite, and FSEvents; it does not copy Raycast source, assets, branding,
or layout.

Current limitations:

- Protected locations and folders the user did not select are not searchable.
- Hidden files are excluded in this release.
- Unsupported or encrypted binary formats may expose metadata but no readable contents.
- Image OCR is bounded by file size and runs after names and metadata are already searchable.
- External volumes must be selected explicitly and be mounted.

## Research sources

- Raycast File Search manual: <https://manual.raycast.com/file-search>
- Raycast v2 technical deep dive: <https://www.raycast.com/blog/a-technical-deep-dive-into-the-new-raycast>
- Apple `NSMetadataQuery`: <https://developer.apple.com/documentation/foundation/nsmetadataquery>
- Apple FSEvents programming guide: <https://developer.apple.com/library/archive/documentation/Darwin/Conceptual/FSEvents_ProgGuide/UsingtheFSEventsFramework/UsingtheFSEventsFramework.html>
- Apple macOS sandbox file access: <https://developer.apple.com/documentation/security/accessing-files-from-the-macos-app-sandbox>
- Apple `QLThumbnailGenerator`: <https://developer.apple.com/documentation/quicklookthumbnailing/qlthumbnailgenerator>
