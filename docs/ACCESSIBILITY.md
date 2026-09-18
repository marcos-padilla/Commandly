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
- Root tool, typed-command, Clipboard History, and Files rows use the same arrow-key/Return
  interaction as other launcher results. Section titles retain header traits, and each row announces
  its title, available subtitle, and Tool, Command, Clipboard, or File value rather than relying on
  its symbol or color.
- The Applications settings hierarchy exposes labeled Expand/Collapse controls for application
  tools, selected state and kind on each row, and a separate labeled enable switch. Built-in tag
  capsules announce that they are locked; every user tag has a named Remove action; Add Tag,
  shortcut recording, conflict warnings, and Restore Defaults remain labeled controls. Typed-command
  syntax and examples are combined into coherent read-only accessibility elements and are not
  presented as shortcut controls.
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

Root Return submission is tied to the exact search request that produced the selected result.
When search is still pending, Return waits for current command/application/calculator results;
an empty fast result also waits for file results. Editing the query (including changing it away
and back), Escape, navigation, dismissal, and explicit selection changes cancel the queued press.
Repeated presses share one pending or executing operation. No old result is executed while the
latest search is unresolved. `LauncherConfirmationTests` exercises these boundaries with suspended
dependencies and explicit continuations; native keyboard behavior also requires runtime review.

Shared searchable action/filter menus provide Up/Down movement, visible selection, Return
activation, and a labeled empty state. Disabled and filtered-out actions cannot be keyboard
activated. In the launcher, Escape first dismisses an expanded filter before feature navigation;
keyboard dismissal restores the preceding field, while an outside click keeps its new focus.
Action-panel dismissal requests root search focus. Applied filter choices also carry a checkmark
and selected accessibility trait, independent of the current keyboard highlight. Increased
Contrast adds an outline to selected root results and menu rows.

Settings supports Command-F to reveal and focus its sidebar search, Up/Down to navigate matching
panes, Return to open a match, and Escape to clear the filter. Density changes honor Reduce
Motion. `LauncherMenuSelectionTests` covers filtered/enabled selection, wraparound, empty
activation, and per-launcher menu-dismissal ownership. These deterministic checks do not replace
manual VoiceOver, Full Keyboard Access, focus-restoration, and light/dark/contrast runtime review.

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
- New Shelf and New Shelf from Clipboard own default `⌥⇧Space` and `⌥⇧A` system-wide keyboard
  routes. They appear as application tools in Settings, where either shortcut can be replaced or
  cleared with the same labeled recorder and conflict feedback as other tools.
- `Space` opens Quick Look, `Tab` switches compact/detail presentation, `⌘C` and `⌘V` export/import
  content, Delete clears, and Escape/`⌘W` closes. Clipboard import accepts file/folder URLs, an image,
  or text. Menus and buttons provide non-drag routes to the remaining actions.

Native drag-and-drop and board repositioning are still pointer-oriented. Clipboard import/export and
action menus are the keyboard/assistive alternatives; this review does not claim that promised-file
drags from every third-party application are supported.

## Storage Cleaner review

Storage Cleaner uses a fixed sidebar/detail layout with category rows that expose selected state,
candidate count, and size. Candidate rows expose name, category, parent path, byte size, keyboard
focus, and whether the item is selected for cleanup. Duplicate rows include visible **Keep** or
**Remove** text in addition to a checkmark and tint, so the one-copy safety rule does not depend on
color.

The search field retains Up/Down candidate navigation and Return toggles the focused item.
Command-Return opens the exact destructive confirmation, Command-K exposes refresh, duplicate
folder selection, recommended selection, and clearing, and Escape cancels confirmation, clears
search, or returns to launcher search. The native folder picker and confirmation remain reachable
with Full Keyboard Access. Loading, empty, partial, failure, and completion states use text and
symbols, and placeholder rows are hidden from assistive technology.

Automated model tests cover selection semantics and the duplicate keep invariant. A signed release
still requires manual VoiceOver reading-order, larger-text, Increased Contrast, Reduce
Transparency, Full Keyboard Access, large/partial scan, inaccessible Trash item, and alternate kept
duplicate review.

## Window Switcher review

