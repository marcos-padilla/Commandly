# Launcher Scene

Primary Commandly command palette: a floating, draggable, scrollable panel summoned by **⌥Space** or **Open Commandly** in the menu bar.

## Current scope (frontend)

- Glass / vibrancy panel with search, sectioned placeholder results, footer actions
- Keyboard: ↑↓ to move, ↵ to confirm, Esc to close; ⌥Space toggles visibility
- Placeholder actions only — most rows show an honest “not implemented yet” status
- **Open Settings** is wired; other commands are stubs

## Non-goals (for now)

- Real app / file / clipboard search
- Ranking, extensions, or remote data
- Exact competitor layouts or branding

## Ownership

| File | Role |
|------|------|
| `LauncherRootView` | Panel composition |
| `LauncherViewModel` | Query, selection, confirm/dismiss |
| `LauncherModels` | Placeholder catalog |
| `Components/` | Search, rows, footer, window chrome |
