# Launcher Scene

Primary Commandly command palette: a floating, draggable, scrollable panel summoned by **⌥Space** or **Open Commandly** in the menu bar.

## Search

The main field is the primary entry point for discovering and running work:

- Focus stays on the search field (not the parent window chrome) so typing always updates the query
- Launcher chrome stays **borderless** (no titled title-bar / empty chrome strip) and patches `canBecomeKey` for the launcher window identifier so reopen can type; `searchFocusEpoch` / `prepareForPresentation` / `requestSearchFocus` reclaim `@FocusState` after hide
- Clicking outside dismisses the launcher through local/global mouse monitors; keyboard-only Space changes do not count as an outside click
- **Escape**: AppKit key monitor (TextField cannot swallow it); overlays first, then application-local Escape, then home, then hide
- Ranked results via SearchKit providers: **commands**, **applications**, and honest **placeholders**
- Result rows are single-line: icon, title, optional muted inline subtitle, trailing kind label; selection uses a subtle full-width rounded overlay
- While the results list is scrolling, pointer hover does not move selection (keyboard selection still works); hover may resume shortly after scrolling stops
- Calculator-shaped queries are evaluated via **CalculatorKit** in parallel and pinned in a dedicated **Calculator** two-pane card above other results
- `CompositeSearchService` merges scores (prefix > keyword > contains) and cancels in-flight work on each keystroke
- Ghost autocomplete for the best result prefix or calculator completion; **Tab** and the right-side Tab control accept it, while **Return** confirms the selected row
- Calculator autocomplete recomputes recoverable expressions, inferred unit targets, and unique fuzzy corrections on every keystroke; stale asynchronous suggestions are discarded
- Installed apps are enumerated from standard Applications folders and opened through `ApplicationOpening` (full catalog; Applications section appears below Commands)
- Application rows show each app’s real icon from its bundle via `NSWorkspace`

## Application system

Built-in capabilities register once through `LauncherApplicationRegistry` / `LauncherApplication`:

- `CommandManifest` (CommandKit) — discovery metadata: id, title, icon, mode (`.action` | `.view`), keywords, default footer actions
- `launch(in:)` — runs an action immediately or constructs a strongly typed `LauncherApplicationSession`
- `LauncherApplicationSession` — the small type-erased shell boundary for content, status, selection, lifecycle, and footer actions
- `LauncherRootView` — dynamically hosts the active session with no Clipboard/File Search branches
- `LauncherApplicationScreen` — optional reusable search/filter/sidebar/detail composition for browser-style applications

See `docs/LAUNCHER_APPLICATIONS.md` for the extension workflow and ADR-0004 for the boundary decision.

`Search Files` is a full view application backed by Commandly's persistent local index within
user-authorized folders. It supports indexed-content search, type filters, Quick Look, metadata,
and file actions.
See `docs/FILE_SEARCH.md` for architecture, privacy, and current limitations.

Root search shows contextual **Actions** at the footer's leading edge and one persistent Settings gear menu at the trailing edge. The gear menu contains Documentation, Settings, and Quit without adding a separate Commandly button. Right-click an installed macOS application row (or press Actions / ⌘K with one selected) to open a searchable application-actions panel: open, Finder reveal / Get Info / package contents, favorites, copy name/path/bundle ID, auto-quit, disable, uninstall, and reset ranking. **Uninstall** opens a review surface that lists the app plus related support files (filter/sort/select) and moves the selected items to the Trash. Registered Commandly application surfaces keep their own footer chrome driven by `CommandActionDescriptor` values so actions (Copy, Actions menu, etc.) stay consistent.

## Clipboard History

Fully implemented view application:

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
- Extensions and remote data
- Exact competitor layouts or branding
- Persisting clipboard history to disk (in-memory for this phase)
- Persisting search history
