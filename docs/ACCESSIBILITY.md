# Accessibility

Foundation requirements:

- Placeholder UI exposes a combined accessibility label.
- Title uses header traits.
- Colors use system semantic colors for light/dark contrast.
- Avoid relying on color alone for meaning in future UI.
- Keep keyboard-first interaction as a core design constraint for upcoming launcher work.
- Future features must be VoiceOver-testable before release.

Accessibility review is part of the definition of done for UI changes (`AGENTS.md`).

## Shelf review

Shelf's implemented accessibility surface includes:

- The blue drag-target outline is reinforced by a changing tray/plus icon and a prompt that reports
  how many incoming items will be added. Drop readiness therefore does not depend on color alone.
- The board exposes an accessibility label plus Empty or a semantic count such as 1 image, 2 PDFs,
  or 3 items. The close and compact/detail navigation controls, clipboard import, direct sharing
  targets, action progress, and unavailable references have text labels or values.
- Detail cells expose each file/folder name and selected state, with a hint describing drag-out.
  Selection also has Select All and Clear Selection controls.
- AirDrop, Messages, and Mail targets retain explicit names and hints while displaying their native
  macOS service artwork.
- The initial content reveal uses a subtle fade/scale only when Reduce Motion is off; reduced-motion
  presentations reveal immediately. Board and direct-action transitions follow the same preference.
- The board can be repositioned from any unoccupied surface area without taking precedence over its
  buttons, menus, or staged-item drag sources. An outgoing item drag also keeps the window fixed.
- `⌥⇧Space` and `⌥⇧A` provide system-wide keyboard routes to a new empty or clipboard-seeded Shelf.
- `Space` opens Quick Look, `Tab` switches compact/detail presentation, `⌘C` and `⌘V` export/import
  content, Delete clears, and Escape/`⌘W` closes. Clipboard import accepts file/folder URLs, an image,
  or text. Menus and buttons provide non-drag routes to the remaining actions.

Native drag-and-drop and board repositioning are still pointer-oriented. Clipboard import/export and
action menus are the keyboard/assistive alternatives; this review does not claim that promised-file
drags from every third-party application are supported.
