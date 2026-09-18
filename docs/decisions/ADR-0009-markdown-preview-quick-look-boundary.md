# ADR-0009: Original Markdown Preview and Finder Quick Look boundary

- Status: Accepted
- Date: 2026-07-18

## Context

Commandly needs a local Markdown reader that works both as a registered launcher application and as
a Finder Quick Look preview. A supplied reference project, Flux Markdown, demonstrates the same
product category, but its application and renderer are dual-licensed under GPL-3.0 and a separate
commercial license. Commandly is currently all-rights-reserved and its project rules require
original implementation, copy, assets, and interface work.

Finder Space-bar previews do not run inside the Commandly application process. They require a
separately sandboxed and signed Quick Look app extension. The host and extension still need one
rendering contract and one non-secret settings format so a document does not change meaning between
the launcher and Finder.

Markdown is untrusted input. Raw HTML, embedded scripts, remote images, local traversal, and
unbounded diagram or image work can turn a convenience preview into a disclosure or resource-abuse
surface.

## Decision

Build **Markdown Preview** as original Commandly code using documented Apple frameworks and a new
dependency-free local package named `MarkdownPreviewKit`.

- `MarkdownPreviewKit` owns Sendable configuration values, supported format identifiers, safe
  Markdown-to-HTML rendering, outline/front-matter results, and the shared preference payload. It
  does not import the Commandly app target.
- The Commandly app target owns user-selected file access, bounded local-image collection, live file
  observation, scroll/recent state, WebKit presentation, HTML/PDF export, printing, and the registered
  launcher application/session.
- A thin embedded Quick Look extension owns only its `QLPreviewingController`, extension WebKit
  presentation, bounded file preparation, and Finder-specific lifecycle. It imports
  `MarkdownPreviewKit`, never the Commandly app target.
- The host and extension share declared non-secret renderer settings through the signed App Group
  `group.com.businessmate360.Commandly`. Markdown text, paths, bookmarks, search terms, scroll
  positions, rendered HTML, and image bytes are not stored in the shared preferences domain.
- The extension remains sandboxed and accepts only the file URL supplied by Quick Look. It receives
  no Downloads-wide access, network entitlement, print entitlement, shell/process authority, or
  temporary home-directory exception.
- File variants are registered under standard Markdown UTIs plus one Commandly-owned UTI for the
  additional plain-text extensions. MDX, R Markdown, Quarto, Markdoc, MDC, Livebook, and similar
  variants are previewed as Markdown text; embedded language runtimes are never executed.
- Rendering emits a strict Content Security Policy. Raw HTML is escaped, scripts from the document
  are never executed, and implicit network loads are blocked. HTTP, HTTPS, and mail links require an
  explicit user action and open through `NSWorkspace` in the host; the Quick Look extension does not
  navigate to local files.
- Local images are pre-inlined only after descriptor-relative no-follow traversal and stable file
  identity checks. Collection is bounded by count, per-image bytes, total bytes, dimensions, frames,
  decoded pixels, and supported image types. Traversal, absolute paths, encoded traversal, symlinks,
  and resources outside the document directory are rejected.
- The initial renderer has no third-party runtime. Standard Markdown, common GFM constructs,
  front matter, source/outline/search presentation, and safe built-in diagram/math representations
  are supported locally. Unsupported or malformed advanced syntax remains visible as source or an
  explicit fallback instead of downloading code or claiming successful rendering.
- Host-only export uses the already-rendered self-contained HTML and WebKit's documented PDF/print
  APIs. The extension exposes no export or print action.
- UI, settings organization, text, symbols, motion, and layout remain original to Commandly. No Flux
  source, TypeScript, CSS, tests, assets, branding, localized copy, bundle identifiers, URL schemes,
  updater configuration, or exact layout is copied or translated.

Any future adoption of Markdown-It, Mermaid, KaTeX, Typst, Vega, Graphviz, Highlight.js, or another
third-party renderer requires a separate dependency, license, maintenance, security, bundle-size,
and performance review. This ADR does not approve those dependencies.

## Consequences

- Commandly can provide one consistent local preview in the launcher and Finder without imposing
  the reference application's GPL license on the repository.
- The Quick Look extension must be embedded, signed, registered by macOS, and enabled by the user.
  A successful unit test or unsigned build cannot prove Finder registration.
- Blocking document HTML and remote resources is intentionally safer than browser-like Markdown
  viewers, but some documents that rely on arbitrary HTML or remote assets will show escaped source
  or placeholders.
- Dependency-free diagram and math support cannot promise exact compatibility with the full Mermaid,
  KaTeX, Typst, Vega, or Graphviz languages. The UI and documentation must preserve the original
  source and identify a fallback rather than misrepresenting it as an exact render.
- App Group configuration requires compatible signing capabilities on the host and extension. A
  failure to read shared preferences falls back to reviewed defaults and does not block previews.
- Real Finder Space-bar, column-pane, signing, extension-conflict, appearance, accessibility, and
  multi-display behavior still require a signed manual macOS test matrix.

## Rejected alternatives

- Copy or rename Flux Markdown: incompatible with Commandly's license and originality boundary
  without a separate commercial license, and still carries third-party obligations.
- Embed Flux as a subprocess or invoke its CLI: fails settings/session integration, creates an
  undeclared external dependency, and conflicts with Commandly's no-arbitrary-process boundary.
- Put shared renderer code in the Commandly app target: a Quick Look extension cannot import the host
  application and would force duplicated behavior.
- Load renderer libraries or images from a CDN: leaks document-view activity, breaks offline use,
  makes output nondeterministic, and expands the extension's authority.
- Register all plain-text files for Quick Look: would overclaim ownership and interfere with unrelated
  source/text preview providers.
- Add broad temporary file, Downloads, network, JIT, or print entitlements preemptively: violates
  least privilege and is unnecessary for the accepted implementation.
