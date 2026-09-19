# Feature gap analysis

Maps Commandly's shipped feature inventory against a comparable macOS utility suite, to decide
what to build next and in what order.

## Provenance and licensing

The comparison target is **Vorssaint** (`vorssaint-utils`), which is licensed **GPL-3.0-or-later**
and carries additional trademark restrictions in its `TRADEMARKS.md`.

Commandly's `LICENSE` currently reads *"All rights reserved. A final open-source or commercial
license has not yet been selected."*

**These licenses are incompatible for code reuse.** Copying or porting GPL-3 source into Commandly
would make Commandly a derivative work, legally requiring it to ship as GPL-3-or-later with
complete corresponding source — which would foreclose the commercial option the LICENSE
deliberately leaves open. Adapting code to a different design system does not change this; a
line-by-line port is still a derivative work. It would also violate `AGENTS.md`:
*"Commandly must remain original. Do not copy ... source code."*

**This document was therefore written clean-room.** It is derived **only** from the reference
project's user-facing `README.md` — that is, from descriptions of *what features do*, which are
facts and not protected expression. No file under its `Sources/` was opened, and no code,
comment, structure, or naming was taken from it.

Any feature built from this document must be implemented independently, in Commandly's own
architecture. Behavioural similarity between utilities is expected and fine; copied expression is
not. If the licensing position changes, revisit this section first.

## The constraint that shapes everything below

A large share of the gap is **not** a matter of effort. Commandly runs **App-Sandboxed**, and:

- [ADR-0008](decisions/ADR-0008-window-switcher-public-api-boundary.md) is **Rejected** — it
  explicitly requires a new accepted decision before a helper or unsandboxed distribution.
- [ADR-0011](decisions/ADR-0011-optional-system-companion.md) accepts an **optional, separately
  signed, non-sandboxed companion** as the route to cross-application window control, menu
  discovery, selected text, and keyboard triggers.
- Window Switcher is already built but **gated off** in the real app for exactly this reason
  (`AppRuntime` passes `includesWindowSwitcher: false`).

So most input-device, window-management, and Dock features are **blocked on companion capability
work**, not on writing the feature. Sequencing must respect that or the work cannot ship.

## Where Commandly already competes

Commandly is not starting from behind. These overlap substantially, and in several cases
Commandly's version is the more developed one:

| Capability | Commandly |
|---|---|
| Launcher / command bar | Launcher with registered applications, typed commands, aliases, tags, inline results |
| Radial menu | **Command Wheel** (profiles, pages, segments, shared execution — ADR-0007) |
| Clipboard history | Clipboard History with capture-time enrichment |
| Shelf | Shelf with an independent window |
| Scratchpad | Productivity Library + Floating Notes |
| Screenshot / recording | Screenshot, annotation, Screen Recording with export review |
| Keep Awake | Keep Awake panel section |
| Volume mixer | Volume Mixer panel section |
| System / Network / Disk / Power / Fans | Dedicated menu-bar panel sections |
| Quick toggles | Quick Toggles panel section |
| Storage cleaning | Storage Cleaner |
| Colour tools | Offline Tools colour formats |
| OCR / image tools | Image Tools (recognition, conversion, background removal) |
| Calculator | CalculatorKit |
| Markdown preview | MarkdownPreviewKit + Quick Look extension |
| AI features | Finder AI, Quick AI, Visual AI, agents, writing tools, translation — **no counterpart in the reference** |

## Genuine gaps

Grouped by what actually blocks them. Effort is rough and assumes clean-room implementation.

### A. Buildable now — sandbox-safe, no companion needed

