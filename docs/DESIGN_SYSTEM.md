# Design System

`DesignSystem` provides tokens only:

- Spacing
- Corner radius
- Typography roles
- Text scale (`CommandlyTextScale` + `commandlyFont` / `commandlyTextScale`)
- Motion durations and shared control/navigation curves
- Layout constants (including onboarding, settings, launcher, and documentation window sizes)
- Semantic color roles (system-mapped for light/dark)
- `BrandPalette` blue accents for branded moments such as onboarding
- `CommandlyTint` semantic color families for status, warning, success, and destructive meaning
- `LauncherPalette` neutral adaptive launcher canvas, chrome, sidebar, detail, selection, and
  separator roles
- `SettingsPalette` neutral adaptive utility-window canvas, sidebar, detail, fields, selection,
  focus, and separator roles shared by Settings and Documentation

## Text size

User preference (`AppTextSizePreference` in settings) maps to a scale factor via `commandlyContentSize(_:)`:

- **Default** → `CommandlyTextScale.standard` (`1.0`) and Dynamic Type `.medium`
- **Larger** → `CommandlyTextScale.larger` (`1.2`) and Dynamic Type `.xLarge`

Feature UI should prefer `.commandlyFont(size:weight:design:)` for chrome and copy so the preference takes effect. Keep fixed `.font(.system(size:))` only for intentionally non-scaling details (for example decorative keyboard key caps).

## View mode

User preference (`AppViewModePreference`) maps to `CommandlyLayoutDensity` via `commandlyViewMode(_:)`:

- **Comfortable** → default spacing, compact single-line launcher rows, and standard launcher height
- **Compact** → tighter padding, smaller icons, shorter launcher panel

Launcher and settings chrome read `\.commandlyLayoutDensity` for paddings and sizes. Launcher result rows are single-line (title plus optional muted inline subtitle and trailing kind label) in both densities.

The launcher layers a neutral adaptive tint over a native behind-window material. It stays
achromatic so search, selection, and real application artwork provide the hierarchy. Settings uses
one translucent neutral sidebar and one quieter detail plane; section spacing and hairlines replace
decorative cards. Documentation uses the same material foundation with a wider searchable sidebar
and constrained reading canvas.

Native Liquid Glass is limited to the navigation and transient-control layer. It may be used for a
sidebar toggle, a floating menu, or another genuinely elevated control, but not as a background for
every row or section. Search fields remain transparent or use an untinted system treatment. Static
settings groups, result rows, and detail content stay flat. Launcher, Settings, and Documentation
windows remain non-opaque so system materials can respond to the desktop, Reduce Transparency, and
active-window state.

Shelf is a single transient floating staging surface, so its board may use one clear Liquid Glass
shape rather than nested glass cards. Its behind-window material deliberately remains optically
active while another application has focus because the board stays visible across applications.

The root launcher treats search as an embedded canvas row with no independent border or fill. Its
footer keeps contextual Actions at the leading edge and one labeled Settings gear menu at the
trailing edge for Documentation, Settings, and Quit.

Navigation and content glyphs are monochrome. `CommandlyTint` is reserved for semantic status such
as success, warning, error, or destructive actions. Standard selection and focus follow the user's
macOS accent color and never carry meaning without labels, weight, or selected-state traits.

## Launcher artwork

`Commandly/Scenes/Launcher/Components/LauncherGlyph.swift` owns the compact monochrome glyph treatment shared by root commands, File Search, and Clipboard History. Glyphs use filled SF Symbols in a consistent alignment frame so they remain crisp and accessible at compact sizes without decorative tiles. File artwork covers folders, images, audio, video, archives, source code, spreadsheets, presentations, PDFs, text, web links, fonts, and generic documents. Clipboard file entries reuse the same file classification.

The original app-icon master lives at `Artwork/CommandlyAppIcon-master.png`; the macOS renditions live in `Assets.xcassets/AppIcon.appiconset`. Keeping the master outside the app-target resources avoids shipping the large production source alongside the compiled asset catalog.

## Shared launcher chrome

Reusable interactive chrome lives in the app target under `Commandly/Scenes/Shared/` (not in the DesignSystem package, which stays tokens-only):

- `CommandlyBackButton` — top-leading back control with hover/press motion
- `CommandlyOptionMenu` — searchable sort/filter menu; screens supply `CommandlyOptionItem` values and selection handling

Reusable launcher-application composition lives under `Commandly/Scenes/Launcher/Applications/`:

- `LauncherApplicationScreen` — opt-in search/filter/sidebar/detail layout with shared focus and keyboard behavior
- `LauncherApplicationRow` — selection, hover, double-click, and contextual-action row foundation
- `LauncherApplicationEmptyState` and `LauncherApplicationMetadataRow` — consistent browser-surface states and detail rows

These components encode the existing Commandly visual language; feature-specific content and behavior remain in each application.

## Rules

- Do not build the final launcher UI here.
- Do not copy Raycast or other competitor visuals.
- Prefer semantic roles over one-off magic numbers in features.
- Use `BrandPalette` only where a Commandly blue identity is intentional; prefer `SemanticColors` for standard chrome.
- Keep the foundation accessible and native.
