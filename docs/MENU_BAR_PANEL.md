# Menu Bar Panel

The Commandly status item opens a panel instead of a dropdown menu. A strip of ten tabs sits under
the brand row; the selected tab fills a scrolling body, and Settings and Quit stay in the footer.

## Sections

| Tab | Symbol | State |
|-----|--------|-------|
| Keep Awake | `moon.zzz.fill` | Built |
| Volume Mixer | `slider.horizontal.3` | Built |
| System | `cpu` | Built |
| Network | `network` | Built |
| Disks | `internaldrive` | Built |
| Power | `bolt.fill` | Built |
| Fans | `fanblades.fill` | Built (control depends on the hardware) |
| Utilities | `wrench.and.screwdriver.fill` | Built |
| Controls | `switch.2` | Built |
| Quick Toggles | `togglepower` | Built |

The selected tab is remembered in `statusPanel.selectedSection`.

## Ownership

| Concern | Location |
|---------|----------|
| Panel chrome, navigation, section bodies | `Commandly/Scenes/StatusBar` |
| Keep Awake session, automation, pointer nudge | `Commandly/Services/KeepAwake` |
| Volume mixer, taps, device routing | `Commandly/Services/VolumeMixer` |
| System, network, disk, and power readings | `Commandly/Services/SystemMetrics` |
| Fan readings and control | `Commandly/Services/FanControl` |
| Quick toggle rows and their system adapters | `Commandly/Services/QuickToggles` |
| Controls rows and the features behind them | `Commandly/Services/Controls` |
| Sleep, power, display, and pointer contracts | `Packages/Sources/Infrastructure/SleepPrevention.swift` |

### Section height

The panel's window sizes itself to its content, so it proposes no definite height to what it
contains. A plain `ScrollView` is greedy in that situation and collapses to nothing, which leaves
a section header sitting directly on the footer with the whole body missing. `MeasuredScrollView`
measures its content and applies that height explicitly, capped against the screen the menu bar is
on. Each section also carries an `estimatedHeight` that stands in until the first measurement
lands, so a tab never flashes at zero.

Every monitor is `@Observable @MainActor` and samples only while its section is on screen, through
`addObserver()` / `removeObserver()`. The volume mixer is the one exception: it starts at launch
when — and only when — it has a saved per-app volume, a saved route, or a preference that reaches
outside the panel, because a tap it already owes an app must not wait for the panel to open.

## Keep Awake

A session holds IOKit power assertions: one against idle system sleep, and one against idle display
sleep unless **Allow the display to sleep** is on. It can run for a fixed duration or until it is
switched off, and a timed session can be extended in place.

Automation starts a session on its own while an external display is attached, while the Mac is on
wall power, or while a chosen app is running. Automation never cuts short a session the user
started; only its own session ends when the last condition stops matching. Stopping by hand
suppresses automation until its conditions clear, so switching off does not bounce straight back on.

**Pause while the screen is locked** drops the assertions on lock and takes them back on unlock.
**Stop on low battery** ends a session at a chosen percentage while on battery. **Move pointer
slightly** nudges the pointer one point on an interval and needs Accessibility.

While a session runs, the menu bar glyph becomes the chosen active icon in the chosen tint.

Closed-lid operation is not offered: it requires `pmset disablesleep` through an administrator
shell, which App Sandbox does not permit.

## Volume Mixer

Output, alert output, and microphone each have a device picker; the system output also has a volume
slider and mute. Below them is one row per app holding an audio connection, with its own volume and
output.

Per-app volume uses CoreAudio process taps (macOS 14.4 and later). A muted tap removes the app's
sound from its real output and a private aggregate device re-renders it at the chosen gain, through
a lookahead peak limiter so a boost above 100% gets louder without distorting. An app on the system
default output at 100% is never tapped at all, and a tap is only ever created for an app the user
actually adjusted.

Options: hide inactive apps, lower the speakers when headphones disconnect, turn the volume keys
into macOS' fine step, and cycle the system output on a shortcut.

## Fans

Fan speed is read from the System Management Controller. Where the controller also exposes the keys
that set a speed, the tab offers Manual and Curve modes.

Control is a borrowed responsibility. It returns to macOS whenever Commandly can no longer judge the
machine's heat: readings stop, the chip reaches the handback temperature, macOS reports thermal
pressure, the Mac sleeps, or Commandly quits.

## Utilities

The actions the dropdown menu used to list — Open Commandly, Window Switcher, Documentation,
Settings, New Shelf, New Shelf From Clipboard, and the debug-only onboarding restart — live here
with the same shortcuts.

## Quick Toggles

Ten everyday macOS switches, each showing the real system state rather than a remembered
intent. Right-clicking a row hides it or opens the System Settings page behind it; hidden rows
come back from the footer, and hiding every row is refused so the tab is never empty.

| Row | How it acts |
|-----|-------------|
| Switch to light/dark mode | One fixed Apple Event to System Events |
| Keyboard light | Level read from the IO registry; changed by posting the illumination keys |
| Mute microphone | The existing `MicrophoneControlling` Core Audio service |
| Empty the Trash | One fixed Apple Event to the Finder, behind an in-row confirmation |
| Eject all disks | The Disks tab's own `DiskMetricsMonitor` |
| Show hidden files | Not available under App Sandbox |
| Hide desktop icons | Not available under App Sandbox |
| Lock the screen | Posts ⌃⌘Q |
| Turn off the display | Not available under App Sandbox |
| Start the screen saver | Opens `ScreenSaverEngine.app` |

The row title names the change it would make — "Switch to light mode" while the Mac is dark,
"Unmute microphone" while it is muted — so a row never reads as a status light.

Three rows cannot act from a sandboxed build. They stay visible, say exactly why, and offer the
System Settings page that can make the change where one exists. Writing the Finder's own
preferences and putting the display to sleep both need authority the sandbox withholds; the
System Companion is the architectural route if those rows should ever act, and that is a separate
decision from this tab.

Rows that post keys — the keyboard light and the lock — need Accessibility and say so in place of
their caption until it is granted.

## Controls

Three collapsible groups — Windows, Mouse and Keyboard, Files — each showing how many of its
switchable rows are on. A sub-option such as **Show ⌘Tab with large icons** is indented under its
parent and only appears while that parent is on.

Working rows read and write the same storage the rest of the app uses, so a switch here and the
same setting in Settings can never disagree:

| Row | Backed by |
|-----|-----------|
| App switcher | The registry's enabled flag for `windows.switcher` |
| Show ⌘Tab with large icons | That application's `replaceCommandTab` variable |
| Dock Preview | Its `dockPreviewsEnabled` variable |
| Radial menu | `CommandWheelProfileStore.isEnabled` |
| Text snippets | `KeyboardTriggerSettingsModel` |
| Highlight Mode | The registry's enabled flag for `highlight.mode` |
| Shelf | The registry's enabled flag for `shelf.board` |

**Quit on close** is shown as configured per application, because Commandly's auto-quit is a list
of applications rather than one global switch.

The remaining rows — maximize windows, the three Dock-click behaviors, inverted scrolling,
focus follows mouse, mouse acceleration, side-button navigation, key debounce, three-finger middle
click, mouse button shortcuts, the Super key, and Finder cut & paste — have no implementation in
Commandly yet. They stay listed, with their switch disabled and a caption that says so, so the tab
shows the whole shape of the feature without pretending any of it works.
