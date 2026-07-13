# Security Model

## Future risk areas

| Risk | Why it matters | Foundation stance |
|------|----------------|-------------------|
| Malicious extensions | Third-party code can steal data or crash the app | No loading yet; manifests only |
| Command injection | User text interpolated into shells | Forbidden; no arbitrary shell execution |
| Unsafe shell execution | Broad process APIs are dangerous | Not implemented; avoid |
| Credential leakage | Tokens in logs/plists/git | Secrets only via secure storage contracts |
| Clipboard exposure | Clipboard may contain passwords | Never log pasteboard contents; OCR / extracted file text treated the same and stay in-memory only |
| Shelf reference exposure | Dropped URLs can disclose private names, paths, or contents | Keep references in-memory, hold security scope only while staged, never log them, and perform sharing/mutation only after explicit user action |
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

Shelf accepts concrete file and folder URLs only after an explicit drop or file-URL paste. A staged
reference is not a copied file and is not written to preferences, Application Support, or logs.
Security-scoped access is released when the reference leaves the board or the board closes. Native
sharing hands URLs to the service the user chooses; that service controls recipients, sign-in, and
network transfer. Copy, move, duplicate, rename, and Trash actions affect real filesystem items and
must report sandbox, scope, conflict, and operation failures rather than implying success.

Shelf does not execute scripts or shell commands and does not hold cloud-provider credentials. Plain
text, standalone clipboard images, promised files, hosted links, transformations, and background
folder monitoring remain outside the implemented boundary.

See also `SECURITY.md` and `docs/PERMISSIONS.md`.
