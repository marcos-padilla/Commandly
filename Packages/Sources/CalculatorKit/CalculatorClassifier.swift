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
        if looksIncomplete(lowered) {
            return ClassificationResult(intent: .incomplete, confidence: .medium)
        }
        if looksLikeCurrency(lowered) {
            return ClassificationResult(intent: .currencyConversion, confidence: .high)
        }
        if looksLikeTimeZone(lowered) {
            return ClassificationResult(intent: .timeZoneConversion, confidence: .high)
        }
        if looksLikeDate(lowered) {
            return ClassificationResult(intent: .dateCalculation, confidence: .high)
        }
        if looksLikeUnit(lowered) {
            return ClassificationResult(intent: .unitConversion, confidence: .high)
        }
        if looksLikePercentagePhrase(lowered) {
            return ClassificationResult(intent: .percentage, confidence: .high)
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
        let wordSuffixes = ["of", "in", "to", "into", "as", "from", "on", "tip", "tax", "discount", "plus", "minus", "times"]
        for suffix in wordSuffixes {
            if trimmed == suffix { return true }
            if trimmed.hasSuffix(" " + suffix) { return true }
        }

        let open = trimmed.filter { $0 == "(" }.count
        let close = trimmed.filter { $0 == ")" }.count
        return open > close
    }

    private func looksLikeCurrency(_ input: String) -> Bool {
        let hasConversion = input.contains(" in ") || input.contains(" to ") || input.contains(" into ") || input.contains(" as ")
        guard hasConversion, hasDigit(input) else { return false }

        let tokens = input.split(whereSeparator: { $0.isWhitespace || $0 == "," }).map(String.init)
        let hasKnownCode = tokens.contains { Self.knownCurrencyCodes.contains($0) }
        let hasSymbol = input.contains("$") || input.contains("€") || input.contains("£") || input.contains("¥")
        return hasKnownCode || hasSymbol
    }

    private func looksLikeTimeZone(_ input: String) -> Bool {
        let timezoneWords = ["timezone", "time zone", "current time in", "time difference"]
        if timezoneWords.contains(where: { input.contains($0) }) {
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
            "days from", "weeks from", "months from", "years from",
            "days until", "weeks until", "months until",
            "days after", "days before", "weeks after", "weeks before",
            "weeks between", "days between",
            "next monday", "next tuesday", "next wednesday", "next thursday",
            "next friday", "next saturday", "next sunday",
            "last monday", "last friday",
            "end of this month", "start of next year", "from now", "from today",
        ]
        return datePhrases.contains(where: { input.contains($0) })
    }

    private func looksLikeUnit(_ input: String) -> Bool {
        let hasConversion = input.contains(" in ") || input.contains(" to ") || input.contains(" into ")
        guard hasConversion, hasDigit(input) else { return false }
        // Avoid stealing currency/timezone queries.
        if looksLikeCurrency(input) || looksLikeTimeZone(input) { return false }
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
        let constants = ["pi", "τ", "tau"]
        if constants.contains(where: { token in
            input == token
                || input.range(of: #"\b\#(token)\b"#, options: .regularExpression) != nil
                || input.contains(token) && hasDigit(input)
        }) {
            return true
        }
        return false
    }

    private func looksLikeArithmetic(_ input: String) -> Bool {
        if containsMathOperators(input) && hasDigit(input) {
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
        let phrases = ["plus", "minus", "times", "multiplied by", "divided by", "over", "squared", "cubed"]
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
