# Extensions (Future)

Extension support is **not implemented**. `ExtensionKit` only stores experimental manifest models.

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
