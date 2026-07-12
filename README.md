# Commandly

Commandly is intended to become a fast, keyboard-first productivity launcher for macOS — original software in the same general category as Raycast, Alfred, and Spotlight, without copying their source, branding, assets, or exact UI.

## Current status

**Foundation only.** The repository currently provides project structure, modular architecture, documentation, scripts, and a placeholder screen. Launcher features are not implemented.

## Technology stack

- Swift / SwiftUI (AppKit only where required)
- Swift Concurrency with strict checking
- Swift Package Manager local modules
- OSLog via Observability
- Swift Testing / XCTest
- Native Apple frameworks only (no third-party dependencies in this phase)

## Prerequisites

- macOS 27.0+
- **Xcode 27+** (the project uses objectVersion 110 and cannot be opened by Xcode 26.x)
- Git
- Optional: SwiftLint, SwiftFormat (`brew install swiftlint swiftformat`)

If multiple Xcode versions are installed, scripts auto-select a toolchain that can open the project. You can override with:

```bash
export COMMANDLY_DEVELOPER_DIR="/path/to/Xcode.app/Contents/Developer"
```

## Open the project

```bash
make open
# or
open Commandly.xcodeproj   # with Xcode 27+ as default
```

## Build

```bash
make bootstrap
make build
```

## Test

```bash
make test
```

Package-only:

```bash
swift test --package-path Packages
```

## Verify

```bash
make verify
```

This runs structural checks, package resolution, optional format/lint, package tests, app unit tests, and a Debug build.

## Project structure

```text
Commandly/                 App target (composition + scenes)
Packages/                  Local SPM modules
CommandlyTests/            App unit tests
CommandlyUITests/          UI tests (optional / skipped in default scheme)
config/                    xcconfig files
docs/                      Architecture and process docs
scripts/                   doctor, bootstrap, build, test, verify, …
AGENTS.md                  Rules for future AI agents and contributors
```

## Architecture summary

The app target is a thin composition root. Domain and infrastructure contracts live in local Swift packages with one-directional dependencies. Concrete services are assembled in `Commandly/Composition`. See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## Roadmap

See [docs/ROADMAP.md](docs/ROADMAP.md). Phase 1 (project foundation) is the current scope.
