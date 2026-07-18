# Performance

These are **future targets**, not measured results. Do not claim they are met until benchmarks exist.

| Metric | Initial target | Notes |
|--------|----------------|-------|
| Cold launch to interactive UI | < 400 ms on reference Apple silicon | Full app shell exists; end-to-end launch is not benchmarked |
| Warm launcher open | < 50 ms | Implemented; not benchmarked |
| Warm Command Wheel activation | < 50 ms shortcut event to visible panel on reference Apple silicon | Implemented; not benchmarked |
| Command Wheel selection feedback | < 16 ms from sampled pointer/key input to model update | 120 Hz pointer sampling is configured; end-to-end feedback is not benchmarked |
| Keyboard response | < 16 ms input-to-feedback | Keyboard-first launcher exists; not benchmarked |
| Search result first paint | < 50 ms for local providers | Local providers ship; only the File Search measurements below are recorded |
| Memory while idle | < 80 MB resident | Not measured |
| CPU while idle | ~0% after settling | Not measured; clipboard monitoring, auto-quit, and active timers have bounded background work |
| Search cancellation | Cancel in-flight work immediately on query change | Required by SearchKit design |

## Engineering guidance

- Keep startup free of permission prompts, network, and heavy I/O.
- Prefer incremental search with cancellation.
- Measure before optimizing; record methodology when adding benchmarks.

## Command Wheel performance contract

The wheel's activation path uses a cached validated configuration and immutable display/profile
snapshots. Opening and pointer tracking must not synchronously read profile JSON, persist settings,
enumerate the command catalog, decode artwork, enumerate screens every frame, or execute a command.
Recent/frequent providers are bounded and frozen for the active session. Geometry and hit testing
operate on value snapshots, and SwiftUI observes a focused presentation model rather than the full
registry or Settings graph. Provider preparation scans at most 96 ranked history candidates per
provider and deduplicates repeated command-reference resolutions within the invocation. Native
application artwork is fully rasterized off the main actor and stored in a 128-entry LRU cache with
time-bounded success and failure entries.

Profile, catalog, permission, and display changes invalidate the relevant cached snapshot between
sessions. Dismissal must release pointer timers, toggle-only event monitors, dwell work, provider
tasks, and panel/session references. The implementation is not considered performance-validated
until activation/selection measurements and repeated open-dismiss leak checks are entered in the
[Command Wheel testing record](COMMAND_WHEEL_TESTING.md#execution-record-for-this-implementation).

## File Search measurements

### Persistent index (current)

Measured on July 12, 2026 on the development Apple-silicon Mac through the Commandly unit-test
target. The synthetic test inserts 10,000 file records into a fresh WAL/FTS5 database and then
searches a multi-token underscore-separated filename near the end of the data set.

| Measurement | Result |
|-------------|--------|
| Fresh 10,000-record index build plus one selective query | 268 ms total test duration |
| Selective 10,000-record FTS query | Under 250 ms (enforced assertion; build time is excluded) |
| Direct scan + content extraction + changed-file refresh in a temporary tree | 20 ms total test duration |
| FSEvents file-level delivery in a temporary tree | 41 ms total test duration |

The opt-in `CommandlyUIValidation` scheme also verifies a cold sandbox-local scan through rendered
SwiftUI, CSV preview population, right-click actions, and a second warm content query. It is an
interaction regression test rather than a latency benchmark because XCTest window/menu setup adds
several seconds unrelated to the search engine.

The 10,000-record assertion is intentionally conservative for shared CI. On-device profiling of a
fully authorized Home-folder index is still required before claiming a whole-disk scan time or a
universal warm-query percentile. The engine publishes each 400-record name/metadata batch, so useful
results do not wait for the full scan or OCR/content enrichment.

### Spotlight prototype (historical, replaced)

These earlier measurements are retained only to document why the prototype was replaced. They are
system Spotlight control-query timings, not current end-to-end UI guarantees. The selected search
root was the user's home folder.

| Search | First usable result batch |
|--------|---------------------------|
| Empty recent-files query | 112 ms, 18 results |
| Exact Desktop CSV filename | 333 ms, 2 results |
| Multi-token screenshot filename | 85 ms, 1 image |
| Folder name | 89 ms, 20 results including 2 folders |
| Indexed file contents | 146 ms, 8 content matches |

The former `NSMetadataQuery` adapter and its per-keystroke gathering lifecycle no longer ship.
