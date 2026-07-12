# Calculator

Commandly evaluates calculator-shaped queries in the launcher search field and pins a **Calculator** result card above commands and applications.

## Behavior

- Runs concurrently with command/app search; cancels on each keystroke
- Does not replace normal search results
- Primary action (Return) copies the formatted result via `PasteboardAccessing` without dismissing the launcher
- Clicking the question pane restores the original expression to the search field for editing; clicking the answer pane copies it in place
- A contextual actions menu can copy formatted or plain output, reopen the expression for editing, insert the result into search, open compatible numeric results in Calculator, or copy the expression/result and open Notes
- Supports `ans` / `answer` / `previous` / `last result` from the last successful result in the session
- Supports named values and assignments in host-owned session memory (`x = 25`, `save 84.50 as subtotal`)
- Previews recoverable incomplete input and offers a recomputed completion on every keystroke

## Engine

Implementation lives in the **CalculatorKit** package:

- Classification (avoids false positives like `Photoshop 2026`)
- Normalization (Unicode operators/fractions/superscripts, English number words, natural-language aliases, locale-aware decimal and grouping separators)
- Single-pass lexer plus recursive-descent parser. Both are linear in input length (`O(n)`), which is the optimal bound for fully consuming an expression; no dynamic evaluation or parser dependency is used.
- Decimal arithmetic with scientific notation, implicit multiplication, postfix percentages and factorials, modulo, functions, and full-input consumption
- Scientific functions, percentages, units (`Measurement`), currency (Frankfurter, no API key), finance, calendars, time zones, geometry, business formulas, and developer utilities

## Arithmetic grammar

Precedence from low to high is additive, multiplicative/modulo, unary signs, right-associative powers, postfix percent/factorial, then primaries and implicit multiplication.

- `-5^2` is `-(5^2)` and evaluates to `-25`
- `2^3^2` is `2^(3^2)` and evaluates to `512`
- `-5!` is `-(5!)` and evaluates to `-120`
- Factorials accept integers from 0 through 32. Negative, fractional, or larger inputs fail instead of overflowing or silently using a gamma function.
- `%` is postfix percentage without a right operand (`20%`) and modulo with one (`10 % 3`). `mod` and `modulo` are explicit aliases.

Supported numeric functions include roots, powers, absolute value, rounding, trigonometric and hyperbolic functions, logarithms, `min`, `max`, `clamp`, sum/mean/median/mode/product/range/variance/standard deviation, factorial, GCD/LCM, and combinations/permutations. Constants include `pi`, `e`, `tau`, `phi`, `sqrt2`, `ln2`, and `ln10`.

Structured command evaluators also cover nearest-increment and significant-figure rounding, numeric comparisons, reverse percentages, tips/taxes/discounts/markup/margin, ratios and proportions, elementary linear equations, two-variable linear systems, real-root quadratics, prime operations, and explicitly marked nondeterministic random commands. These paths consume the complete input and do not use dynamic evaluation. Quadratics with complex-only roots and general symbolic algebra remain unsupported.

## Locale and pasted input

Number literals are canonicalized once using the evaluation locale, then tokenized with a stable internal grammar. Locale grouping separators, regular/non-breaking spaces, and apostrophes are accepted when they form three-digit groups. Common pasted operators (`×`, `÷`, `−`, `√`), superscripts (`²`, `³`), and vulgar fractions are normalized before parsing. A separator that is not valid for the selected locale is not silently guessed.

English number phrases are normalized before lexing, including hyphenated compounds, hundreds through billions, decimals introduced by “point,” and negative values. Examples include `ten plus ten`, `one hundred and five times two`, and `three point five plus one point two five`. Named fraction handling remains separate so phrases such as `one half` retain their fraction meaning.

## Launcher interaction

The calculator card deliberately has separate interactive regions instead of behaving as one command button:

- The question pane returns the original input to the focused search field so it can be edited.
- The answer pane copies the formatted answer and keeps Commandly visible.
- The actions menu is result-aware. For example, date or textual answers do not offer “Open in Calculator.”
- “Copy and Open Notes” puts a ready-to-paste `expression = result` line on the pasteboard and opens Notes. It does not automate or modify a note, avoiding an Apple Events/Automation permission.
- Incomplete but recoverable input, such as `sqrt(5` or `2 +`, is evaluated from a typed completion without changing the text the user entered. A ghost suffix and a right-side **Tab to complete** control accept that completion.
- Bare, unambiguous measurements infer a conventional target (`5 mph` → km/h, `5 feet` → meters). The target is recalculated from the current query, so continuing with `5 mph in m` changes the completion to m/s instead of retaining stale state.
- Typo corrections that replace existing characters cannot be represented as an append-only ghost suffix; the same Tab control still accepts the full corrected expression.

