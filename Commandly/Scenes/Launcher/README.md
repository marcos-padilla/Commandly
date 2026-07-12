# Launcher Scene

Primary Commandly command palette: a floating, draggable, scrollable panel summoned by **⌥Space** or **Open Commandly** in the menu bar.

## Search

The main field is the primary entry point for discovering and running work:

- Focus stays on the search field (not the parent window chrome) so typing always updates the query
- Ranked results via SearchKit providers: **commands**, **applications**, and honest **placeholders**
- Calculator-shaped queries are evaluated via **CalculatorKit** in parallel and pinned in a dedicated **Calculator** two-pane card above other results
- `CompositeSearchService` merges scores (prefix > keyword > contains) and cancels in-flight work on each keystroke
- Ghost autocomplete for the best prefix match; **Tab** accepts, **Return** confirms the selected row
- Installed apps are enumerated from standard Applications folders and opened through `ApplicationOpening` (full catalog; Applications section appears below Commands)
- Application rows show each app’s real icon from its bundle via `NSWorkspace`

## Command system

Built-in commands register through `CommandCatalog` / `LauncherCommandRegistering`:

- `CommandManifest` (CommandKit) — id, title, icon, mode (`.action` | `.view`), keywords, default footer actions
- Action mode — runs immediately (example: Open Settings)
- View mode — pushes a command surface with its own search/list/preview and footer actions (example: Clipboard History)

Footer chrome is driven by `CommandActionDescriptor` values from the active surface so new commands keep a consistent UI.

## Clipboard History

Fully implemented first command surface:

- Monitors the system pasteboard in the **background** (text, images, file URLs) without activating Commandly or raising windows
- Search + type filter
- Split list / preview / metadata (image pasteboard items and image file URLs show a detail preview)
- Copy, Delete, Clear History via footer + Actions menu; hover Copy on list rows
- Re-copy write-backs are not recorded as new history entries
- Never logs clipboard contents

Clipboard capture updates the in-memory store only. The launcher must not re-raise on store changes (`LauncherWindowConfigurator` applies chrome without calling `BringHostingWindowToFront`).

## Non-goals (for now)

- AI / natural-language Q&A
- File search, extensions, remote data
- Exact competitor layouts or branding
- Persisting clipboard history to disk (in-memory for this phase)
- Persisting search history
