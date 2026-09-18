# Modularization progress ledger

Working ledger for the feature-oriented modular monolith migration. This file is the
source of truth for *what has actually moved*, not for what is planned.

A feature is only marked **Migrated** when its implementation lives in its owning target,
its contributions are registered through the module host, and it has verification evidence.
Files moving on disk is not migration.

## Baseline

| Fact | Value |
|------|-------|
| Base branch | `dev` |
| Baseline commit | `d98a43e72fb7575fdaa13381a2cbc33b10ce60a9` ("fix: error while opening navbar") |
| Working branch | `feat/modular-monolith` |
| macOS | 27.0 (26A428), arm64 |
| Xcode | 27.0 (27A266a) at `/Users/marcos/Downloads/Xcode.app` |
| Swift | 6.4 (swiftlang-6.4.0.34.1) |
| Package platform | `.macOS(.v14)`, swift-tools-version 6.0 |
| Scheme used by scripts | `Commandly` (`scripts/common.sh`) |
| SwiftLint / SwiftFormat | not installed — `make verify` skips both steps |

### Baseline verification (run before any edit)

| Command | Result |
|---------|--------|
| `./scripts/doctor.sh` | passed — project readable, 17 schemes |
| `./scripts/build.sh` | **BUILD SUCCEEDED** (exit 0) |
| `./scripts/test.sh` (CommandlyTests) | **TEST SUCCEEDED** (exit 0) |
| `DEVELOPER_DIR=<Xcode 27> swift test --package-path Packages` | passed (exit 0) |

> Note: `swift test` must run with `DEVELOPER_DIR` pointing at Xcode 27. Using the
> default `/Library/Developer/CommandLineTools` toolchain fails to build the package.
> `scripts/verify.sh` already exports the right one via `scripts/common.sh`.

### Baseline scale

| Area | Files | Lines |
|------|-------|-------|
| `Commandly/` (app target) | 623 | 115,130 |
| `Packages/Sources/` | 153 | 25,108 |
| `Packages/Tests/` | 51 | 7,575 |
| `CommandlyTests/` | 173 | 35,962 |
| `CommandlyUITests/` | 2 | 395 |
| `CommandlyMarkdownQuickLook/` | 2 | 438 |
| `CommandlySystemCompanion/` | 5 | 260 |

## Existing architectural seams (traced, not assumed)

| Seam | Location | Assessment |
|------|----------|------------|
| `LauncherApplicationDefinition` | `Commandly/Composition/LauncherApplicationDefinition.swift` | Already a data-only manifest: identity, parent, kind, tags, order, default hot key, typed configuration schema, `CommandManifest`, documentation. Good basis for module metadata; **keep**. |
| `LauncherApplicationRegistry` | `Commandly/Composition/LauncherApplicationRegistry.swift` | Generic registry (register/validate/resolve/ownership/atomic `refreshTools` with rollback/enablement inheritance). The registry itself is **not** the problem. **Keep and evolve.** |
| `LauncherApplicationRegistry.makeBuiltIn` | same file, lines ~448–612 | **This is the giant built-in feature factory.** ~50 parameters, 48 `register(...)` calls, and cross-feature service plumbing (File Search's `pasteboard`/`urlOpener` feeding Downloads, Logos, Offline Tools, Emoji; Quick AI's `chat` feeding Emoji and Dictation). This is what module assemblies replace. |
| `SharedCommandExecutionCoordinator` | `Commandly/Services/CommandExecution/SharedCommandExecution.swift` | Actor: refresh catalog → resolve → availability gate → execute once → privacy-safe history. **One authoritative path already exists.** Do not build a second engine. |
| `CommandReference` / `CommandArguments` / `CommandResult` | `Packages/Sources/CommandKit/` | Typed, persistable, `Codable`. `CommandResult` is `success/failure/cancelled` only — no accepted/denied/interaction-required states yet. |
| `CommandRegistry` | `Packages/Sources/CommandKit/CommandKit.swift` | Actor with atomic `replaceCatalog` + availability snapshot. Authoritative metadata catalog. |
| `DocumentationCatalog` | `Commandly/Scenes/Documentation/DocumentationCatalog.swift` | Already projects articles from the registry + core articles. Typed model, no runtime Markdown parsing. **Keep.** |
| `AppRuntime` | `Commandly/Application/AppRuntime.swift` (1,588 lines) | App-level runtime. Holds `handleRegisteredApplicationPresentation` — the bridge from resolved command to application session or background invocation. Also the place with per-feature properties. |
| `AppContainer` | `Commandly/Composition/AppContainer.swift` (127 lines) | Small; not a service locator today. |
| `SettingsRootView` | `Commandly/Scenes/Settings/SettingsRootView.swift` (340 lines) | Shared settings shell with pane enum. |
| `ApplicationTerminationCoordinator` | `Commandly/Application/ApplicationTerminationCoordinator.swift` (91 lines) | AppKit termination contract. |
| `LauncherApplicationSession` | `Commandly/Scenes/Launcher/Applications/LauncherApplicationSession.swift` | Typed session contract (manifest + model + view factory). |

