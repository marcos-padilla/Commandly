# Markdown Preview

Markdown Preview is Commandly's original, keyboard-first Markdown reader. It is available as a
registered launcher application and through an embedded Finder Quick Look extension. Both surfaces
use the same dependency-free renderer and non-secret configuration model; neither uploads document
content or executes code from a document.

The implementation is clean-room Commandly work. It does not copy the supplied Flux Markdown
project's GPL-licensed source, renderer, tests, assets, branding, copy, or exact interface. See
[ADR-0009](decisions/ADR-0009-markdown-preview-quick-look-boundary.md).

## Use it in Commandly

1. Open Commandly and launch **Markdown Preview**.
2. Choose a supported Markdown file or drop one onto the viewer.
3. Read the rendered document, open the outline, search within the preview, or switch to escaped
   source.
4. Reload manually or leave automatic reload enabled while another editor changes the file.
5. Export a self-contained HTML file or a PDF from the explicit export actions.

The active launcher session owns its file access and cancels loading, observation, search, and export
work when it closes. Choosing a newer file invalidates older in-flight results so a slow read cannot
replace the current document.

## Use it in Finder

After installing a signed Commandly build and enabling its Quick Look extension in **System Settings
→ General → Login Items & Extensions → Quick Look**, select a supported file in Finder and press
Space. Finder may also use the extension in its preview or column pane.

Quick Look supplies the selected file URL to the sandboxed extension. The extension does not scan a
folder, request Files and Folders permission, retain the file descriptor after preparation, or gain
general Downloads access. Documents are bounded before rendering so Finder remains responsive.

Extension registration is controlled by macOS. Rebuilding or replacing Commandly can require Finder
to rediscover the extension, and another installed preview provider can win a UTI conflict. Commandly
must not report Finder integration as verified until a signed build passes the manual matrix below.

## Supported files

The viewer accepts these extensions as Markdown text:

- `.md`, `.markdown`, `.mdown`, `.mdwn`, `.mkd`, `.mkdn`, and `.mkdown`
- `.mdx`, `.rmd`, `.qmd`, `.mdoc`, and `.mdc`
- `.mmd` and `.livemd`

MDX JSX, R/Quarto chunks, Markdoc directives, and Livebook code are displayed as Markdown/source;
Commandly never evaluates them. A standalone `.mmd` file is treated as diagram source while keeping
the original text available.

## Rendering

The local renderer covers headings, paragraphs, emphasis, strong text, inline and reference-style
links, images, lists, fenced code, blockquotes, tables, task lists, strikethrough, alerts, YAML front
matter, emoji shortcodes, footnotes, mark/subscript/superscript forms, outline anchors,
light/dark/system appearance, print styles, source presentation, line gutters, and right-to-left
document direction.

Diagram and math fences receive safe built-in visual representations and preserve the original
source. This dependency-free implementation does not claim exact language compatibility with the
complete Mermaid, KaTeX, Typst, Vega/Vega-Lite, or Graphviz engines. Invalid or unsupported input is
shown as an explicit fallback rather than hidden or executed.

Raw HTML and embedded scripts are escaped. Remote images and implicit network resources are blocked.
Local images can be shown when macOS grants the active preview access, they resolve beneath the
selected document's directory, and they pass all bounds:

- at most 32 images;
- at most 2 MiB per image;
- at most 8 MiB total;
- at most 16,384 pixels in either dimension and 64 million pixels per frame;
- at most 256 frames, 128 million decoded pixels per image, and 256 million decoded pixels total;
- PNG, JPEG, GIF, and WebP only;
- descriptor-relative no-follow traversal only: no absolute path, parent traversal, encoded
  traversal, or symlink component.

## Search, outline, and reading state

Search is local to the active WebKit document. It supports next/previous navigation and can apply
case-sensitive, whole-word, or a deliberately restricted safe regular-expression subset without
persisting the query. The outline follows h1–h6 headings and scrolls to stable, deduplicated anchors.

Zoom is bounded from 0.5× through 3×. Scroll memory uses a one-way digest rather than a plaintext
path and is capped to a bounded recent set. The shared Quick Look preferences domain does not contain
scroll positions or recent-file information.

## Settings

Open **Settings → Applications → Markdown Preview**. The settings are declared by the registered
application schema, persist as non-secret values, and are mirrored to the Quick Look extension.

