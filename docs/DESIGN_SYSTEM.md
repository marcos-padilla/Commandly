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
