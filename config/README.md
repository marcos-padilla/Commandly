# Build Configuration

This directory holds shared `.xcconfig` files for Commandly.

| File | Purpose |
|------|---------|
| `Base.xcconfig` | Shared non-secret settings |
| `Debug.xcconfig` | Debug overrides |
| `Release.xcconfig` | Release overrides |
| `Local.example.xcconfig` | Template for optional local overrides |
| `Local.xcconfig` | Machine-specific overrides (gitignored) |

## Rules

- Never commit Team IDs you consider private, API keys, certificates, or absolute machine paths.
- Prefer automatic signing.
- Use `scripts/bootstrap.sh` to create `Local.xcconfig` from the example when missing.
