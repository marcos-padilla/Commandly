# Clipboard Tools module

Target: `ClipboardToolsModule` · Module ID: `clipboard-tools` · Status: shipping

## What it does

Three clipboard operations plus optional automatic clearing:

| Command ID | Meaning | Mode | AI |
|------------|---------|------|-----|
| `clipboard.tools` | Open the Clipboard Tools surface | requiresUserInterface | hidden |
| `clipboard.tools.plain-text` | Replace rich clipboard text with its plain text | direct | hidden |
| `clipboard.tools.clean-url` | Remove tracking parameters from a copied link | direct | hidden |
| `clipboard.tools.clear` | Empty the system clipboard now | direct | hidden |

## Why "plain text" does not paste for you

Commandly is sandboxed and does not synthesise keystrokes into other applications. This command
therefore **prepares the clipboard** and the user pastes normally. Documenting this plainly is
deliberate: a command that claimed to paste but did not would be a lie in the UI.

Actually pasting would need the ADR-0011 companion. See `docs/FEATURE_GAP_ANALYSIS.md`.

## URL cleaning is deliberately conservative

A parameter is stripped only when it is a well-known analytics tag (`utm_*`, `gclid`, `fbclid`,
`mc_eid`, …). Anything unrecognised is kept, because a wrongly stripped parameter can break a link
— a search query, a page number, a signed token — which is far worse than leaving one tracker
behind. `ref` is **not** stripped by default for exactly this reason; users who want it can add it
under "Also remove these parameters".

Only a single absolute `http`/`https` URL is cleaned. Prose containing a link is left alone.

## Settings

| Variable | Kind | Default |
|----------|------|---------|
| `cleanLinksAutomatically` | toggle | off |
| `additionalTrackingParameters` | text | empty |
| `autoClearIdleSeconds` | integer (0–86400) | 0 (off) |
| `autoClearOnSystemSleep` | toggle | off |
| `autoClearOnDisplaySleep` | toggle | off |
| `autoClearOnScreenLock` | toggle | off |

Everything is off by default, so an unconfigured module clears nothing.

## Capabilities

None. No macOS permission is required.

## Storage

The module persists nothing of its own.

**Clearing the clipboard never deletes Clipboard History entries.** Clearing what is currently on
the clipboard and deleting saved items are separate decisions, and only the second destroys data
the user asked Commandly to keep. A test pins this.

## AI exposure review

**No command is exposed to AI.** These commands read and rewrite whatever the user copied, which
may be a password, a private link, or other sensitive text. There is no compelling automation case
that outweighs that, so all four stay `.hidden`. A test pins the whole set.

## Activation

`activationPolicy: .atLaunchWhenEnabled` — auto-clear must already be running before the user
copies something, so the module cannot wait for a launcher surface to be opened.
