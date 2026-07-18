# Development

## Required Xcode setup

Commandly’s Xcode project uses **objectVersion 110** and was created with **Xcode 27**. Xcode 26.x cannot open it.

1. Install Xcode 27+.
2. Select it:

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
# or your Xcode 27 beta path
```

3. Confirm:

```bash
xcodebuild -version
make doctor
```

Optional override for scripts without changing the system default:

```bash
export COMMANDLY_DEVELOPER_DIR="/path/to/Xcode.app/Contents/Developer"
```

## Bootstrap

```bash
make bootstrap
```

This verifies tools, creates `config/Local.xcconfig` from the example if missing, and resolves packages.

## Open the project

```bash
make open
```

Or open `Commandly.xcodeproj` with Xcode 27+.

## Build from Xcode

1. Select the **Commandly** scheme.
2. Choose **My Mac**.
3. Press Run.

## Build from the terminal

```bash
make build
```

Uses repository-local `.derivedData`.

## Run tests

```bash
make test
swift test --package-path Packages
```

For Command Wheel changes, follow the focused automated, GUI, manual, accessibility, multi-display,
and performance matrix in [Command Wheel Testing](COMMAND_WHEEL_TESTING.md), then run
`make verify`. Geometry and state tests are not a substitute for checking the temporary panel,
focus restoration, Spaces/full-screen behavior, and VoiceOver on macOS.

## Change commands or Command Wheel

- Add reusable command metadata and behavior through the shared CommandKit/launcher-application
  path. Do not add an execution switch, AppKit closure, or native service call to Command Wheel.
- Keep persisted command arguments typed, schema-validated, reusable, and non-secret. Usage history
  must never retain their values.
- Keep radial geometry and display positioning pure. Use the returned clamped center for rendering
  and hit testing.
- Treat input, timer, provider-task, panel, and shortcut registrations as lifecycle-owned resources;
  teardown must be explicit and testable.
- Update the typed in-app article and repository user/architecture/extension/testing docs whenever
  behavior changes.

Read [Command Wheel Architecture](COMMAND_WHEEL_ARCHITECTURE.md),
[Extending Command Wheel](COMMAND_WHEEL_EXTENDING.md), and ADR-0007 before editing the feature.

## Add a new module

1. Add a target + product in `Packages/Package.swift`.
2. Create sources under `Packages/Sources/<Module>`.
3. Add tests under `Packages/Tests/<Module>Tests`.
4. Link the product in `Commandly.xcodeproj` (package product dependency).
5. Import only from allowed dependents.
6. Document ownership in `AGENTS.md` / architecture docs.

## Add a new permission

1. Document benefit and prompt timing in `docs/PERMISSIONS.md`.
2. Update entitlements / usage descriptions only when required.
3. Request only after user intent.
4. Provide denial recovery guidance.
5. Mock permission state in tests.

## Common signing problems

| Symptom | Likely cause | Mitigation |
|---------|--------------|------------|
| Team required | No development team selected | Set team in Xcode Signing settings or optional `DEVELOPMENT_TEAM` in gitignored `Local.xcconfig` |
| Sandbox violations | Missing entitlement for a feature | Add least-privilege entitlement only when feature needs it |
| Wrong Xcode | objectVersion 110 unread | Use Xcode 27+ / `COMMANDLY_DEVELOPER_DIR` |

Do not commit personal Team IDs if you consider them private. Automatic signing without a committed Team ID is preferred.
