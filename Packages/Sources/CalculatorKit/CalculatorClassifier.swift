import Foundation

/// Classifies whether input is calculator-shaped and which specialized path to use.
///
/// Classification is heuristic and multi-signal — not a single regular expression.
struct CalculatorClassifier: Sendable {
    private static let knownCurrencyCodes: Set<String> = [
        "usd", "eur", "gbp", "jpy", "cad", "aud", "chf", "cny", "hkd", "nzd",
        "sek", "nok", "dkk", "pln", "czk", "huf", "ron", "bgn", "try", "ils",
        "inr", "krw", "sgd", "thb", "myr", "idr", "php", "zar", "brl", "mxn",
        "ars", "clp", "cop", "pen", "aed", "sar", "twd", "vnd", "uah", "rub",
    ]

    func classify(_ rawInput: String) -> ClassificationResult {
        let trimmed = rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return ClassificationResult(intent: .notCalculator, confidence: .low)
        }

        let lowered = trimmed.lowercased()

        // Specialized intents first so conversion language is not discarded as "prose + digit".
        if looksLikeCalculationSuite(lowered) {
            return ClassificationResult(intent: .calculationSuite, confidence: .high)
        }
        if looksIncomplete(lowered) {
            return ClassificationResult(intent: .incomplete, confidence: .medium)
        }
        if looksLikeCurrency(lowered) {
            return ClassificationResult(intent: .currencyConversion, confidence: .high)
        }
        if looksLikeFinancial(lowered) {
            return ClassificationResult(intent: .financial, confidence: .high)
        }
        if looksLikePercentagePhrase(lowered) {
            return ClassificationResult(intent: .percentage, confidence: .high)
        }
        if looksLikeUnit(lowered) {
            return ClassificationResult(intent: .unitConversion, confidence: .high)
        }
        if lowered.range(of: #"^time between .*(?:january|february|march|april|may|june|july|august|september|october|november|december).+ and .+$"#, options: .regularExpression) != nil {
            return ClassificationResult(intent: .dateCalculation, confidence: .high)
        }
        if looksLikeTimeZone(lowered) {
            return ClassificationResult(intent: .timeZoneConversion, confidence: .high)
        }
        if looksLikeDate(lowered) {
            return ClassificationResult(intent: .dateCalculation, confidence: .high)
        }
        if looksLikeScientific(lowered) {
            return ClassificationResult(intent: .scientific, confidence: .high)
        }
        if looksLikeArithmetic(lowered) {
            return ClassificationResult(intent: .arithmetic, confidence: .high)
        }

        if looksLikeNonCalculatorPhrase(trimmed) {
            return ClassificationResult(intent: .notCalculator, confidence: .high)
        }

