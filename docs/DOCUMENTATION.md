# In-App Documentation

Commandly ships a private, searchable documentation browser as a standard macOS window. Open it
from the Settings gear menu in the launcher's bottom-right corner or the menu-bar item by choosing
**Documentation**. The keyboard shortcut is **Command-?**. The browser describes implemented
behavior only; it must not present roadmap items or placeholders as available features.

## Architecture

Documentation has two typed sources that share one renderer:

1. Every registered `LauncherApplication` contributes a `LauncherApplicationDocumentation` value
   through its `LauncherApplicationDefinition`.
2. `CoreDocumentationCatalog` contributes articles for app-wide behavior that is not a registered
   launcher application, including launcher navigation, installed macOS applications, Calculator,
   Settings, privacy, permissions, and accessibility.

`DocumentationCatalog` combines both sources. For application articles it derives the title,
subtitle, symbol, order, enabled state, alias, global hotkey, default actions, and configuration
fields from the live `LauncherApplicationRegistry`. Authored content therefore does not duplicate
mutable registration metadata. Disabled applications stay in the browser and explain how to enable
them.

The catalog precomputes folded searchable text from titles, summaries, keywords, prose, steps,
shortcuts, examples, aliases, actions, and configuration. `DocumentationViewModel` owns selection,
filtering, and refresh. The SwiftUI views render only typed blocks; repository Markdown is not read
or parsed at runtime and no documentation query leaves the Mac.

## Structured content contract

`LauncherApplicationDocumentation` contains:

- a `DocumentationCategory` for sidebar grouping;
- a concise overview;
- one or more stable `DocumentationSection` values;
- additional search keywords.

Sections contain stable, uniquely identified `DocumentationBlock` values. Supported block content
is paragraph text, bullet lists, numbered steps, shortcut tables, input/output examples, and typed
callouts for tips, privacy, permissions, limitations, or important notes. Stable IDs support tests,
search, and future deep links.

Registration rejects launchable applications with missing or malformed documentation. Validation
requires non-empty content and unique section, block, shortcut, and example IDs. Groups may omit an
article because they are hierarchy nodes rather than launchable experiences.

## Adding or changing a launcher application

1. Author the feature and its registration metadata as described in
   `docs/LAUNCHER_APPLICATIONS.md`.
2. Add a focused documentation contribution beside the application under
   `Commandly/Scenes/Launcher/Applications/Documentation`.
3. Pass it to `LauncherApplicationDefinition(manifest:documentation:)`. That initializer requires
   the contribution, so a normal application registration cannot compile without documentation.
4. Describe every implemented workflow, action, keyboard shortcut, configuration field, privacy
   boundary, permission, and material limitation. Use structured examples for input-driven tools.
5. Register the application normally. Do not add a documentation-screen branch: the article is
   included through `LauncherApplicationRegistry` the next time the documentation catalog refreshes
   (including when the Documentation window opens).
6. Add focused behavior tests and verify that the built-in documentation coverage test still passes.

When behavior changes, update its in-app article and the relevant developer document in the same
change. Content must be grounded in the implementation and tests. Never promise a permission,
integration, network result, or persistence guarantee that was not verified.

## Adding core documentation

Use a focused file under `Commandly/Scenes/Documentation/Content` for a behavior that cannot be
owned by a registered application. Expose one `CoreDocumentationArticle` and add it to
`CoreDocumentationCatalog.articles`. Prefer turning a real feature into a registered application
when it has an independent launcher surface; core articles are not a second feature registry.

Calculator is intentionally a core article because calculation is an inline launcher search
provider. Its article is the reference example for detailed, searchable documentation and must stay
aligned with `docs/CALCULATOR.md` and CalculatorKit coverage.

## UI and accessibility

The Documentation window is resizable and uses Commandly's original macOS material language: a
translucent native background, a searchable navigation sidebar, restrained Liquid Glass navigation
controls, and quiet standard-material article surfaces. It honors the shared text-size preference
and uses a fixed reading layout optimized for documentation at either launcher density.

- **Command-F** focuses documentation search.
- Up/Down Arrow moves article selection while search is focused.
- Escape clears an active search.
- Section chips scroll to stable article headings.
- Key symbols have spoken labels, headings expose header traits, selected rows expose selected state,
  and callouts use labels and symbols rather than color alone.
- Reduced Motion removes the window's nonessential selection/sidebar animation.

## Privacy and maintenance

The browser does not request a permission, use the network, inspect user content, or log searches.
It may display the current non-secret application alias, shortcut, enablement, and configuration
schema already held by the registry. Documentation must never include secrets, clipboard values,
private file paths, or user-authored content.

Run targeted documentation tests, then `make verify`, before claiming a documentation change is
complete.
