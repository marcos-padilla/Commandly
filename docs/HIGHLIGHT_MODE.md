# Highlight Mode

Highlight Mode makes pointer and keyboard activity visible during presentations, tutorials, and
screen recordings. It is a registered Commandly application with an app-lifetime native service.

## User behavior

- Open Highlight Mode from launcher search to review its state and turn it on or off.
- Assign a conflict-safe global shortcut in Settings → Applications → Highlight Mode. That shortcut
  toggles the mode directly without presenting the Commandly launcher over the current screen.
- Configure click rings, keyboard shortcuts, typed-text feedback, cursor spotlight, spotlight size,
  accent color, and feedback duration in the same generic Applications inspector.
- Configuration changes apply to an active session.

The overlay is transparent and click-through, joins every Space, and does not activate Commandly.
One panel is maintained per display. Click feedback is drawn on the display where the click occurred;
keyboard feedback follows the display containing the pointer.

## Permission and privacy

Global event observation requires macOS Accessibility access. The service checks and requests that
permission only after an explicit enable action. If access is denied or the event monitor cannot be
installed, no overlay remains active and the UI provides a recovery route to Permissions settings.

Typed characters, shortcuts, and click positions are transient in-memory render state. They are not
persisted, logged, uploaded, copied to the pasteboard, or included in command invocation history.
The shared command history records only the Highlight Mode command identifier, invocation source,
outcome, record identifier, and timestamp. Users should turn off typed-text feedback before entering
passwords or other sensitive information.

Highlight Mode does not record the screen, capture audio, synthesize input, or require Screen
Recording permission.

## Architecture

- `Infrastructure/HighlightMode.swift` owns the narrow configuration, state, error, and service
  contract plus an in-memory test implementation.
- `NativeHighlightModeService` owns Accessibility gating, global/local AppKit event monitors, and
  click-through panels.
- `HighlightModeApplication` declares discovery, generic configuration, documentation, launcher UI,
  and background invocation behavior.
- `AppRuntime` owns the production service lifetime, applies live configuration updates, stops the
  service at termination, and sends background hotkeys through the shared command coordinator.

No third-party dependency is used.

## Performance

An enabled but otherwise idle overlay has no display-linked redraw loop. Spotlight movement
invalidates the static canvas only when pointer events arrive, keyboard feedback expires through a
one-shot timer, and the 60 Hz animation timeline exists only while a click pulse is visible.
Stopping the service removes event monitors, panels, timers, and transient render state.

## Verification

Automated tests use `InMemoryHighlightModeService` and never request a real permission or observe real
input. Manual verification should cover permission grant and denial, hotkey toggling without launcher
presentation, click-through behavior, multiple displays and Spaces, full-screen presentation apps,
typing/shortcut rendering, live configuration changes, and teardown at app termination.
