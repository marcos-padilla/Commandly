# Extensions (Future)

Extension support is **not implemented**. `ExtensionKit` only stores experimental manifest models.

This status refers to **external** extensions. The launcher definition role named `AI Extension`
describes built-in, reviewed Commandly code such as Finder AI; it does not load an external bundle,
script, manifest implementation, or provider-supplied code. `AIKit` provider adapters are ordinary
compiled package code, and model output is treated as untrusted data accepted only through typed,
locally enforced tools. See `docs/AI.md` and ADR-0006.

## Candidate approaches

| Approach | Pros | Cons |
|----------|------|------|
| Built-in native commands | Fast, typed, reviewable | Requires app updates |
| Declarative extensions (JSON/YAML manifests) | Easy to reason about, limited power | Limited capability |
| Signed native bundles | High performance, Apple-native | Higher authoring cost; signing required |
| JavaScript extensions | Familiar to many authors | Runtime complexity, security surface |
| XPC isolation | Crash and privilege isolation | Complexity, IPC overhead |
| Shortcuts / App Intents | System integration | Less “launcher native” UX |
| Remote API integrations | Powerful workflows | Network, auth, privacy concerns |

## Design constraints whenever extensions begin

- Security: signing, permission declarations, no implicit trust
- Performance: extension latency budgets and cancellation
- Versioning: manifest compatibility with app versions
- Permissions: explicit, least privilege, user visible
- Crash isolation: prefer out-of-process execution for untrusted code

Do not load external code, create a marketplace, or embed a JS runtime until an ADR is accepted.
The BYOK AI decision does not authorize any of those capabilities. Adding a built-in AI extension
must not be used to bypass the future signing, isolation, permission, and review design required for
third-party extensions.
