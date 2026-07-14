# Security Model

## Future risk areas

| Risk | Why it matters | Foundation stance |
|------|----------------|-------------------|
| Malicious extensions | Third-party code can steal data or crash the app | No loading yet; manifests only |
| Command injection | User text interpolated into shells | Forbidden; no arbitrary shell execution |
| Unsafe shell execution | Broad process APIs are dangerous | Not implemented; avoid |
| Credential leakage | Tokens in logs/plists/git | Secrets only via secure storage contracts |
| Clipboard exposure | Clipboard may contain passwords | Never log pasteboard contents; Clipboard History enrichment stays in memory, while explicit Shelf text/image imports use an owner-only per-board temporary directory that is deleted on cleanup |
| Shelf reference exposure | Dropped URLs and materialized clipboard content can disclose private names, paths, or contents | Keep external references in memory, confine owned content to a private temporary directory, hold security scope only while staged, never log payloads or paths, and perform sharing/mutation only after explicit user action |
| Unsafe URLs | OpenURL can be abused | Validate before opening |
| Path traversal | File APIs may escape intended roots | Validate and constrain paths |
| Excessive permissions | Hard to revoke trust | Least privilege; contextual prompts |
| Insecure updates | Tampered builds | Distribution design deferred |

## Hard rules

- Never directly execute user-entered shell strings.
- Validate URLs before opening.
- Validate file paths and keep access scoped.
- Store secrets in Keychain (via `SecureStoring`), never UserDefaults or source.
- Redact sensitive values in logs (`SensitiveValue`, logging policy).
- Require confirmation for destructive actions (future features).
- Use least privilege entitlements.
- Do not request permissions at launch.

## Shelf boundary

Shelf accepts concrete file and folder URLs after an explicit drop or paste and accepts an explicit
clipboard import of plain text or a standalone image. A staged external reference is not copied and
is not written to preferences, Application Support, or logs. Imported text/image bytes are
materialized beneath an owner-only, per-board directory in Commandly's temporary container so they
can use the same URL-based action pipeline. Owned files are deleted when their items leave Shelf,
and the directory is deleted when the board closes or is replaced.

Security-scoped access is released when an external reference leaves the board or the board closes.
Native sharing hands URLs to the service the user chooses; that service controls recipients,
sign-in, and network transfer. Copy, move, duplicate, rename, and Trash actions affect filesystem
items and must report sandbox, scope, conflict, and operation failures rather than implying success.

Shelf does not execute scripts or shell commands and does not hold cloud-provider credentials.
Promised files, rich-text preservation, arbitrary pasteboard representations, hosted links,
transformations, and background folder monitoring remain outside the implemented boundary.

See also `SECURITY.md` and `docs/PERMISSIONS.md`.
