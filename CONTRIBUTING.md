# Contributing

Thanks for helping build Commandly.

## Before you start

1. Read `AGENTS.md`.
2. Read `docs/ARCHITECTURE.md` and `docs/DEVELOPMENT.md`.
3. Run `make doctor` and `make bootstrap`.
4. Keep changes scoped to the owning module.

## Development loop

```bash
make bootstrap
make test
make verify
```

## Rules of thumb

- Prefer native Apple APIs over third-party dependencies.
- Put contracts in packages; assemble implementations in `Composition`.
- Do not request permissions at launch.
- Do not commit secrets, Team IDs you want private, or `config/Local.xcconfig`.
- Add tests for new behavior.
- Update docs when architecture or workflow changes.

## Pull requests

- Describe user-visible behavior and module ownership.
- List tests run.
- Call out permission, privacy, or performance impact.
- Do not claim features that are only scaffolded.
