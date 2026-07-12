# Security Policy

## Reporting a vulnerability

If you discover a security issue in Commandly, please report it privately to the maintainers. Do not open a public issue for sensitive reports until a fix is available.

Include:

- Affected version / commit
- Reproduction steps
- Impact assessment
- Any suggested remediation

## Project security stance

Commandly will eventually interact with apps, files, clipboard data, and possibly extensions. The foundation therefore treats security as a first-class concern:

- Least privilege entitlements
- No secrets in source control
- No sensitive values in logs
- No arbitrary shell execution of user input
- Extension loading is explicitly out of scope until a reviewed design exists

See `docs/SECURITY_MODEL.md` for detailed guidance.
