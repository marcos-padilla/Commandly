# Color Tools and root color results

Color Tools and the root launcher share one bounded, local sRGB literal parser. Entering a complete color such as `#966A5E` in root search presents an original compact swatch/value card with a format selector, Copy, and Formats. Return copies the selected format; Command-K opens the six typed copy actions. In Color Tools, all six values appear together with explicit copy buttons and a selected format for Return. Command-1 through Command-6 copy the formats in the order below. The existing native screen sampler remains an explicit separate action.

| Output | Example for #966A5E |
| --- | --- |
| Hex | `#966A5E` |
| Hex with Alpha | `#966A5EFF` |
| RGBA | `rgba(150, 106, 94, 1)` |
| RGBA (Percentage) | `rgba(58.823529%, 41.568627%, 36.862745%, 100%)` |
| RGB (CSS4) | `rgb(150 106 94 / 1)` |
| HSL | `hsl(12.857143 22.95082% 47.843137% / 1)` |

Hex is explicitly six digits and omits transparency. Hex with Alpha always includes eight digits. Transparent inputs initially select Hex with Alpha; the checkerboard preview and text identify transparency. All other outputs retain alpha, including HSL. Hex rounds each component to the nearest byte. Functional outputs use up to six decimal places; conversion is bounded precision, not exact arbitrary-precision arithmetic.

## Supported literals

Based on the W3C's [CSS Color 4 RGB syntax](https://www.w3.org/TR/css-color-4/#rgb-functions), [hex notation](https://www.w3.org/TR/css-color-4/#hex-notation), and [HSL syntax/conversion](https://www.w3.org/TR/css-color-4/#the-hsl-notation):

- Hex with 3, 4, 6, or 8 ASCII digits.
- `rgb()` / `rgba()` and `hsl()` / `hsla()` aliases, case insensitive.
- Legacy comma forms; RGB channels must share number or percentage units, HSL saturation/lightness must be percentages, and optional alpha uses a comma.
- Modern space forms, optional slash alpha, RGB numbers/percentages (including mixed units), HSL saturation/lightness numbers or percentages, and absolute missing components (`none`, resolved to zero).
- Numeric hue in degrees or `deg`, `grad`, `rad`, `turn`; finite signed decimals/exponents; number or percentage alpha. Finite RGB/alpha outliers clamp to their bounded sRGB ranges. Hue wraps; negative saturation clamps to zero. Resolved out-of-gamut HSL channels clip to sRGB.

The parser accepts at most 256 UTF-8 bytes including surrounding whitespace. It rejects non-finite numbers, malformed delimiters/units, mixed legacy channel types, trailing garbage, and unsupported syntax. This is a standalone literal converter, not a complete CSS evaluator: no named/system colors, variables, calculations, relative colors, comments, escapes, wide-gamut spaces, interpolation, or CSS gamut-mapping engine. It does not invoke WebKit or run a stylesheet.

## Ownership and lifecycle

`Services/OfflineTools/CommandlyColor.swift`, `CommandlyColorParser.swift`, and `CommandlyColorActions.swift` own finite values, literal conversion, and stable format actions. Only color logic was extracted from `OfflineToolsDomain.swift`; other tools are unchanged. `Composition/Search/ColorSearchProvider` is a synchronous adapter with no I/O. `ColorSearchModel` owns root result identity, output selection and explicit clipboard dispatch; UI remains on MainActor. The focused editor uses the same value and action definitions.

Changing a query clears its old root result, pending copy and action menu. Result identities prevent an old card/menu from copying a later query, including the same literal entered again. A queued cancelled copy never dispatches; an authorized clipboard write already in progress cannot be revoked, and its stale completion cannot change the new result's status. Dismissal clears root color state. A late native sampler completion does not replace color text edited while the sampler was open.

## Privacy and accessibility

Parsing/conversion performs no disk, network, permission, profile, or device reads. Draft colors remain in view/model memory and are not logged or persisted by this feature. Copy is explicit and writes only the reviewed chosen string. The existing NSColorSampler boundary is unchanged; no screen recording or image retention is added.

The original swatch uses a checkerboard for alpha and an accessible value. Headings, input, format selector and per-format buttons have labels. Format names accompany color previews so meaning does not depend on color alone. The editor claims input focus after attachment, supports Return and Command-1…6, and uses the shared Command-K/Escape action flow. Root format actions use the shared keyboard action panel. Layout follows Commandly density tokens and supports scrolling of the format rows.

## Verification

`CommandlyColorTests` covers accepted legacy/modern syntax, malformed strings, bounds and finite inputs, known vectors, hue units, alpha, extreme finite values and deterministic round trips through all six outputs. `ColorSearchModelTests` exercises the real parser plus injected clipboard/sampler boundaries, six exact typed outputs, stale identities, cancellation before/after dispatch, selected-format Return and late sampler results. Root integration tests cover immediate Return while search is pending, recognition, alpha defaults, actions, and query replacement.

Isolated tests and off-tree Swift 6 app typechecking are required before publication. Final app build/full verification and native keyboard/VoiceOver acceptance are tracked by the root task; no real clipboard, screen sampler, or permission is exercised in these deterministic tests. Search-path benchmark results are recorded with the slice integration receipt.

September 14, 2026: aggregate `make verify` passed in `/tmp/commandly-video-verify-tranche15-color.log`.
The clean signed native build passed strict deep signature validation. Native root acceptance found
the generated `#966A5E` value, filtered Command-K to percentage output, copied HSL with Command-6,
and selected Hex with Alpha for a transparent RGB input. The editor displayed all six formats and
converted `hsl(0.5turn 100% 50% / 25%)` to `rgb(0 255 255 / 0.25)` using Command-5. Root copy used
the in-memory acceptance pasteboard; the editor copied these generated colors through the actual
SystemPasteboard. The actual NSColorSampler returned `#212121` from
Commandly's own interface and restored its input focus. A separate cancellation check is pending.
Editor Command-K exposed a shared menu presentation bug. After repair, native Command-K → CSS4
search → Return copied the expected value and restored the prior input selection, verified by
typing a replacement color. The shared-menu full verification passed in tranche 15. A field-editor
Escape fallback passed native acceptance in tranche 16: Escape closes the Actions panel and restores
the editor selection; Escape in the editor returns to root search. Native sampler-only cancellation
is still unconfirmed because the observed Escape also returned to root.