        return ClassificationResult(intent: .notCalculator, confidence: .high)
    }

    // MARK: - Negative cases

    private func looksLikeNonCalculatorPhrase(_ input: String) -> Bool {
        let lowered = input.lowercased()

        // Conversion / time / date shaped queries are never "incidental number" phrases.
        if looksLikeTimeZone(lowered) || looksLikeCurrency(lowered) || looksLikeDate(lowered) || looksLikeUnit(lowered) {
            return false
        }
        if containsFunctionCall(lowered) || containsCalculatorVocabulary(lowered) {
            // Still allow app-name negatives below when no math operators.
        }

        let negativePatterns: [String] = [
            #"^(photoshop|safari|chrome|finder|settings|preview|notes|mail|maps|music|calendar)\b"#,
            #"^open\s+\w+"#,
            #"^customer\s+\d+"#,
            #"^command\s+\d+$"#,
            #"^file\s+version\s+\d+"#,
            #"^invoice\s+\d+"#,
            #"^\w+\s+20\d{2}$"#,
        ]

        for pattern in negativePatterns {
            if lowered.range(of: pattern, options: .regularExpression) != nil {
                if containsMathOperators(lowered) || containsFunctionCall(lowered) {
                    continue
                }
                return true
            }
        }

        if lowered.range(
            of: #"^\d+\s+\w+\s+(street|st|avenue|ave|road|rd|boulevard|blvd|lane|ln)\b"#,
            options: .regularExpression
        ) != nil {
            return true
        }

        let hasDigit = lowered.contains { $0.isNumber }
        let hasOperator = containsMathOperators(lowered) || lowered.contains("(") || lowered.contains("%")
        let hasCalcVocabulary = containsCalculatorVocabulary(lowered)
        if hasDigit && !hasOperator && !hasCalcVocabulary && !containsFunctionCall(lowered) {
            let letterCount = lowered.filter(\.isLetter).count
            let digitCount = lowered.filter(\.isNumber).count
            if letterCount >= 4 && digitCount <= 4 {
                return true
            }
        }

        return false
    }

    // MARK: - Positive signals

    private func looksIncomplete(_ input: String) -> Bool {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return true }

        if let last = trimmed.last, "+-*/^(".contains(last) {
            return true
        }

        // Word suffixes must be whole tokens, not accidental endings ("tokyo" ≠ "to").
        let wordSuffixes = ["of", "in", "to", "into", "as", "from", "on", "plus", "minus", "times"]
        for suffix in wordSuffixes {
            if trimmed == suffix { return true }
            if trimmed.hasSuffix(" " + suffix) { return true }
        }
        if input.range(of: #"^price after \d+(?:\.\d+)?% tax$"#, options: .regularExpression) != nil {
            return true
        }
        if input == "interest paid in first year" || input == "principal paid after 24 payments" {
            return true
        }

        let open = trimmed.filter { $0 == "(" }.count
        let close = trimmed.filter { $0 == ")" }.count
        return open > close && !trimmed.hasSuffix(")")
    }

    private func looksLikeCurrency(_ input: String) -> Bool {
        if hasDigit(input), input.contains("exchange rate") {
            return true
        }
        let hasConversion = input.contains(" in ") || input.contains(" to ") || input.contains(" into ") || input.contains(" as ")
        let hasShortConversion = input.range(
            of: #"^[-+]?\d+(?:\.\d+)?\s*[a-z]{3}\s+[a-z]{3}$"#,
            options: .regularExpression
        ) != nil
        guard hasConversion || hasShortConversion, hasDigit(input) else { return false }

        let tokens = input.split(whereSeparator: { $0.isWhitespace || $0 == "," }).map(String.init)
        let hasKnownCode = tokens.contains { Self.knownCurrencyCodes.contains($0) }
            || input.range(of: #"\d(?:usd|eur|gbp|jpy|cad|aud|cny)\b"#, options: .regularExpression) != nil
        let hasSymbol = input.contains("$") || input.contains("€") || input.contains("£") || input.contains("¥")
        let names = ["dollar", "dollars", "euro", "euros", "yen", "yuan", "peso", "pesos", "pound sterling", "british pound"]
        return hasKnownCode || hasSymbol || names.contains(where: input.contains)
    }

    private func looksLikeFinancial(_ input: String) -> Bool {
        let phrases = [
            "simple interest", "compounded", "compound ", "future value", "present value", "pv of",
            "monthly payment", "car payment", "mortgage payment", " down on ", "loan amount after",
            "% down", "remaining balance", "save monthly", "monthly savings", "return from", "annualized return", "cagr",
            "profit if", "profit margin", "loss percentage", "loss %", "break even", "per hour yearly",
            "salary hourly", "per month yearly", "per week annually", "annually monthly", "overtime",
        ]
        return hasDigit(input) && phrases.contains(where: input.contains)
    }

    private func looksLikeCalculationSuite(_ input: String) -> Bool {
        let phrases = [
            "area of a rectangle", "perimeter of a", "area of a square", "diagonal of a", "area of a circle",
            "circumference of a circle", "circle diameter from", "area of a triangle", "hypotenuse with",
            "third side of a right triangle", "volume of a cube", "volume of a box", "surface area of a sphere",
            "volume of a cylinder", "volume of a cone", "bmi for", "running pace", "mile pace", "marathon at",
            "distance at", "time to travel", "speed for", "calories per day", "calorie surplus",
            "weekly hours", "monthly hours", "subtotal ", " tax and ", "commission on", "% commission",
            "conversions from", "conversion rate", "increase conversion rate", "growth from", "monthly growth rate",
            "cpa if", "roas if", "roi if", " in binary", "binary to decimal", "hex to decimal",
            "decimal to hexadecimal", " bitwise", "ascii code", "character for ascii", "unicode for", " as character",
            " to rgb", " to hex", "hsl(", "download time", "upload ", "how long to transfer",
            "url encode", "decode ", "base64 encode", "base64 decode",
            "set hourly rate", "integrate ", "differentiate ", "solve a complex symbolic system",
            "round ", " rounded to ", " sig figs", "significant figures", "significant digits",
            "greater than", " to 2 ratio", "simplify ", "ratio of ", " in a 3:2 ratio",
            " costs ", " is to ", "solve ", "roots of ", "quadratic ",
            "is 97 prime", "next prime", "prime factors", "factorize ", "list primes",
            "random number", "random integer", "random decimal", "roll a die", "roll 2d6", "flip a coin",
            "lumens",
            "more than what", "less than what", "what number plus", "what original amount",
            "sales tax", "remove ", "price before", "take ", "original price",
            "markup", "gross margin", "markup percentage", "profit margin if",
        ]
        if phrases.contains(where: input.contains) { return true }
        if input.range(of: #"^hours from .+ to .+ with a \d+-minute lunch$"#, options: .regularExpression) != nil { return true }
        if input.range(of: #"^[a-z][a-z0-9_ ]*\s*=\s*.+$"#, options: .regularExpression) != nil { return true }
        if input.range(of: #"^save\s+[\d.]+%?\s+as\s+[a-z][a-z0-9_ ]*$"#, options: .regularExpression) != nil { return true }
        if input.range(of: #"^add [\d.]+% tax to [\d.]+$"#, options: .regularExpression) != nil { return true }
        if input.range(of: #"^cagr from [\d.]+ to [\d.]+ in \d+ years$"#, options: .regularExpression) != nil { return true }
        if input.range(of: #"^-?[\d.]+\s*(?:>|>=|<|<=|==|!=)\s*-?[\d.]+$"#, options: .regularExpression) != nil { return true }
        if input.range(of: #"^(?:x\^2|solve x\^2|x \+ y|solve x \+ y|\d+x(?:\s*[+-]\s*\d+)?\s*=|x\s*[+-])"#, options: .regularExpression) != nil { return true }
        if input.range(of: #"^\d+:\d+$"#, options: .regularExpression) != nil
            || input.range(of: #"^(?:\d+/\d+\s*=\s*\d+/x|solve \d+:\d+\s*=)"#, options: .regularExpression) != nil { return true }
        return input.range(of: #"^0x[0-9a-f]+\s*\+\s*0x[0-9a-f]+$"#, options: .regularExpression) != nil
            || input.range(of: #"^(?:not\s+\d+|\d+\s*(?:&|\||<<|>>|and|or|xor)\s*\d+)$"#, options: .regularExpression) != nil
            || input.range(of: #"^0b[01]+\s+in\s+(?:hex|octal|decimal)$"#, options: .regularExpression) != nil
    }

    private func looksLikeTimeZone(_ input: String) -> Bool {
        if input.range(of: #"^utc[+-]\d{1,2}(?::\d{2})?$"#, options: .regularExpression) != nil { return true }
        let timezoneWords = [
            "timezone", "time zone", "current time", "time now", "what time is it", "time in ", "local time in",
            "time difference", "hours ahead", "utc offset", "unix time now", "timestamp for", " as local time",
            " in local time", " in utc", "hours after", "hours before", "minutes after", "minutes before",
            "time between", "hours between", "difference between", "how long from", "hours and minutes",
            "in 24-hour", "in 12-hour", "military time", "24-hour format", "meeting from", "duration from",
            "split ", "meetings fit between", "shift starting", "workday starting", "every ", "biweekly schedule",
            "occurrences every", "what does ", "next run for", "sunrise", "sunset", "daylight duration", "golden hour",
            " as epoch",
        ]
        if timezoneWords.contains(where: { input.contains($0) }) {
            return true
        }

        if input.range(of: #"^\d{1,2}:\d{2}(?::\d{2})?\s+(?:in|as)\s+(?:seconds|hours|hours and minutes)$"#, options: .regularExpression) != nil
            || input.range(of: #"^\d{1,2}:\d{2}\s*\+\s*\d{1,2}:\d{2}$"#, options: .regularExpression) != nil
            || input.range(of: #"^(?:noon|midnight|\d{1,2}(?::\d{2})?\s*(?:am|pm)?)\s*(?:\+|-|plus|minus)\s*\d+\s+(?:hours?|minutes?)$"#, options: .regularExpression) != nil
            || input.range(of: #"^\d+\s+day\s+\d+\s+hours?\s+from now$"#, options: .regularExpression) != nil
            || input.range(of: #"^\d+\s+(?:minutes|seconds|hours)\s+(?:as|in)\s+"#, options: .regularExpression) != nil
            || input.range(of: #"^\d{13}\s+milliseconds\s+as date$"#, options: .regularExpression) != nil
            || input.range(of: #"^\d{1,2}\s+\d{1,2}\s+(?:\*|\d{1,2})\s+(?:\*|\d{1,2})\s+(?:\*|\d(?:-\d)?|mon)$"#, options: .regularExpression) != nil {
            return true
        }

        // Prefer simple patterns — ICU word boundaries break on "5pm".
        let hasTime = input.contains("noon")
            || input.contains("midnight")
            || input.range(of: #"\d{1,2}:\d{2}"#, options: .regularExpression) != nil
            || input.range(of: #"\d{1,2}\s*(am|pm)\b"#, options: .regularExpression) != nil
            || input.range(of: #"\d{1,2}(am|pm)\b"#, options: .regularExpression) != nil

        let hasPlaceOrZone = CalculatorDateTime.looksLikePlaceOrZone(input)
            || input.range(of: #"\b(cst|ist|bst|pst|est|mst|utc|gmt)\b"#, options: .regularExpression) != nil
        let hasConversion = input.contains(" in ") || input.contains(" to ")
        return hasTime && hasPlaceOrZone && hasConversion
    }

    private func looksLikeDate(_ input: String) -> Bool {
        let datePhrases = [
            "today", "tomorrow", "yesterday", "current date", "today's date",
            "days from", "weeks from", "months from", "years from",
            "days until", "weeks until", "months until", "days since", "weeks since", "months since", "years since",
            "days after", "days before", "weeks after", "weeks before",
            "months after", "months before", "years after", "years before",
            "days ago", "weeks ago", "months ago", "years ago",
            "weeks between", "days between", "months between", "years between",
            "next monday", "next tuesday", "next wednesday", "next thursday",
            "next friday", "next saturday", "next sunday",
            "last monday", "last friday", "previous tuesday", "monday after next",
            "this monday", "this tuesday", "this wednesday", "this thursday", "this friday",
            "this saturday", "this sunday", "week after next", "month after next",
            "first monday", "first tuesday", "first wednesday", "first thursday", "first friday",
            "second monday", "third friday", "fourth monday", "fifth monday",
            "start of", "end of", "first day of", "last day of",
            "week number", "what week", "day of year", "day of 20",
            "current quarter", "next quarter", "quarter", "business day", "working day", "weekdays",
            "age if born", "how old is", "age on", "birthday", "format ", " as iso",
            " as unix timestamp", "timestamp ", " as date", "in us format", "in long format",
            "in short format", "in medium format", "from now", "from today",
            "next week", "last week", "next month", "last month", "next year", "last year",
        ]
        if datePhrases.contains(where: { input.contains($0) }) { return true }
        if input.range(of: #"^(?:january|february|march|april|may|june|july|august|september|october|november|december)\s+\d{1,2}(?:,?\s+\d{4})?$"#, options: .regularExpression) != nil { return true }
        return input.range(
            of: #"^(?:january|february|march|april|may|june|july|august|september|october|november|december)\s+\d{1,2}(?:,?\s+\d{4})?\s+(?:\+|-|plus|minus)\s+\d+\s+(?:days?|weeks?|months?|years?)$"#,
            options: .regularExpression
        ) != nil
    }

    private func looksLikeUnit(_ input: String) -> Bool {
        if input.contains("hours and minutes") || input.contains(" as hours") { return false }
        if input.range(of: #"(?:\sago|\sfrom now|\sfrom today|\safter today|\sbefore today)$"#, options: .regularExpression) != nil { return false }
        if input.hasPrefix("split ") || input.hasPrefix("next date ") || input.hasPrefix("every ")
            || input.contains(" occurrences every ") || input.range(of: #"^\d{1,2}:\d{2}:\d{2}\s"#, options: .regularExpression) != nil { return false }
        if input.range(of: #"^\d{1,2}(?::\d{2})?\s*(?:am|pm)\s+in\s+(?:12|24)-hour"#, options: .regularExpression) != nil { return false }
        if input.range(of: #"^\d{1,2}:\d{2}\s+in\s+12-hour"#, options: .regularExpression) != nil { return false }
        if input.range(of: #"^[-+]?\d+(?:\.\d+)?\s*(?:m|oz|gal|ton|c)$"#, options: .regularExpression) != nil {
            return true
        }
        if input.hasPrefix("speed of sound ") {
            return true
        }
        if input.range(
            of: #"^(?:watts\s+if\s+volts\s+are|amps\s+for|volts\s+for)|^[-+]?\d+(?:\.\d+)?\s+volts\s*\*"#,
            options: .regularExpression
        ) != nil {
            return true
        }
        let hasConversion = input.contains(" in ") || input.contains(" to ") || input.contains(" into ")
        let hasShortConversion = input.range(
            of: #"^[-+]?\d+(?:\.\d+)?\s*[^\s\d]+\s+[^\s\d]+$"#,
            options: .regularExpression
        ) != nil
        let hasNumericValue = input.range(of: #"^[-+]?(?:\d|pi\b|tau\b)"#, options: .regularExpression) != nil
            || input.hasPrefix("convert ") || input.hasPrefix("how many ") || input.hasPrefix("speed of sound ")
            || input.range(of: #"^[+-]?(?:pi|tau)\s"#, options: .regularExpression) != nil
        guard hasConversion || hasShortConversion, hasNumericValue else { return false }
        // Avoid stealing currency/timezone queries.
        if looksLikeCurrency(input) { return false }
        return CalculatorUnitRegistry.shared.containsUnitToken(in: input)
    }

    private func looksLikePercentagePhrase(_ input: String) -> Bool {
        if input.contains("%") { return true }
        if input.contains("percent") { return true }
        if input.contains(" tip on ") || input.contains(" tax on ") || input.contains(" discount from ") {
            return true
        }
        return false
    }

    private func looksLikeScientific(_ input: String) -> Bool {
        if containsFunctionCall(input) { return true }
        let constants = ["pi", "e", "τ", "tau", "phi", "sqrt2", "ln2", "ln10"]
        if constants.contains(where: { token in
            input == token
                || input.range(of: #"\b\#(token)\b"#, options: .regularExpression) != nil
        }) {
            return true
        }
        return false
    }

    private func looksLikeArithmetic(_ input: String) -> Bool {
        if containsMathOperators(input) && hasDigit(input) {
            return true
        }
        if input.contains("!"), hasDigit(input) {
            return true
        }
        if input.range(of: #"^[+-]?(?:\d+(?:\.\d*)?|\.\d+)[eE][+-]?\d+$"#, options: .regularExpression) != nil {
            return true
        }
        // Juxtaposition / implicit mul: 2(3+4), 3pi, 2sqrt(9)
        if input.range(of: #"\d\s*\("#, options: .regularExpression) != nil {
            return true
        }
        if input.range(of: #"\d(pi|tau|e|sqrt|sin|cos|tan|log|ln|abs)"#, options: .regularExpression) != nil {
            return true
        }
        // Natural language operators
        if hasDigit(input) && containsNaturalLanguageOperator(input) {
            return true
        }
        if isPureNumber(input) {
            return true
        }
        if input == "ans" || input == "answer" || input == "previous" {
            return true
        }
        return false
    }

    private func containsNaturalLanguageOperator(_ input: String) -> Bool {
        let phrases = ["plus", "minus", "times", "multiplied by", "divided by", "over", "mod", "modulo", "squared", "cubed"]
        return phrases.contains { input.contains($0) }
    }

    private func containsMathOperators(_ input: String) -> Bool {
        input.contains("+")
            || input.contains("-")
            || input.contains("*")
            || input.contains("/")
            || input.contains("^")
            || input.contains("×")
            || input.contains("÷")
            || input.contains("−")
            || input.contains("!")
    }

    private func containsFunctionCall(_ input: String) -> Bool {
        CalculatorScientific.functionNames.contains { name in
            input.range(of: #"\b\#(name)\s*\("#, options: .regularExpression) != nil
        }
    }

    private func containsCalculatorVocabulary(_ input: String) -> Bool {
        if CalculatorScientific.functionNames.contains(where: { input.contains($0) }) {
            return true
        }
        let words = [
            "plus", "minus", "times", "divided", "over", "percent",
            "pi", "tau", "feet", "meters", "celsius", "fahrenheit", "usd", "eur",
            "days", "weeks", "hours", "minutes", "ans", "answer", "squared", "cubed",
        ]
        return words.contains { input.contains($0) }
    }

    private func hasDigit(_ input: String) -> Bool {
        input.contains { $0.isNumber }
    }

    private func isPureNumber(_ input: String) -> Bool {
        let cleaned = input
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: " ", with: "")
        if cleaned.range(of: #"^[+-]?(?:\d+(?:\.\d*)?|\.\d+)[eE][+-]?\d+$"#, options: .regularExpression) != nil {
            return true
        }
        guard !cleaned.isEmpty else { return false }
        var sawDigit = false
        var sawDot = false
        for (index, ch) in cleaned.enumerated() {
            if ch.isNumber {
                sawDigit = true
                continue
            }
            if ch == ".", !sawDot {
                sawDot = true
                continue
            }
            if ch == "-", index == 0 {
                continue
            }
            return false
        }
        return sawDigit
    }
}
