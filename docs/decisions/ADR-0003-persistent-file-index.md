# ADR-0003: Persistent local file index

- Status: Accepted
- Date: 2026-07-12

## Context

File Search originally created an `NSMetadataQuery` for each search request. That made filename
availability depend on Spotlight state, repeated expensive gathering work while typing, produced
inconsistent partial batches, and exposed the UI to selector/notification lifecycle failures.
It also could not reliably search Finder tags, bounded on-device OCR, or content that Spotlight
had not indexed.

Raycast's published v2 architecture independently validates the product-level direction: its file
search moved from Spotlight metadata to a separate direct filesystem scanner, local index, and
filesystem-event updates. Apple's FSEvents guidance recommends pairing persistent events with a
directory-hierarchy snapshot when an app needs to know precisely what changed.

## Decision

Commandly owns a local, per-device file index for user-authorized folders:

- Direct `FileManager` enumeration builds a metadata snapshot off the main actor.
- SQLite in WAL mode stores file records; system SQLite FTS5 indexes normalized names, paths,
  Finder tags, metadata, and extracted contents. No third-party package is added.
- Core name/path metadata is committed in bounded batches and becomes searchable immediately.
- A second utility-priority phase performs bounded text/PDF extraction, optional Spotlight metadata
  enrichment, and on-device Vision OCR for images.
- FSEvents file-level streams refresh changed paths after the initial scan. Large event bursts trigger
  a reconciliatory scan.
- Schema versions are disposable. Corruption or an incompatible schema deletes only Commandly's
  derived index and rebuilds it from authorized source folders.
- The index is local, is never synced or logged, and removes records outside the current authorized
  scope set before serving queries.

## Consequences

- Warm filename, path, tag, metadata, and enriched-content searches do not start Spotlight queries.
- The first scan consumes disk I/O and may take time for very large scopes; names appear before
  optional content enrichment finishes.
- Content coverage is bounded. Unsupported binary formats may still contribute Spotlight-provided
  metadata/text when available, but Commandly does not claim readable content for every binary format.
- The security-scoped folder grant remains active while the in-process index monitor is running after
  the user first opens File Search. This avoids an always-on launch scan while keeping subsequent
  searches and filesystem changes fast.
- Index storage grows with the number and textual contents of authorized files. Extraction caps and
  ignored noise directories bound this cost.

## Rejected alternatives

- A fresh `NSMetadataQuery` per keystroke: inconsistent and too slow for the critical filename path.
- A Codable in-memory snapshot: high launch memory and rewrite amplification for large home folders.
- A third-party SQLite wrapper: unnecessary for the small actor-confined database surface and contrary
  to the current zero-third-party-dependency policy.
- Scanning file contents while typing: unbounded latency, privacy risk, and cancellation complexity.