### Direct-operation seam that already exists

`LauncherApplicationBackgroundInvoking` (application-level) and
`LauncherApplicationToolBackgroundInvoking` (tool-level) let a command run **without**
presenting a launcher session. `AppRuntime.handleRegisteredApplicationPresentation`
(lines ~835–880) dispatches to them from inside the shared executor.

This is the correct existing seam for new direct operations such as `timers.start`.
A new direct operation must **not** introduce a parallel execution engine.

Implementers used by: Microphone Control, Window Switcher, Shelf, System Settings Catalog,
Window Layouts, Offline Tools, Highlight Mode.

### Cross-feature coupling found in the audit (do not preserve blindly)

Derived from `makeBuiltIn` parameter flow, **not** from directory names:

- `FileSearchApplicationServices.pasteboard` is reused by Offline Tools, Downloads, Logos,
  Emoji Search and Dictation. → belongs in a shared clipboard capability, not File Search.
- `FileSearchApplicationServices.urlOpener` / `.fileRevealer` are reused by Downloads,
  File Browser, Image Tools, Markdown Preview. → shared file-action capability.
- `QuickAIApplicationServices.chat` is reused by Emoji Search and Dictation.
  → shared AI text-generation capability; Quick AI keeps its conversation UI.

### Shipping gates to preserve

- **Window Switcher is gated off in the real app.** `AppRuntime.swift:504` calls
  `makeBuiltIn(includesWindowSwitcher: false)`. The parameter default `true` only affects
  tests/previews. Modularization must not enable it.
- `ExternalAgentApplication` is registered twice (`.hermes`, `.openClaw`) from one type.
- `OfflineToolsApplication` is registered once per `OfflineToolKind` except `.emoji`.

## Target structure

Adopted incrementally; only rows marked ✅ exist in the build graph today.

| Target | Role | State |
|--------|------|-------|
| `ModuleKit` | Data-only module metadata + non-UI contribution/lifecycle contracts | ✅ |
| `ModuleRuntime` | Generic host: validation, lazy exactly-once activation, ownership-scoped tokens, catalog projection, teardown | ✅ |
| `AICommandBridge` | Default-deny projection of module commands to `AIKit` tool definitions | ✅ |
| `TimersModule` | Timers & Focus feature target (domain, commands, settings schema, docs) | ✅ |
| `CommandlyUI` | UI contribution contracts + reusable launcher/settings components | not started |
| `ModuleRuntimeUI` composition adapter | Bridges UI contributions to one module lifetime | not started |
| Remaining feature targets | see inventory below | not started |

## Feature inventory

Owner column is the *intended* module owner. Status is the *actual* migration state.

Lifetime key: **infra** = application infrastructure, **service** = retained while the
module is enabled, **session** = launcher presentation session, **operation** = independent
work that outlives the session.

