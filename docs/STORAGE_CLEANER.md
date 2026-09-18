# Storage Cleaner

## User behavior

Storage Cleaner is a registered launcher application with three reviewable categories:

- **App Leftovers** scans direct children of reviewed current-user Library locations and lists
  reverse-domain identifier names that do not match an installed application or helper prefix.
- **Caches** lists third-party top-level entries under `~/Library/Caches`. Caches are never
  preselected because an installed or running app may recreate or actively use them.
- **Exact Duplicates** asks the user to choose one folder, groups regular files by size, and then
  confirms byte-for-byte identity with an incremental SHA-256 hash. All but the most recently
  modified copy are initially selected, and changing selection can never leave a group with every
  copy selected.

The user can filter, inspect parent paths and sizes, change every recommendation, and review a final
item count and byte total. Confirmed items move to the macOS Trash. Storage Cleaner never deletes
automatically, permanently deletes an item, or empties the Trash.

## Architecture

- `Infrastructure` owns `StorageCleanupItem`, `StorageCleanupScanResult`,
  `StorageCleanupScanning`, and `StorageCleanupDirectoryChoosing` plus in-memory test adapters.
- `WorkspaceStorageCleanupScanner` is an actor-confined native adapter. It performs filesystem
  enumeration, bounded size calculation, installed-bundle matching, and incremental content
  hashing away from the main actor.
- `WorkspaceStorageCleanupDirectoryChooser` owns the native `NSOpenPanel` used for one ephemeral
  duplicate scope.
- `StorageCleanerViewModel` is main-actor UI state. It owns cancellation, stale-scan rejection,
  category/query filtering, recommendations, the one-copy duplicate invariant, destructive
  confirmation, and partial-failure reporting.
- `StorageCleanerApplication` registers the command and injects the scanner, picker, and existing
  `ApplicationBundleManaging` Trash boundary from the composition root.

## Bounds and matching

Library discovery is intentionally conservative:

- It scans direct children of Application Support, Preferences, HTTPStorages, Cookies, WebKit,
  Containers, Saved Application State, LaunchAgents, Logs, and Application Scripts in the real
  current-user Library.
- It recognizes names with at least three reverse-domain components after known suffixes such as
  `.plist`, `.savedState`, and `.binarycookies` are removed.
- It excludes Apple identifiers, Commandly data, shared group containers, ambiguous human-named
  folders, hidden entries, and symbolic links.
- An identifier is treated as represented when it equals, extends, or is a parent prefix of an
  installed application bundle identifier. This protects common helper naming patterns.
- The scan stops after 600 candidates or 100,000 inspected files and reports a partial result.

Duplicate discovery skips hidden files, package descendants, symbolic links, empty files, and
unreadable items. It inspects at most 25,000 regular files and hashes at most 10 GiB of candidate
content per scan. Size is only a prefilter; files appear as duplicates only when their SHA-256
digests also match.

Identifier matching is evidence, not proof of ownership. A helper or command-line component may have
no visible `.app`, and ambiguous app-name folders are intentionally missed. The UI and documentation
therefore require path review and never claim a complete disk sweep.

## Privacy and permissions

The Library scan begins only when the user opens Storage Cleaner or explicitly refreshes it. It
reuses the existing temporary home-relative read-write exception that application uninstall already
requires for the real user Library. No new TCC prompt is introduced.

Duplicate access uses `com.apple.security.files.user-selected.read-write` for the folder chosen in
the native panel. Storage Cleaner does not persist a security-scoped bookmark for this ephemeral
scope. Paths, filenames, bundle identifiers, sizes, hashes, scan results, and selections remain in
memory, are not logged, and are not uploaded.

Trash operations happen only after an exact local confirmation. Failures are reported per batch;
the workflow does not claim transactionality or rollback, because earlier items may already have
moved to Trash when a later item fails or cancellation occurs.

## Accessibility

- Category rows expose selected state, candidate count, and total size without relying on color.
- Candidate rows expose name, category, parent path, size, focus, and cleanup-selection state.
- Duplicate rows say **Keep** or **Remove** in text in addition to their symbol and color.
- Up/Down changes focus, Return toggles the focused candidate, Command-Return opens the destructive
  review, Command-K exposes rescanning and selection actions, and Escape cancels/clears/goes back.
- Loading, empty, partial, failure, and completed states use text plus symbols.

Manual release review must still cover VoiceOver reading order, Full Keyboard Access, larger text,
Increased Contrast, Reduce Transparency, a large partial scan, permission-denied Trash operations,
and changing the kept file in a duplicate group.

## Testing

Automated tests use isolated temporary directories and injected in-memory adapters. They cover:

- installed-bundle/helper prefix protection;
- Apple and Commandly exclusion;
- conservative app-leftover and cache categorization;
- exact duplicate hashing and one recommended kept copy;
- registered application/session composition;
- cache opt-in selection and recommended leftover selection;
- changing which duplicate copy is kept; and
- confirmed Trash routing without touching real user files.
