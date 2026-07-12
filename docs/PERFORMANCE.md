# Performance

These are **future targets**, not measured results. Do not claim they are met until benchmarks exist.

| Metric | Initial target | Notes |
|--------|----------------|-------|
| Cold launch to interactive UI | < 400 ms on reference Apple silicon | Placeholder UI only today |
| Warm launcher open | < 50 ms | Launcher not implemented |
| Keyboard response | < 16 ms input-to-feedback | No palette yet |
| Search result first paint | < 50 ms for local providers | Contracts only |
| Memory while idle | < 80 MB resident | Not measured |
| CPU while idle | ~0% after settling | No background work in foundation |
| Search cancellation | Cancel in-flight work immediately on query change | Required by SearchKit design |

## Engineering guidance

- Keep startup free of permission prompts, network, and heavy I/O.
- Prefer incremental search with cancellation.
- Measure before optimizing; record methodology when adding benchmarks.

## File Search measurements

Measured on July 12, 2026 on the development Apple-silicon Mac. These are system Spotlight
control-query timings, not current end-to-end UI guarantees. The selected search root was the
user's home folder.

| Search | First usable result batch |
|--------|---------------------------|
| Empty recent-files query | 112 ms, 18 results |
| Exact Desktop CSV filename | 333 ms, 2 results |
| Multi-token screenshot filename | 85 ms, 1 image |
| Folder name | 89 ms, 20 results including 2 folders |
| Indexed file contents | 146 ms, 8 content matches |

These are development-machine observations, not universal guarantees. The current development
install must recreate its saved security-scoped bookmark after adding the app-scoped bookmark
entitlement before equivalent in-app measurements are valid. Regression targets are under 250 ms
for the first recent batch and under 500 ms for a selective filename/content query when Spotlight
and the saved grant are healthy. Commandly consumes `NSMetadataQueryGatheringProgress` only when
the batch contains an authorized item with a usable path; it no longer publishes an empty UI from
an incomplete metadata batch.