| # | Feature (application ID) | Current implementation | Lifetime | Intended owner | Status |
|---|--------------------------|------------------------|----------|----------------|--------|
| 1 | Timers & Focus (`timers.focus`) | `Scenes/Launcher/Applications/TimersApplication.swift`, `Scenes/Launcher/Commands/Timers/`, `Services/Timers/TimerStore.swift` | service (tick timer) + session | `TimersModule` | **Migrated (domain + commands)** — see below |
| 2 | Clipboard History (`clipboard.history`) | `Services/Clipboard/`, `ClipboardHistoryApplication` | service (monitor) + session | `ClipboardHistoryModule` | Not started |
| 3 | Screen Recording | `Services/ScreenRecording/`, `Scenes/ScreenRecording/`, `ScreenRecordingApplication` | operation (recording/export) | `ScreenRecordingModule` | Not started |
| 4 | File Search (`files.search`) | `Services/FileSearch/`, `FileSearchApplication` | service (index) + session | `FileSearchModule` | Not started |
| 5 | File Browser | `Services/FileBrowser/`, `FileBrowserApplication` | session + folder grants | `FileBrowserModule` | Not started |
| 6 | Calculator history | `CalculatorKit` + `CalculatorHistoryApplication` | session | `CalculatorModule` | Not started |
| 7 | Downloads | `Services/Downloads/` | session | `DownloadsModule` | Not started |
| 8 | Logos | `Services/Logos/` | session | `LogosModule` | Not started |
| 9 | Background Remover | `Services/BackgroundRemoval/` | session | `ImageToolsModule` | Not started |
| 10 | Image Tools | `Services/ImageTools/` | session | `ImageToolsModule` | Not started |
| 11 | Schedule | `Services/Schedule/` | service | `ScheduleModule` | Not started |
| 12 | Camera | `Services/Camera/` | session (capture device) | `CameraModule` | Not started |
| 13 | Screenshot | `Services/Screenshot/` | operation | `ScreenshotModule` | Not started |
| 14 | Display Resolution | `Services/DisplayResolution/`, `Scenes/DisplayResolution/` | operation (rollback txn) | `DisplayResolutionModule` | Not started |
| 15 | Menu Bar Shortcuts | `Services/MenuBarShortcuts/` | infra + service | `MenuBarShortcutsModule` | Not started |
| 16 | Celebration | `CelebrationApplication` | session | `CelebrationModule` | Not started |
| 17 | Finance | `Services/Finance/` | session | `FinanceModule` | Not started |
| 18 | Markdown Preview | `MarkdownPreviewKit`, `Services/MarkdownPreview/` | session + file watcher | `MarkdownPreviewModule` | Not started |
| 19 | Shelf | `Services/Shelf/` | service + independent window | `ShelfModule` | Not started |
| 20 | Productivity Library / Floating Notes | `Services/ProductivityLibrary/`, `Scenes/FloatingNotes/` | service + operation (unsaved notes) | `ProductivityLibraryModule` | Not started |
| 21 | System Settings Catalog | `Services/SystemSettings/` | direct operations | `SystemToolsModule` | Not started |
| 22 | System Activity | `Services/SystemActivity/` | session | `SystemToolsModule` | Not started |
| 23 | Port Manager | `Services/PortManagement/` | session | `SystemToolsModule` | Not started |
| 24 | Storage Cleaner | `Services/StorageCleaner/` | session + destructive ops | `StorageCleanerModule` | Not started |
| 25 | Microphone Control | `Services/Microphone/` | direct operation | `SystemToolsModule` | Not started |
| 26 | Highlight Mode | `Services/HighlightMode/` | service + direct operation | `HighlightModeModule` | Not started |
| 27 | Window Switcher | `Services/WindowSwitcher/`, `Scenes/WindowSwitcher/` | service | `WindowSwitcherModule` | Not started — **gated off, keep off** |
| 28 | Window Layouts | `Services/WindowLayouts/` | direct operation + companion | `WindowLayoutsModule` | Not started |
| 29 | Finder AI | `Services/AI/`, `Scenes/Launcher/Commands/FinderAI/` | session + AI grants | `FinderAIModule` | Not started |
| 30 | Quick AI | `QuickAIApplication` | session; **`chat` shared** | `QuickAIModule` + shared AI capability | Not started |
| 31 | AI Agents | `AIAgentLibrary` (AIKit) | session | `AIAgentsModule` | Not started |
| 32 | Visual AI | `VisualAIApplication` | session | `VisualAIModule` | Not started |
| 33 | External Agents (Hermes, OpenClaw) | `Services/AI/ExternalAgents/` | session + connections | `ExternalAgentsModule` | Not started |
| 34 | Writing Tools | `Services/WritingTools/` | session | `WritingToolsModule` | Not started |
| 35 | Translation | `Services/Translation/` | session | `TranslationModule` | Not started |
| 36 | Emoji Search | `Services/Emoji/` | session; depends on shared clipboard + AI | `EmojiModule` | Not started |
| 37 | Dictation | `Services/Dictation/` | service (mic) ; depends on shared clipboard + AI | `DictationModule` | Not started |
| 38 | GIF Search | `Services/GIFSearch/` | session + network | `GIFSearchModule` | Not started |
| 39 | Slack Emoji | `Services/SlackEmoji/` | session + connection | `SlackEmojiModule` | Not started |
| 40 | Notion Workspace | `Services/Notion/` | session + connection | `NotionModule` | Not started |
| 41 | Finder Path | `Services/FinderPath/` | direct operation | `FinderPathModule` | Not started |
| 42 | App Menus | `Services/AppMenus/` | direct operation | `AppMenusModule` | Not started |
| 43 | Offline Tools (per `OfflineToolKind`) | `Services/OfflineTools/` | direct operations | `OfflineToolsModule` | Not started |
| 44 | Open Settings | `OpenSettingsApplication` | infra | shell | Not started |
| 45 | Command Wheel | `Scenes/CommandWheel/`, `Services/CommandWheel/` | infra consumer of command references | shell | Not started |
| 46 | Keyboard Triggers | `Services/KeyboardTriggers/` | infra | shell | Not started |
| 47 | System Companion | `SystemCompanionKit`, `CommandlySystemCompanion` | separate signed target | platform exception | Not started |
| 48 | Markdown Quick Look | `CommandlyMarkdownQuickLook` | separate signed target | platform exception | Not started |

