# Accessibility

Project requirements:

- Screen and panel titles use header traits where they establish structure.
- Colors use system semantic colors for light/dark contrast.
- Do not rely on color alone for meaning.
- Keep keyboard-first interaction as a core design constraint.
- New features must be VoiceOver-testable before release.

Accessibility review is part of the definition of done for UI changes (`AGENTS.md`).

## Shared window and launcher review

- Settings and launcher navigation use labeled monochrome symbols; selected rows expose selected
  state through shape, weight, and accessibility traits rather than color alone.
- Search fields, sidebar toggles, article navigation, launcher results, and footer actions retain
  keyboard and VoiceOver labels. The native Settings titlebar toggle exposes a stable identifier,
  a current Hide/Show label, and help text while the visible scene title remains suppressed.
- Embedded launcher-application search retains its feature-specific label and identifier, clear
  action, Return behavior, arrow-key selection, and Escape handling. Compact glass Back and filter
  controls retain labels, current values, hints, and pointer help even though their visible chrome
  is intentionally quieter.
- Settings and Documentation honor the shared Larger Text preference, and documentation maintains a
  constrained reading measure rather than stretching prose across the window.
- Sidebar, page, and panel transitions suppress nonessential spatial motion when Reduce Motion is
  on; pointer hover feedback is limited to short, non-spatial color fades.
- Native Liquid Glass is reserved for genuinely elevated navigation and transient controls so
  Reduce Transparency and Increased Contrast can use the system treatment; static content stays on
  flat neutral planes separated by spacing and semantic hairlines.

## Command Wheel review

Command Wheel exposes the radial interface as a container with one coherent accessibility element
per visible segment. Each segment reports its title, ordinal position, selected state, availability,
and submenu state; decorative material, rings, guides, and wedge shapes are hidden. The center
cancel/back target has a separate label, hint, and stable identifier. Missing, unavailable, loading,
error, and empty states use words, symbols, opacity, and outline treatment rather than color alone.
Command and application names are intentionally absent from the visible radial ring to prevent
collisions; complete names remain in each segment's accessibility semantics and in Settings.

Keyboard selection is available without pointer movement: Tab/Right Arrow advances clockwise;
Shift-Tab/Left Arrow reverses; Up/Down traverse the same stable order; 1–9 selects a visible slot;
Return activates; and Escape goes back or cancels. Empty and hidden slots are skipped. Toggle mode
takes only temporary panel focus and restores the previously active application after dismissal.
Settings offers labeled buttons and menus for slot assignment, movement, clearing, submenu creation,
profile order, import/export, and reset, so profile editing does not depend on drag-and-drop.

The wheel reads system light/dark appearance, Reduce Motion, Reduce Transparency, and Increased
Contrast; it also follows Commandly's shared text-size preference. Animation never affects hit
testing or the final release sample. Automated semantic checks complement—but do not replace—the
manual VoiceOver, contrast, reduced-motion, and keyboard/focus matrix in
[Command Wheel Testing](COMMAND_WHEEL_TESTING.md).

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
- A newly opened empty board delays its decorative drop prompt for about one second, then uses a
  slow fade with a slight vertical settle only when Reduce Motion is off. The hidden prompt is also
  hidden from assistive technology, while the board continues to expose its Empty value. Incoming
  drop feedback and reduced-motion presentations reveal immediately. Board and direct-action
  transitions follow the same preference.
- The board can be repositioned from any unoccupied surface area without taking precedence over its
  buttons, menus, or staged-item drag sources. An outgoing item drag also keeps the window fixed.
- `⌥⇧Space` and `⌥⇧A` provide system-wide keyboard routes to a new empty or clipboard-seeded Shelf.
- `Space` opens Quick Look, `Tab` switches compact/detail presentation, `⌘C` and `⌘V` export/import
  content, Delete clears, and Escape/`⌘W` closes. Clipboard import accepts file/folder URLs, an image,
  or text. Menus and buttons provide non-drag routes to the remaining actions.

Native drag-and-drop and board repositioning are still pointer-oriented. Clipboard import/export and
action menus are the keyboard/assistive alternatives; this review does not claim that promised-file
drags from every third-party application are supported.