Window Switcher has an accessibility design prototype, not a released accessibility surface. The
sandboxed production app must keep the feature unregistered and disabled because Apple's
[App Sandbox guidance](https://developer.apple.com/documentation/security/protecting-user-data-with-app-sandbox)
lists the needed cross-application assistive Accessibility and termination behaviors as
incompatible. Passing semantic tests against the prototype does not make its panel reachable to
users or validate a privileged system integration.

The prototype represents each discovered window as one coherent accessibility element labeled with
the application name, title or an explicit Untitled fallback, minimized/hidden state, and selection
state. A thumbnail is decorative and never the only source of identity or state. Application icons,
badges, outlines, and dimming supplement text and accessibility values; they do not make color the
only signal. An unavailable action produces an accessible explanation instead of silently failing.

The modeled panel provides type-to-search, arrow selection, Tab/Shift-Tab cycling, Return activation,
and Escape cancellation. Hold and Cycle would commit on modifier release. Modeled keyboard actions
include Close, Minimize/Restore, Full Screen, Zoom, Center, half-screen placement, and graceful Quit.
These routes, the nonactivating panel's focus behavior, and More/context-menu reachability all require
explicit VoiceOver and Full Keyboard Access review against a future authorized signed runtime.

Dock hover is only a modeled pointer entry point. Pin/Unpin has a changing label and would keep the
prototype panel available without locking the system Dock. It is not a current product workflow, and
there is no registered/cycling alternative to claim as accessible parity today.

The prototype reads Reduce Motion and Reduce Transparency; Reduced Motion removes selection
animation and Reduce Transparency uses an opaque semantic window background. This is deterministic
foundation coverage only. Larger Text, Increased Contrast, thumbnail absence, focus restoration,
permission recovery, and semantic order still require the future runtime matrix.

After a new ADR authorizes a privileged helper or non-sandboxed distribution, manual release review
must cover VoiceOver with Option-Tab and any opt-in Command-Tab replacement, Full Keyboard Access,
key repeat, shortcut cancellation/focus restoration, titleless and minimized windows, permission
denial/revocation, multiple displays, full-screen Spaces, and Dock auto-hide/orientation/
magnification. Public Accessibility hierarchies can change between macOS releases, so even a tested
future build cannot claim universal Dock-hover or Command-Tab interception.

## Markdown Preview review

The shared command-surface action panel now connects Command-K and the footer Actions button to
one searchable list. Arrow navigation skips disabled entries; Return dispatches only an enabled
current action, and Escape dismisses before leaving the application. Input focus is restored to the
previous attached field on dismissal. File Search and Markdown Preview retain their custom panels.
This repair followed native Color Tools acceptance, which exposed an unwired menu-state binding.
Its new native acceptance and VoiceOver traversal are tracked in the video ledger.

Markdown Preview exposes named controls for file selection, reload, outline visibility, local
search, search options, previous/next match, source mode, zoom, automatic reload, export, print, and
document actions. Loading, ready, warning, truncation, and failure states use text and symbols as
well as color. Outline rows announce their heading text, level, and selected state; the rendered
document and escaped source have distinct accessibility labels.

The host provides keyboard routes for choosing a file, search, reload, source mode, zoom, HTML/PDF
export, action search, and Escape dismissal. Drag-and-drop is supplementary to the file picker.
Rendering follows system light/dark appearance when configured, uses semantic contrast, preserves
selectable text, and does not require animation to understand state. The renderer supplies heading,
table, list, quote, alert, details, link, and code semantics rather than flattening the document into
an image.

Finder owns the outer Quick Look window and may reserve keys or alter focus routing, so automated
host tests cannot validate the extension end to end. A signed release must manually cover VoiceOver,
Full Keyboard Access, larger text, Increased Contrast, Reduce Motion, light/dark appearance, narrow
Finder panes, source/code horizontal movement, outline order, and repeated Space-bar previews before
the Finder accessibility behavior is claimed as verified.

## GIF search and System Settings commands

GIF results announce distinct titles, creators/sources, and descriptions. The list and animated
preview use remaining launcher height; native compact/light/larger-text acceptance passed. Keyboard
search, selection, copy, searchable Actions, Escape, and native Save cancellation passed with
generated media. The connection sheet scrolls so disclosures remain readable with larger text;
its final native recheck and actual VoiceOver traversal remain separate. Reduce Motion uses a still
preview with disabled playback controls; this behavior has deterministic coverage.

The System Settings catalog uses shared search/list/detail composition, explicit destination names,
keyboard actions, and scrollable details. Native page navigation and keyboard/compact acceptance
are tracked separately from metadata and injected-workspace tests.

## Slack Emoji

The search field, workspace picker, result list, secure connection field, and action controls use
native labels. Return copies the selected shortcode; Command–Shift–C copies its original image.
Alias and unavailable-preview explanations remain visible. The connection sheet scrolls under fixed
Done/Cancel controls, and Reduce Motion uses a still preview. Native keyboard, compact/large-text,
light/dark, and VoiceOver acceptance are pending integration checks; see [Slack Emoji](SLACK_EMOJI.md).

## Finder Path

Finder Path uses a scrollable explanation, labeled controls, a Return primary action, searchable
Command-K actions and Escape cancellation/back navigation. Denial keeps the recovery path visible.
Success and errors are generic status text; the path itself is not displayed in the launcher. Opening
the application does not prompt. The separate Allow Finder Access and Copy action follows a visible
explanation. Generated and real Finder native keyboard/compact/VoiceOver checks remain pending.