## Milestone status

| Milestone | Scope | Status |
|-----------|-------|--------|
| A — Baseline and contracts | Inventory, `ModuleKit`, `ModuleRuntime`, host tests | **Done** |
| B — Timers end to end | `TimersModule`, `timers.start` direct operation, shared execution | **Done** |
| C — Clipboard History | monitoring, enrichment, settings, search, storage | Not started |
| D — Screen Recording | independent coordinator, operation state, termination | Not started |
| E — Shared shell and remaining modules | remaining inventory | Not started |
| F — AI bridge and developer workflow | `AICommandBridge` ✅; module template ✅; docs export | Partial |
| G — Remove migration machinery and verify | remove `makeBuiltIn`, final verify | Not started |

## Command coverage matrix

Only commands whose module has been migrated are listed. A command is added here when
it is registered through `ModuleRuntime`, not when it merely exists.

### TimersModule

| Command ID | Operation meaning | Entry points | Mode | Input | Output | Capabilities | AI |
|------------|-------------------|--------------|------|-------|--------|--------------|-----|
| `timers.focus` | Open the Timers & Focus application surface | search, shortcut, wheel, menu bar | requiresUserInterface | — | presented session | none | **hidden** (presentation only) |
| `timers.focus.tool.open` | Open the timers surface | search, shortcut, wheel | requiresUserInterface | — | presented session | none | **hidden** (presentation only) |
| `timers.new` | Open the new-timer **draft** (does not start a timer) | search, shortcut, wheel | requiresUserInterface | — | presented session with draft | none | **hidden** (interaction required) |
| `timers.start` | **Start a countdown immediately** | search, shortcut, wheel, menu bar, AI | direct | `durationSeconds` (int, required), `title` (string, optional) | timer id + phase + end time | none | **exposed** (reviewed) |

