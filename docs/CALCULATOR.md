# Calculator

Commandly evaluates calculator-shaped queries in the launcher search field and pins a **Calculator** result card above commands and applications.

## Behavior

- Runs concurrently with command/app search; cancels on each keystroke
- Does not replace normal search results
- Primary action (Return) copies the formatted result via `PasteboardAccessing`
- Supports `ans` / `answer` / `previous` from the last successful result in the session

## Engine

Implementation lives in the **CalculatorKit** package:

- Classification (avoids false positives like `Photoshop 2026`)
- Normalization (Unicode operators, NL aliases, thousands separators)
- Recursive-descent parser (Decimal arithmetic; documented `-5^2` and `2^3^2`)
- Scientific functions, percentages, units (`Measurement`), currency (Frankfurter, no API key), dates, time zones

## Currency

`FrankfurterExchangeRateProvider` uses `https://api.frankfurter.app`. No API key is required. Rates are never fabricated; offline/provider failures surface as user-facing errors. Unit tests use fake providers only.

## Ambiguities

- `$` without an explicit currency code is treated as ambiguous
- Abbreviations like `CST` / `IST` require clarification rather than guessing
- Angle mode defaults to radians (session-configurable via `CalculatorSessionStore`)

## Privacy

Calculator expressions and results are not logged.