All three controls expose distinct accessibility labels and remain keyboard-focusable.

## Scope

The supplied calculator expression catalog is covered by specialized deterministic evaluators and table-driven tests. This includes arithmetic/scientific expressions, percentages, units, currency and finance, calendars and time zones, scheduling/cron, geometry, informational health arithmetic, business metrics, number bases/bitwise operations, character and color conversion, transfer-time estimates, URL encoding, and Base64.

Symbolic integration/differentiation and astronomy without a location are explicitly unsupported. They return an unsupported-capability error rather than a fabricated value. Cron support intentionally covers the documented five-field examples, not every vendor-specific extension.

The source expression catalog is audited line by line with `scripts/audit-calculator-prompt-coverage.rb`. The current catalog contains 754 executable examples represented verbatim in CalculatorKit tests. Another 34 fenced lines are explicitly classified by the audit as documentation rather than queries: operator legends, displayed expected equations/results, standalone alias vocabulary, and decimal-versus-binary unit comparison labels.

## Unit conversions

The unit registry supports length, area, volume, mass, temperature, duration, speed, acceleration, pressure, energy, power, frequency, decimal and binary data storage, data-transfer rate, fuel economy, angle, torque, force, density, volume flow, current, voltage, resistance, and illuminance. It also evaluates the electrical relationships `P = V × I`, `I = P ÷ V`, and `V = P ÷ I`.

- Unqualified gallons, cups, pints, quarts, fluid ounces, tablespoons, and teaspoons use exact US customary definitions. Imperial volume aliases are explicit.
- Unqualified `mpg` means US miles per gallon; Imperial mpg is separately supported.
- Duration years use the mean Gregorian year of 365.2425 days and include that assumption in result metadata. Months are not treated as fixed durations.
- “Speed of sound” uses 343 m/s for dry air at 20 °C and records the assumption.
- Ingredient-dependent cooking volume-to-mass conversions fail without density data; Commandly does not pretend that all ingredients share a density.
- Lumens and lux are not interconverted because luminous flux and illuminance are different physical dimensions.
- A standalone lumen quantity is preserved as luminous flux and explicitly notes that an illuminance conversion requires area and geometry.
- Default targets are registry policies, not a list of full prompt strings. Every registered alias and every canonical same-dimension conversion is exercised by exhaustive tests. Materially ambiguous bare aliases such as `m`, `oz`, and `gal` do not receive an inferred target.

## Currency

`FrankfurterExchangeRateProvider` uses `https://api.frankfurter.app`. No API key is required. Rates are never fabricated; offline/provider failures surface as user-facing errors. Unit tests use fake providers only.

- ISO codes, common currency names, compact forms (`100USD in EUR`, `100 usd eur`), and common symbols are supported.
- `$` is resolved only when the locale region identifies a dollar currency (for example USD, CAD, AUD, or NZD). Otherwise it remains ambiguous. `€` and `£` are unambiguous; `¥` requires Japanese or Chinese locale context.
- Generic names such as “pesos” and `kr` remain ambiguous. Region-qualified names such as “Mexican pesos” are supported.
- Multiple-currency addition converts every operand to the requested output currency using timestamped provider rates. A missing rate fails the entire result.
- “Divide by the EUR exchange rate” uses the explicit EUR/source-currency quote direction and records that direction in metadata.

## Finance

The deterministic finance evaluator supports simple and compound interest, present value, ordinary annuity present value, fixed-rate loan payments, mortgage down payments, remaining loan balance, savings goals, total and annualized return, profit/margin/loss, break-even calculations, pay-period conversion, and overtime pay.

- Loan results include principal, rate, payment count, total paid, and total-interest notes. Taxes, insurance, HOA charges, and fees are explicitly excluded.
- Savings calculations distinguish no-return saving from end-of-month deposits with monthly compounding.
- Break-even units round up to the next whole unit.
- Hourly/annual conversions use configurable paid hours per week and paid weeks per year from `CalculatorEvaluationContext`.
- Overtime uses the context’s configurable multiplier and never infers a legal rule from locale.
- These calculations are deterministic arithmetic, not financial, tax, legal, or investment advice. No market return is fabricated.

## Calendar and time

