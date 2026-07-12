# Security Model

## Future risk areas

| Risk | Why it matters | Foundation stance |
|------|----------------|-------------------|
| Malicious extensions | Third-party code can steal data or crash the app | No loading yet; manifests only |
| Command injection | User text interpolated into shells | Forbidden; no arbitrary shell execution |
| Unsafe shell execution | Broad process APIs are dangerous | Not implemented; avoid |
| Credential leakage | Tokens in logs/plists/git | Secrets only via secure storage contracts |
| Clipboard exposure | Clipboard may contain passwords | Never log pasteboard contents; OCR / extracted file text treated the same and stay in-memory only |
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

See also `SECURITY.md` and `docs/PERMISSIONS.md`.