| Feature | What it does | Effort | Notes |
|---|---|---|---|
| Paste as plain text | One shortcut pastes without formatting; original stays on the clipboard | S | Pure pasteboard work; fits the module system directly |
| Auto-clear clipboard | Clear the system clipboard after a delay, on sleep/lock; saved history untouched | S | Needs care: must not delete owned history — see the deactivate/delete distinction in ADR-0012 |
| Clean URL | Strip tracking parameters from copied links, on demand or automatically | S | Deterministic, testable, no permission |
| Disk image installer | Detect a mounted `.dmg` holding one app, install to Applications, eject | M | Needs user-selected scope; sandbox-compatible with a grant |
| Homebrew manager | Search/install/remove formulae and casks | M | **Check first**: arbitrary process execution conflicts with `AGENTS.md` ("no arbitrary shell execution") and with the sandbox. May need an ADR |
| App updates | List apps with newer versions from published feeds | M–L | Network + catalog matching; privacy review required |
| Network speed test | Throughput measurement in the Network panel | M | Network egress needs an explicit privacy note |
| Threshold alerts | Notifications for sustained CPU, temperature, memory pressure, low disk/battery | M | Notification permission; panel data already exists |
| Menu-bar readouts | Keep selected readings in the menu bar itself | M | Data already collected by the panel sections |
| Bluetooth on sleep | Disable Bluetooth while asleep, restore only what was switched off | S–M | Verify the public API surface before committing |
| Extra brightness / display control | Per-display brightness, on/off, XDR headroom | M–L | Verify which parts are reachable without a helper |

### B. Blocked on the ADR-0011 companion

None of these can ship from the sandboxed app. They need accepted companion capabilities first.

| Feature | Blocking capability |
|---|---|
| **Selected text** *(already surfaced in Settings as "Not implemented")* | Accessibility read of another app's selection |
| Text snippets / expansion | Accessibility text insertion + global key monitoring |
| Super key, key debounce, mouse button shortcuts, extra-click filter | HID event tap |
| Smooth scrolling, pointer acceleration, scroll direction, middle click, side buttons | HID event tap |
| Focus follows mouse | Accessibility window raise |
| App switcher (richer ⌘Tab) | Already built, gated off by ADR-0008 |
| Window layout / edge snapping / drag-to-move | Accessibility window control (partially covered by Window Layouts + companion) |
| Dock preview, Dock clicks | Accessibility + Dock introspection |
| Quit-on-close, ⌘Q/⌘W protection | Event tap + per-app rules |
| Uninstaller | Broad filesystem reach; Full Disk Access |

**Recommendation:** treat "Selected text" as the first companion capability to complete, since it
is already advertised in the UI as missing and ADR-0011 explicitly lists it in scope. Everything
else in this table should queue behind the capability it needs, not be attempted piecemeal.

### C. Large and arguably out of character

| Feature | Assessment |
|---|---|
| **Dynamic Island** | The reference's single largest feature by far. It is a whole second UI surface with its own layout system, gallery, gestures, media/lyrics, calendar, notification mirroring and shortcut editor. This is a product decision, not a backlog item — it would rival the launcher in size. Recommend an explicit decision before any work. |
| Cleaning Mode | Keyboard lock + display blackout; needs an event tap and a strong safety story |
| Messaging-downloads tidying | Narrow, privacy-sensitive; low priority |
| Music app blocker, output switcher, per-app output | Audio routing beyond the current Volume Mixer scope |

## Suggested order

1. **Finish what the UI already promises.** "Selected text" is displayed to users as
   "Not implemented". Either build the companion capability or stop advertising it.
2. **Ship the Group A quick wins** as modules: Paste as plain text, Clean URL, Auto-clear
   clipboard. Each is small, sandbox-safe, testable, and exercises the new module architecture on
   real features rather than on one reference module.
3. **Decide the companion question.** Group B is roughly half the gap and is entirely gated on it.
   Until ADR-0011's capabilities land, that work cannot ship, and Window Switcher stays dark.
4. **Decide Dynamic Island explicitly** rather than letting it arrive as a backlog item.
5. Revisit Group A's larger items (App updates, Homebrew, speed test) once 1–3 are settled.

## Status

- Completed: launcher **Quit Commandly** now performs a real quit through the app's normal
  termination path instead of showing a placeholder.
- Still a placeholder, honestly labelled: launcher **Welcome / walkthrough** row.
- Still advertised as "Not implemented": **Selected text** in System Integration settings.
- Menu-bar panel navbar: **all ten sections are implemented.** `StatusPanelPlaceholderSection`
  exists but is dead code — nothing renders it. It can be deleted or kept for future tabs.
