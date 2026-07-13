# Design System

`DesignSystem` provides tokens only:

- Spacing
- Corner radius
- Typography roles
- Text scale (`CommandlyTextScale` + `commandlyFont` / `commandlyTextScale`)
- Motion durations
- Layout constants (including onboarding window sizes)
- Semantic color roles (system-mapped for light/dark)
- `BrandPalette` blue accents for branded moments such as onboarding
- `LauncherPalette` adaptive launcher canvas, chrome, sidebar, detail, selection, and separator roles
- `SettingsPalette` adaptive Settings canvas, sidebar, card, and border tints

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

The launcher layers a translucent near-black navy tint over a native behind-window blur in Dark appearance. This preserves enough desktop color and luminance to feel integrated with macOS while keeping text legible. Light appearance uses the same material structure with a brighter adaptive tint. Header/footer chrome, sidebar/detail separation, selection, and hairlines must use `LauncherPalette` instead of feature-local dark-mode constants.

Settings uses the same native material foundation with `SettingsPalette` tints. Native Liquid Glass is reserved for grouped cards and interactive choice/action controls; it should not be stacked across every row or used as decoration without a hierarchy purpose. Both launcher and Settings windows must remain non-opaque so their behind-window materials can sample the desktop.

## Launcher artwork

`Commandly/Scenes/Launcher/Components/LauncherGlyph.swift` owns the compact filled-glyph treatment shared by root commands, File Search, and Clipboard History. Glyphs use SF Symbols inside a consistent rounded tile so they remain crisp and accessible at compact sizes. File artwork covers folders, images, audio, video, archives, source code, spreadsheets, presentations, PDFs, text, web links, fonts, and generic documents. Clipboard file entries reuse the same file classification.

The original app-icon master lives at `Artwork/CommandlyAppIcon-master.png`; the macOS renditions live in `Assets.xcassets/AppIcon.appiconset`. Keeping the master outside the app-target resources avoids shipping the large production source alongside the compiled asset catalog.

## Shared launcher chrome

Reusable interactive chrome lives in the app target under `Commandly/Scenes/Shared/` (not in the DesignSystem package, which stays tokens-only):

- `CommandlyBackButton` — top-leading back control with hover/press motion
- `CommandlyOptionMenu` — searchable sort/filter menu; screens supply `CommandlyOptionItem` values and selection handling

## Rules

- Do not build the final launcher UI here.
- Do not copy Raycast or other competitor visuals.
- Prefer semantic roles over one-off magic numbers in features.
- Use `BrandPalette` only where a Commandly blue identity is intentional; prefer `SemanticColors` for standard chrome.
- Keep the foundation accessible and native.