Unsupported automation operations and why:

- `timers.focus`, `timers.focus.tool.open` — open a window; nothing to automate headlessly.
- `timers.new` — deliberately opens a draft for the user to complete. Exposing it to AI
  would let a model claim it started a timer when it only opened a form. Use `timers.start`.

## Verification evidence

| Check | Command | Result |
|-------|---------|--------|
| Baseline build | `./scripts/build.sh` | passed (exit 0) |
| Baseline app tests | `./scripts/test.sh` | passed (exit 0) |
| Baseline package tests | `DEVELOPER_DIR=<Xcode 27> swift test --package-path Packages` | passed (exit 0) |
| Post-A/B module boundaries | `./scripts/check-module-boundaries.sh` | **MODULE BOUNDARIES OK** |
| Post-A/B package tests | `DEVELOPER_DIR=<Xcode 27> swift test --package-path Packages` | passed — 16 suites, including 33 ModuleKit, 25 ModuleRuntime, 25 AICommandBridge, 53 TimersModule |
| Post-A/B app build | `./scripts/build.sh` | **BUILD SUCCEEDED** (exit 0) |
| Post-A/B app tests | `./scripts/test.sh` (run repeatedly) | green except for the three pre-existing wall-clock flakes below; **green on every other test** with those three skipped |
| Post-A/B composition tests | `-only-testing:CommandlyTests/ModuleCompositionTests` + `ModuleAIExposureCompositionTests` + `TimersApplicationTests` | 21/21 passed |
| Module generator | `./scripts/new-module.sh Bookmarks` then `swift test --filter BookmarksModuleTests` | 4/4 passed; collision and bad-name cases correctly refused; scratch module removed afterwards |
| Full verification | `make verify` | steps 1–6 pass (structural, **MODULE BOUNDARIES OK**, package resolution, format/lint skipped — not installed, package tests) and step 8 (app build) passes. Step 7 (app tests) hits one of the pre-existing flakes below on some runs, exactly as the baseline does. |

### Known flaky tests (pre-existing, not regressions)

