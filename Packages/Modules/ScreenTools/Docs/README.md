# Screen Tools module

Target: `ScreenToolsModule` · Module ID: `screen-tools` · Status: shipping

## What it does

| Command ID | Meaning | Mode | AI |
|------------|---------|------|-----|
| `screen.tools` | Open the Screen Tools surface | requiresUserInterface | hidden |
| `screen.tools.copy-text` | Select an area; copy the text recognized in it | requiresUserInterface | hidden |
| `screen.tools.pick-color` | Sample a pixel; copy its color | requiresUserInterface | hidden |

## Composed, not reinvented

Both operations are built from contracts the app already owned:

- `ScreenshotCapturing` — the same region selector the Screenshot application uses
- `ImageRecognizing` — the same on-device Vision recognizer Image Tools uses
- `PasteboardAccessing` — the shared clipboard contract
- `ScreenColorSampling` — a new narrow protocol over `NSColorSampler`

No new capture stack and no second recognizer were written.

## Privacy

Recognition runs on this Mac. Recognized text goes to the clipboard and **nowhere else** — it is
deliberately excluded from the command's result, so a caller cannot read private screen content
out of an outcome. The result carries a character count and a truncation flag only, and a test
pins that a recognized secret never appears in the message or output.

## Permissions

- **Copy text** needs Screen Recording. It is declared as a capability requirement, so the host
  reports the module as `permissionRequired` from cached state rather than prompting.
- **Pick color** needs no permission: `NSColorSampler` is driven by the user pointing at a pixel.

## Settings

| Variable | Kind | Default |
|----------|------|---------|
| `screenColorFormat` | selection (Hex, Hex+alpha, RGB, RGBA, HSL, SwiftUI) | Hex |
| `joinRecognizedLines` | toggle | off |

An unknown stored format falls back to Hex rather than failing.

## AI exposure review

**No command is exposed.** Both require the user to point at something on screen, so a model
could never complete them, and `copy-text` reads arbitrary private screen content. All three stay
`.hidden`, pinned by a test.
