# Design System

`DesignSystem` provides tokens only:

- Spacing
- Corner radius
- Typography roles
- Motion durations
- Layout constants (including onboarding window sizes)
- Semantic color roles (system-mapped for light/dark)
- `BrandPalette` blue accents for branded moments such as onboarding

## Rules

- Do not build the final launcher UI here.
- Do not copy Raycast or other competitor visuals.
- Prefer semantic roles over one-off magic numbers in features.
- Use `BrandPalette` only where a Commandly blue identity is intentional; prefer `SemanticColors` for standard chrome.
- Keep the foundation accessible and native.