Three tests in `CommandlyTests` fail intermittently in full-suite runs and pass in isolation. All
three depend on a **wall-clock budget** that the parallel full-suite load can exceed on a busy
machine — the pattern `AGENTS.md` already forbids ("Arbitrary `Task.sleep` used as
synchronization").

| Test | Wall-clock dependency |
|------|-----------------------|
| `MenuControllerTests/appSwitchInvalidatesAndRefreshDoesNotRetargetOpenSession()` | Suite-wide deadline `ContinuousClock.Instant.now.advanced(by: .seconds(5))` (`CommandlyTests/MenuControllerTests.swift:14`); every `controller.handle(...)` call runs under it. |
| `CommandlyTests/fileSearchActionsCardExecutesNativeAndNestedActions()` | `waitUntil(timeoutNanoseconds:condition:)` (`CommandlyTests/CommandlyTests.swift:3058`) — a **1-second** sleep-polling loop that returns *silently* when the budget expires, so the following `#expect` fails. |
| `CommandlyTests/clipboardEnrichmentAppliesAndIgnoresStaleIDs()` | Inline **2-second** `Date()` deadline with `Task.sleep(for: .milliseconds(20))` polling (`CommandlyTests/CommandlyTests.swift:2394`). |

None is related to this migration: nothing here touches App Menus, `CompanionMenuController`,
`CompanionMenuLease`, `SystemCompanionKit`, File Search, or clipboard capture.

**Decisive check.** Running the complete app test suite on this branch with exactly these three
tests skipped is green:

```
xcodebuild ... -only-testing:CommandlyTests \
  -skip-testing:"CommandlyTests/MenuControllerTests/appSwitchInvalidatesAndRefreshDoesNotRetargetOpenSession()" \
  -skip-testing:"CommandlyTests/CommandlyTests/fileSearchActionsCardExecutesNativeAndNestedActions()" \
  -skip-testing:"CommandlyTests/CommandlyTests/clipboardEnrichmentAppliesAndIgnoresStaleIDs()" test
→ ** TEST SUCCEEDED ** (exit 0)
```

Everything else in the suite — including every test added by this migration — passes. Verified in
isolation too: `-only-testing:CommandlyTests/MenuControllerTests` 11/11 passed, and
`fileSearchActionsCardExecutesNativeAndNestedActions()` passed in 0.090 s.

> Filter note: a Swift Testing method filter needs the trailing `()`. Without it `xcodebuild`
> matches nothing, runs zero tests, and still reports `** TEST SUCCEEDED **`.

**Baseline evidence (collected, not assumed).** `d98a43e7` was checked out into separate git
worktrees with none of this migration's changes, and `./scripts/test.sh` was run five times:

| Baseline run | Result |
|--------------|--------|
| 1 | passed (exit 0) |
| 2 | **failed** — `appSwitchInvalidatesAndRefreshDoesNotRetargetOpenSession()` |
| 3 | **failed** — `appSwitchInvalidatesAndRefreshDoesNotRetargetOpenSession()` |
| 4 | **failed** — `fileSearchActionsCardExecutesNativeAndNestedActions()` |
| 5 | passed (exit 0) |

**The untouched baseline passes only 2 of 5 full-suite runs, and both flaky tests reproduce there.**
The app test suite — and therefore `make verify` — was already intermittently red before this work.

Fixing these tests is out of scope for an architecture migration and is deliberately not bundled
here. Each needs its wall-clock budget replaced with an injected clock or an explicit signal.

`make verify` consequently cannot be reported as a clean pass on this branch. Every step of it
except the app-test step passes; the app-test step passes on some runs and hits one of these two
pre-existing flakes on others, exactly as it does on the baseline.

## Outstanding work

### Deliberately deferred adapters

| Adapter | Why it exists | Removal condition |
|---------|---------------|-------------------|
| `Commandly/Composition/ModuleSettingsProjection.swift` | Modules author `ModuleConfigurationField`; the launcher settings screen still renders `LauncherConfigurationField`. The projection keeps one authored source instead of two hand-maintained copies. | Retire when the launcher settings screen consumes the module schema directly. |
| Authored documentation bodies in `LauncherApplicationDocumentation` | `ModuleDocumentationContribution` currently carries article identity, summary, and validated references; the rich typed body model still lives in the app target. | Merge when a `CommandlyUI`/documentation target owns the typed body model. |
| `TimersApplication` in the app target | The launcher session contract (`LauncherApplicationSession`) is an app-target type, so the SwiftUI surface cannot move yet. | Move when `CommandlyUI` owns the session and UI contribution contracts. |
| Grants synthesised in `TimersApplication.invokeToolInBackground` | `LauncherApplicationToolBackgroundInvoking` does not forward the `CommandInvocationContext`, so a background tool cannot see its real caller. Authorization is therefore decided **before** dispatch (by `SharedCommandModuleDispatcher` for automation callers, by the launcher availability gate for user-initiated ones), and this boundary carries only the identity grant the command's policy requires — it never upgrades authority. | Forward the invocation context and caller grants through `LauncherApplicationToolBackgroundInvoking`. **Required before routing any command with a `filesystemMutation`, `externalAction`, or disclosing policy through this path.** |

### Not started

- Milestone C (Clipboard History), D (Screen Recording), E (remaining modules), G (removing
  `makeBuiltIn` and the remaining migration machinery).
- `CommandlyUI` and the UI contribution contracts.
- Deterministic documentation Markdown/JSON export command.
- Extraction of the shared clipboard, file-action, and AI text-generation capabilities that
  `makeBuiltIn` currently threads between unrelated features.
- Long-running operation handles (`accepted` / progress / cancellation) are modelled in `ModuleKit`
  but no migrated module uses them yet; Screen Recording is their first real consumer.
- Native acceptance checks: permission dialogs, capture hardware, signing, Quick Look registration,
  App Group communication, and full-screen Spaces behavior are **not** covered by the automated
  suites above.
