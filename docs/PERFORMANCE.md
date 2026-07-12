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