- Relative and specific-date arithmetic uses the configured `Calendar`, `TimeZone`, locale, and deterministic `now`.
- Adding months or years clamps an invalid month-end or leap-day to the last valid day.
- `next Monday` excludes today; `this Wednesday` can include today. Week boundaries use the configured calendar.
- Business days use configurable weekend weekdays and only explicitly supplied holiday dates. No regional holiday is invented.
- Birthday queries require an explicitly supplied birth date or a month/day stored with consent.
- Time-zone conversions use IANA zones and date-aware daylight-saving offsets. Ambiguous abbreviations such as `CST`, `IST`, and `BST` fail.
- The zone registry includes every identifier reported by Foundation, unique city aliases derived from IANA identifiers, and explicit common geographic aliases such as `Arizona` → `America/Phoenix`. Fuzzy matching accepts only a unique best match, so uncertain names are not guessed.
- Bare clock differences cross midnight when the end is not later than the start. Scheduling expressions with bare working-hour clocks infer `9` to `5` as an eight-hour daytime interval.
- UTC offsets support whole, half, and quarter hours. Unix seconds/milliseconds and ISO 8601 date-times are supported.

## Geometry, health, business, and developer utilities

- Geometry covers the documented rectangle, square, circle, triangle, cube, box, sphere, cylinder, and cone formulas.
- BMI, pace, distance/speed/time, and calorie totals are informational arithmetic only; they are not diagnoses or weight-change guarantees.
- Business calculations cover work hours, subtotals/tax/tip, explicit commission tiers, conversion/growth rates, CPA, ROAS, and ROI.
- Developer utilities cover binary/octal/decimal/hex values, contextual bitwise operators, ASCII/Unicode, RGB/HSL/hex colors, SI transfer-time estimates, percent encoding, and Base64.
- Transfer-time results exclude protocol overhead unless a future caller supplies an explicit model; the assumption is recorded in metadata.

## Session memory

`CalculatorEvaluationContext.variables` carries named values into evaluation. Assignment results expose typed `assignedVariableName` and `assignedVariable` metadata, which the macOS host records in `CalculatorSessionStore`.

- Memory is session-scoped and in-process by default.
- Percentage variables preserve their percentage semantics (`tax = 7%`, then `100 + tax` → `107`).
- Typed previous measurements retain their source unit, enabling queries such as `convert ans to meters`.
- Calculator expressions, assignments, and values are never logged or persisted by `CalculatorKit`.

## Ambiguities

- `$` is resolved only with a locale region that identifies a specific dollar currency; otherwise it is ambiguous
- Standalone shorthand such as `5 m`, `10 oz`, or `1 gal` requests clarification rather than inventing an operation
- Abbreviations like `CST` / `IST` require clarification rather than guessing
- Numeric dates use the configured locale and attach the interpretation to result metadata
- Angle mode defaults to radians (session-configurable via `CalculatorSessionStore`)

## Live prediction and fuzzy matching

Prediction is a separate typed layer over the deterministic evaluators. It can balance missing parentheses, add a neutral operand to a trailing arithmetic operator, complete function names, correct bounded natural-language/unit/time-zone typos, and infer a default conversion. The completed expression is evaluated once with prediction disabled, which prevents recursion and ensures the preview uses the same parser and evaluators as a submitted query.

String correction uses a Unicode-aware optimal-string-alignment Damerau–Levenshtein implementation. Similarity thresholds are bounded by domain, and ties are rejected. Language normalization rules, correction vocabulary, units, and time zones are centralized registries rather than enumerations of complete prompts. This supports new numeric values and grammatical combinations without adding an exact case for each sentence.

Suggestions are stateless and recomputed for each query. Search, calculation, and completion tasks respect cancellation before publishing UI state, preventing a slower earlier query from overwriting a later one. A debug performance test currently requires 1,500 representative suggestions to complete in under one second on the test host; this is a regression guard, not a cross-device product guarantee.

## Privacy

Calculator expressions and results are not logged. Clipboard writes happen only after an explicit copy action. Opening Calculator or Notes happens only after the user selects the corresponding action; Commandly does not request Automation permission or write directly into Notes.

Partial input and predictions are not persisted. Prediction performs no network access; currency evaluation retains its existing explicit provider behavior.

Random commands are generated only after the query explicitly requests a random value and their result metadata marks them as nondeterministic. They are not persisted by `CalculatorKit`.

## Testing the supplied catalog

Run the package tests and then audit the exact prompt file:

```sh
swift test --package-path Packages
ruby scripts/audit-calculator-prompt-coverage.rb /path/to/pasted-text-1.txt
```

The audit fails and prints source line numbers if any executable fenced expression is absent from the CalculatorKit test sources.
