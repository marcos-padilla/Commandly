# Performance

These are **future targets** unless a dated measurement is recorded below. Do not claim an unmeasured
target is met.

| Metric | Initial target | Notes |
|--------|----------------|-------|
| Cold launch to interactive UI | < 400 ms on reference Apple silicon | Full app shell exists; end-to-end launch is not benchmarked |
| Warm launcher open | < 50 ms | Implemented; not benchmarked |
| Warm Command Wheel activation | < 50 ms shortcut event to visible panel on reference Apple silicon | Implemented; not benchmarked |
| Command Wheel selection feedback | < 16 ms from sampled pointer/key input to model update | 120 Hz pointer sampling is configured; end-to-end feedback is not benchmarked |
| Future Window Switcher warm activation | < 100 ms to a useful title/icon presentation on reference Apple silicon | Prototype target only; production runtime is unregistered/disabled and cannot be benchmarked as a feature |
| Future Window Switcher selection feedback | < 16 ms against the current immutable snapshot | Prototype target only; thumbnail/cycling integration is not production-validated |
| Warm Markdown Preview render | < 100 ms for a typical text-only document on reference Apple silicon | Implemented with bounded local parsing; not benchmarked |
| Finder Quick Look first preview | < 250 ms for a typical text-only document on reference Apple silicon | Extension and 500 KiB source bound implemented; signed Finder lifecycle not benchmarked |
| Keyboard response | < 16 ms input-to-feedback | Keyboard-first launcher exists; not benchmarked |
| Search result first paint | < 50 ms for local providers | Local providers ship; only the File Search measurements below are recorded |
| Inline root file section | Follow the 80 ms debounce with a bounded local-index query | Implemented with a 10-result cap; end-to-end root latency is not benchmarked |
| Memory while idle | < 80 MB resident | Not measured |
| CPU while idle | ~0% after settling | One signed Debug regression measurement is recorded below; a Release benchmark is still required |
| Search cancellation | Cancel in-flight work immediately on query change | Required by SearchKit design |

## Engineering guidance

- Keep startup free of permission prompts, network, and heavy I/O.
- Prefer incremental search with cancellation.
- Measure before optimizing; record methodology when adding benchmarks.

## Inline root-search performance contract

Clipboard matching reads the bounded in-memory history and returns at most six rows; it must not
rerun capture-time OCR, PDF extraction, or file enrichment. Inline File Search waits 80 ms, returns
at most ten rows from the existing SQLite index, and must not start a per-keystroke filesystem scan.
The root query task cancels both the debounce and index request when superseded, and late results must
not replace a different query.

Index scanning, content enrichment, FSEvents monitoring, and event processing are also scoped to an
active launcher/File Search session. Dismissal stops observation, cancels outstanding workers,
coalesces and drains queued paths, and releases security-scoped access. A later session resumes from
the persisted SQLite index rather than keeping a background crawler alive while Commandly is unused.

The current implementation publishes calculator, command/application, typed-command, and clipboard
rows first, then merges the debounced file child only when the query is still current. No end-to-end
first-paint, rapid-typing cancellation, file-merge, or large-clipboard-history measurement has been
recorded, so the general search target above is not yet claimed for this combined path.

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

## Window Switcher prototype performance contract

These are conditional acceptance targets, not current product measurements. The sandboxed production
runtime remains unregistered and disabled because its required cross-application Accessibility and
termination behavior is incompatible with Commandly's App Sandbox boundary. Measure this section
only after a new ADR authorizes a separately signed non-sandboxed helper or a non-sandboxed direct-
distribution build, and record the exact artifact signature, entitlements, and topology.

The first presentation prioritizes an immutable textual snapshot: application icon, title when
available, state, and supported actions. Accessibility enumeration, refresh observation, and optional
thumbnail capture must never block shortcut cycling or SwiftUI input. The model tags asynchronous
results with the current presentation/enumeration generation so a late title, thumbnail, or refresh
cannot replace a newer selection or resurrect a dismissed panel.

Enumeration and capture are bounded and cancellable where the public API permits. Any future
notification-driven refresh must coalesce an application's burst of Accessibility notifications.
Thumbnails are requested only for the visible bounded set, captured asynchronously at a
presentation-sized resolution, and held in memory only. The feature must not enumerate Accessibility
trees, list system windows, capture pixels, or rebuild application icons on every pointer movement or
key repeat.

Initial thumbnail loading is limited to 24 results. Live Preview refreshes only the selected window
and waits 500 ms between attempts; it is not a multi-window video capture loop.

The optional Dock-hover monitor is stopped by default. When enabled, it polls no faster than every
120 ms and bounds each public Accessibility traversal to depth 7 and 240 visited elements. Hover
delay and protected-panel hit testing must not create an unbounded observer graph or retain a pointer
trail.

For a future authorized runtime, disablement, dismissal, permission revocation, target termination,
and display/Space changes must release event taps, observers, capture tasks, thumbnails, and panel/
session references. Performance is not validated until cold/warm activation, rapid-cycle
responsiveness, idle CPU, capture memory,
and repeated open-dismiss leak measurements are recorded against that privileged artifact. No such
Window Switcher measurements have been recorded, and current sandboxed Commandly cannot supply them.

## Markdown Preview performance contract

The host performs bounded file reads, local-image validation, parsing, and HTML construction away
from the main actor. A new file selection or reload advances a generation and cancels stale work so
an older result cannot replace the current document. File watching is event-driven and coalesced;
it must not poll, render on every raw event, or keep observation alive after the session closes.

Host source reads are capped at 8 MiB. Local images are capped at 32, 2 MiB each, 8 MiB total,
16,384 pixels per dimension, 64 million pixels per frame, 256 frames, 128 million decoded pixels per
image, and 256 million decoded pixels per document. Finder Quick Look reads at most 500 KiB and
truncates at a line boundary. Both surfaces use a nonpersistent web data store, make no renderer
network requests, and release the page when the view or extension preview ends. Search highlights
are capped by the renderer, and only a deliberately restricted regular-expression subset is
accepted before evaluation.

The implementation is not considered performance-validated until cold/warm host render, Finder
first-preview, large-file truncation, image-bound behavior, edit/reload churn, repeated open/close
memory, and idle CPU measurements are recorded on a signed build. No such Markdown Preview
measurements have been recorded yet.

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

### Idle CPU regression check

Measured on July 27, 2026 on the development Apple-silicon Mac using a signed Debug build on the
macOS 27 beta. The original high-CPU process had already exited, so this is a reproduction and
post-fix regression check rather than a profile of that exact PID.

With a root File Search session active, short process samples showed transient indexing activity
between 14% and 16% CPU. After clearing the query and dismissing the launcher, eight consecutive
one-second process samples reported 0.0% CPU and cumulative CPU time remained unchanged at 1.76
seconds. A separate five-second stack sample contained no `PersistentFileSearchService`,
`FileIndexScanner`, `FileIndexEventProcessor`, or `TimelineView` frames.

This verifies the observed Debug run settled after dismissal; it does not establish a universal
Release-build percentile across machines, index sizes, or authorized folder sets.

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
