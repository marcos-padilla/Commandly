# Launcher Scene

Primary Commandly command palette: a floating, draggable, scrollable panel summoned by **⌥Space** or **Open Commandly** in the menu bar.

## Search

The main field is the primary entry point for discovering and running work:

- Focus stays on the search field (not the parent window chrome) so typing always updates the query
- Launcher chrome stays **borderless** (no titled title-bar / empty chrome strip) and patches `canBecomeKey` for the launcher window identifier so reopen can type; `searchFocusEpoch` / `prepareForPresentation` / `requestSearchFocus` reclaim `@FocusState` after hide
- Click outside / app deactivate dismisses the launcher (global + local mouse monitors, resign-key, resign-active)
- Ranked results via SearchKit providers: **commands**, **applications**, and honest **placeholders**
- Result rows are single-line: icon, title, optional muted inline subtitle, trailing kind label; selection uses a subtle full-width rounded overlay
- While the results list is scrolling, pointer hover does not move selection (keyboard selection still works); hover may resume shortly after scrolling stops
- Calculator-shaped queries are evaluated via **CalculatorKit** in parallel and pinned in a dedicated **Calculator** two-pane card above other results
- `CompositeSearchService` merges scores (prefix > keyword > contains) and cancels in-flight work on each keystroke
- Ghost autocomplete for the best result prefix or calculator completion; **Tab** and the right-side Tab control accept it, while **Return** confirms the selected row
- Calculator autocomplete recomputes recoverable expressions, inferred unit targets, and unique fuzzy corrections on every keystroke; stale asynchronous suggestions are discarded
- Installed apps are enumerated from standard Applications folders and opened through `ApplicationOpening` (full catalog; Applications section appears below Commands)
- Application rows show each app’s real icon from its bundle via `NSWorkspace`

## Command system

Built-in commands register through `CommandCatalog` / `LauncherCommandRegistering`:

- `CommandManifest` (CommandKit) — id, title, icon, mode (`.action` | `.view`), keywords, default footer actions
- Action mode — runs immediately (example: Open Settings)
- View mode — pushes a command surface with its own search/list/preview and footer actions (example: Clipboard History)

Root search shows a footer with an app-menu (Settings, Quit) and an empty **Actions** menu. Command surfaces keep their own footer chrome driven by `CommandActionDescriptor` values so actions (Copy, Actions menu, etc.) stay consistent.

## Clipboard History

Fully implemented first command surface:

- Monitors the system pasteboard in the **background** (text, images, file URLs) without activating Commandly or raising windows
- Search + type filter over **capture-time** metadata (never re-runs Vision/PDFKit while typing)
- Images: on-device Vision OCR + classification labels (e.g. search “flower”); Live Text overlay on the detail preview
- Files: PDFKit text, plain-text/RTF extraction where readable; otherwise filename-only (sandbox may skip some paths)
- Split list / preview / metadata (image pasteboard items and image file URLs show a detail preview)
- Copy, Delete, Clear History via footer + Actions menu; hover Copy on list rows
- Re-copy write-backs are not recorded as new history entries
- Never logs clipboard contents or OCR / extracted text

Clipboard capture updates the in-memory store only. The launcher must not re-raise on store changes (`LauncherWindowConfigurator` applies chrome without calling `BringHostingWindowToFront`).

## Non-goals (for now)

- AI / natural-language Q&A
- File search, extensions, remote data
- Exact competitor layouts or branding
- Persisting clipboard history to disk (in-memory for this phase)
- Persisting search history