| Section | Setting | Default | Effect |
|---------|---------|---------|--------|
| Appearance | Preview appearance | System | Follow macOS, Light, or Dark |
| Typography | Base font size | 14 px | Reading size from 12–24 px |
| Typography | Finder preview font size | 13 px | Compact Finder size from 10–24 px |
| Typography | Code theme | Default | Default, GitHub, Monokai, or Atom One Dark styling |
| Rendering | Mermaid diagrams | On | Render supported Mermaid-shaped fences locally |
| Rendering | Math | On | Render supported inline/block math locally |
| Rendering | Emoji shortcodes | On | Replace supported `:name:` shortcodes |
| Rendering | Typst math | On | Render supported Typst-shaped math locally |
| Rendering | Collapse blockquotes | Off | Start ordinary quotes and alerts collapsed |
| Rendering | Show line numbers | Off | Show source/code gutters |
| Navigation | Show outline | On | Open the document outline initially |
| Navigation | Automatic reload | On | Observe the active file for external edits |
| Navigation | Remember scroll position | On | Restore bounded, digest-keyed reading state |
| Navigation | Default view | Preview | Open in rendered preview or escaped source |
| Navigation | Default zoom | 1× | Initial zoom from 0.5×–3× |

Commandly does not add a feature-specific interface-language setting. Markdown Preview follows
Commandly and macOS language behavior instead of creating a second application-level locale.

## Keyboard actions

| Keys | Action |
|------|--------|
| `Return` | Choose a file when the viewer is empty |
| `⌘R` | Reload the active file |
| `⌘F` | Focus in-document search |
| `⇧⌘M` | Switch between preview and source |
| `⌘+` / `⌘-` / `⌘0` | Zoom in, out, or reset |
| `⇧⌘E` | Export self-contained HTML |
| `⇧⌘P` | Export PDF |
| `Escape` | Close search/actions or return to the launcher |

Finder can reserve keyboard events while Quick Look is active, so its Space-bar preview must remain
usable without relying on these shortcuts.

## Export

HTML export writes the already-sanitized, self-contained rendered document. Allowed local images are
data URLs; remote resources and scripts are not added. PDF export uses WebKit's documented PDF
capture path and a user-selected destination. Cancellation is normal and write failures are reported
without claiming a file was saved.

Exports are host-only. The Quick Look extension has no print or export entitlement and exposes no
write action.

## Privacy and security

- No Markdown text, rendered HTML, image bytes, path, link destination, search query, or outline is
  logged or uploaded.
- File access begins only after an explicit picker/drop or a Quick Look request.
- Raw document HTML/scripts do not execute; the rendered page has a strict Content Security Policy.
- Network loads are blocked. Explicit supported links open outside the launcher through the reviewed
  workspace boundary.
- App Group preferences contain only declared renderer settings.
- The extension is read-only and sandboxed. It has no shell, process, AI, clipboard, updater, broad
  filesystem, or ambient network authority.

Markdown itself requires no new TCC permission. Enabling a Quick Look extension is an explicit macOS
extension-management choice, not a Files and Folders permission prompt.

## Accessibility

The launcher viewer exposes named controls for file selection, reload, outline, search, source mode,
zoom, export, and document state. Outline rows include heading level in their accessibility value.
Source and rendered content remain selectable, keyboard reachable, and useful without color.
Reduced Motion disables smooth scrolling; Increased Contrast and Reduce Transparency use the
existing Commandly surface tokens and native WebKit text rendering.

Quick Look must be reviewed with VoiceOver and Full Keyboard Access because Finder owns the outer
window and may change focus routing.

## Performance limits

- Quick Look reads at most 500 KiB of Markdown and truncates at a line boundary with a visible note.
- Host reads, rendering, image collection, and export run away from the main actor where the API
  permits and honor cancellation.
- Local image byte, dimension, frame, and decoded-pixel bounds prevent a document from expanding
  into unbounded memory.
- File-system events are coalesced and stale render generations are discarded.
- The WebKit data store is nonpersistent; closing a session releases its page and observation state.

## Manual Finder matrix

Run on a signed local build and record macOS/build/signing details:

| Area | Required cases |
|------|----------------|
| Registration | Clean install, upgrade, extension disabled/enabled, another Markdown preview provider installed, Finder relaunch |
| Surfaces | Space-bar panel, Finder preview pane, column preview, narrow/short sizes, resize, repeated open/close |
| Formats | Every registered extension, UTF-8/BOM/UTF-16, empty, malformed, and over-500-KiB documents |
| Resources | Valid sibling/subfolder images, spaces/unicode, missing image, oversized image, traversal, encoded traversal, symlink escape, remote URL |
| Rendering | GFM, front matter, alerts, code, math/diagram fallbacks, source mode, outline, RTL, light/dark/system |
| Settings | Change every mirrored option, reopen Quick Look, reset defaults, unavailable App Group fallback |
| Lifecycle | Edit, atomic replace, rename, delete, rapid changes, WebKit process termination, extension revocation |
| Accessibility | VoiceOver names/order, keyboard-only use, Full Keyboard Access, Larger Text, Reduce Motion, Increased Contrast |
| Performance | Cold/warm preview, large bounded file, image limits, repeated sessions, memory release, idle CPU |

Unit and build verification cover the shared renderer and extension structure, but cannot replace
this signed Finder test.
