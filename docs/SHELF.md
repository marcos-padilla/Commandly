# Shelf

Commandly Shelf is a built-in launcher application for temporarily staging files and snippets on a
local floating board. Inspiration comes from the general “temporary shelf” productivity category;
Commandly does not copy Dropover or any other product's branding, assets, or interface.

## Current scope

This phase ships:

- A small floating Shelf board with Apple glass vibrancy, a close control, and a focus-aware
  drag handle; **Drop files here** fades in after the board opens
- Draggable repositioning via the window background; the handle widens briefly while dragging and
  hides when the board loses focus
- Menu bar items **New Shelf** (`⌥⇧Space`) and **New Shelf From Clipboard** (`⌥⇧A`)
- Launcher discovery under the title **Shelf** (opens the same floating board)
- Settings → Applications fields for visibility, empty dismissal, preferred corner, and drop sound
- Preferred-corner placement when a board first opens
- In-app documentation describing only the behavior above

Not implemented yet:

- Drag-and-drop staging of files, images, or text
- Reading the pasteboard into the shelf board
- Playing drop sounds
- Persistence of staged items
- Multiple simultaneous Shelf boards

## Architecture

| Piece | Role |
|-------|------|
| `ShelfApplication` | Registration, configuration schema, launcher open action |
| `ShelfLaunchController` | Routes launcher present requests into `AppRuntime` |
| `ShelfBoardModel` / `ShelfBoardView` | Floating board UI |
| `ShelfWindowConfigurator` | Borderless floating, movable chrome and corner placement |
| `RegisteredApplicationDocumentation.shelf` | In-app article |
| `StatusBarMenu` | Menu-bar entry points |

Settings values are resolved through `LauncherApplicationResolvedSettings` like other applications.
Preferred corner is applied when a board first opens; keep-visible and drop-sound wiring expands with
staging.

## Privacy

The board does not log, upload, or persist clipboard contents, paths, or staged items. Future
staging must remain local, avoid logging protected content, and complete a permission review before
any new macOS capability is requested.
