import Foundation

/// Normalized calculator input ready for specialized evaluators or the lexer.
struct NormalizedInput: Sendable, Equatable {
    let original: String
    let text: String
    let displayExpression: String
}

/// Normalizes unicode operators, whitespace, NL aliases, and answer references.
struct CalculatorNormalizer: Sendable {
    func normalize(_ raw: String, context: CalculatorEvaluationContext) -> NormalizedInput {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        // Unicode whitespace / NBSP
        text = text
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: "\u{202F}", with: " ")
            .replacingOccurrences(of: "\t", with: " ")

        while text.contains("  ") {
            text = text.replacingOccurrences(of: "  ", with: " ")
        }

        // Unicode operators
        let operatorMap: [(String, String)] = [
            ("×", "*"),
            ("⋅", "*"),
            ("·", "*"),
            ("÷", "/"),
            ("−", "-"),
            ("–", "-"),
            ("—", "-"),
            ("π", "pi"),
            ("τ", "tau"),
        ]
        for (from, to) in operatorMap {
            text = text.replacingOccurrences(of: from, with: to)
        }

        text = replaceUnicodeMath(in: text)
        text = replaceNaturalLanguageAliases(in: text)
        text = replaceNumberWords(in: text)
        text = replaceAnswerAliases(in: text, previousAnswer: context.previousAnswer, previousValue: context.previousValue)
        text = replaceVariables(in: text, variables: context.variables)

        // Contextual `x` multiplication: digit/paren x digit/paren/identifier
        text = replaceContextualX(in: text)

        text = normalizeNumberSeparators(text, locale: context.locale)
        text = expandMagnitudeWords(text)

        let display = text
        return NormalizedInput(original: raw, text: text, displayExpression: display)
    }

    private func normalizeNumberSeparators(_ input: String, locale: Locale) -> String {
        var result = input
        let decimal = locale.decimalSeparator ?? "."
        let grouping = locale.groupingSeparator ?? ","

        // Apostrophes and spaces are grouping only when followed by an exact
        // three-digit group. This deliberately leaves mixed numbers (`2 1/4`)
        // alone for phrase parsing.
        result = replacingMatches(#"(?<=\d)['’](?=\d{3}(?:\D|$))"#, with: "", in: result)
        result = replacingMatches(#"(?<=\d) (?=\d{3}(?:\D|$))"#, with: "", in: result)

        if grouping != decimal, !grouping.isEmpty {
            let escaped = NSRegularExpression.escapedPattern(for: grouping)
            result = replacingMatches("(?<=\\d)\(escaped)(?=\\d{3}(?:\\D|$))", with: "", in: result)
        }
        if decimal != "." {
            let escaped = NSRegularExpression.escapedPattern(for: decimal)
            result = replacingMatches("(?<=\\d)\(escaped)(?=\\d)", with: ".", in: result)
        }
        return result
    }

    private func replaceUnicodeMath(in input: String) -> String {
        var text = input
        let replacements: [(String, String)] = [
            ("½", "(1/2)"), ("¼", "(1/4)"), ("¾", "(3/4)"),
            ("⅓", "(1/3)"), ("⅔", "(2/3)"), ("⅛", "(1/8)"),
            ("²", "^2"), ("³", "^3"), ("√", "sqrt "),
        ]
        for (source, replacement) in replacements {
            text = text.replacingOccurrences(of: source, with: replacement)
        }
        text = replacingMatches(#"\|\s*([^|]+?)\s*\|"#, with: "abs($1)", in: text)
        text = replacingMatches(#"\*\*"#, with: "^", in: text)
        return text
    }

    private func expandMagnitudeWords(_ input: String) -> String {
        var result = input
        let pattern = #"(\d+(?:\.\d+)?)\s+(thousand|million|billion)\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return input }
        while let match = regex.firstMatch(in: result, range: NSRange(result.startIndex..<result.endIndex, in: result)),
              let fullRange = Range(match.range(at: 0), in: result),
              let valueRange = Range(match.range(at: 1), in: result),
              let magnitudeRange = Range(match.range(at: 2), in: result),
              let value = Decimal(string: String(result[valueRange]), locale: Locale(identifier: "en_US_POSIX"))
        {
            let factor: Decimal
            switch result[magnitudeRange].lowercased() {
            case "thousand": factor = 1_000
            case "million": factor = 1_000_000
            default: factor = 1_000_000_000
            }
            result.replaceSubrange(fullRange, with: NSDecimalNumber(decimal: value * factor).stringValue)
        }
        return result
    }

    private func replaceNaturalLanguageAliases(in input: String) -> String {
        var text = input
        // Case-insensitive word replacements.
        // The shared lexicon is ordered with multi-word rules first.
        for (phrase, replacement) in CalculatorLanguageLexicon.normalizationRules {
            text = replaceCaseInsensitivePhrase(phrase, with: replacement, in: text)
        }
        text = stripCommandPrefix(text)
        text = rewritePrefixFunction("sqrt", in: text)
        text = rewritePrefixFunction("cbrt", in: text)
        text = rewritePrefixFunction("abs", in: text)
        text = rewritePrefixFunction("factorial", in: text)
        text = rewritePrefixFunction("ln", in: text)
        text = rewriteNamedFractions(in: text)
        text = rewriteNaturalFunctions(in: text)
        text = rewriteExplicitAngles(in: text)
        text = rewriteUnitQuestion(in: text)
        return text
    }

    private func stripCommandPrefix(_ input: String) -> String {
        replacingMatches(CalculatorLanguageLexicon.commandPrefixPattern, with: "", in: input)
    }

    private func rewritePrefixFunction(_ name: String, in input: String) -> String {
        let escaped = NSRegularExpression.escapedPattern(for: name)
        return replacingMatches("^\(escaped)\\s+(.+)$", with: "\(name)($1)", in: input)
    }

    private func rewriteNamedFractions(in input: String) -> String {
        var text = input
        let exact: [(String, String)] = [
            ("one half", "1/2"), ("a half", "1/2"),
            ("one quarter", "1/4"), ("three quarters", "3/4"),
            ("one third", "1/3"), ("two thirds", "2/3"),
        ]
        for (phrase, replacement) in exact {
            text = replaceCaseInsensitivePhrase(phrase, with: replacement, in: text)
        }
        text = replacingMatches(#"\b(\d+)\s+and\s+(\d+)/(\d+)\b"#, with: "($1+$2/$3)", in: text)
        text = replacingMatches(#"\b(\d+)\s+(\d+)/(\d+)\b"#, with: "($1+$2/$3)", in: text)
        text = replacingMatches(#"\b(\d+)\s+and\s+(1/2|1/4|3/4|1/3|2/3)\b"#, with: "($1+$2)", in: text)
        let words = ["one": "1", "two": "2", "three": "3", "four": "4", "five": "5", "six": "6", "seven": "7", "eight": "8", "nine": "9"]
        for (word, digit) in words {
            text = replacingMatches("^\(word)\\s+and\\s+(1/2|1/4|3/4|1/3|2/3)$", with: "(\(digit)+$1)", in: text)
        }
        return text
    }

    private func rewriteNaturalFunctions(in input: String) -> String {
        var text = input
        text = replacingMatches(#"^fifth\s+root\s+of\s+(.+)$"#, with: "nthroot($1,5)", in: text)
        text = replacingMatches(#"^remainder\s+of\s+(.+?)\s*/\s*(.+)$"#, with: "$1 mod $2", in: text)
        text = replacingMatches(#"^(.+?)\s+remainder\s+(.+)$"#, with: "$1 mod $2", in: text)
        text = replacingMatches(#"^(?:minimum|min)\s+of\s+(.+)$"#, with: "min($1)", in: text)
        text = replacingMatches(#"^(?:maximum|max)\s+of\s+(.+)$"#, with: "max($1)", in: text)
        text = replacingMatches(#"^log\s+base\s+([0-9.]+)\s+of\s+(.+)$"#, with: "log($2,$1)", in: text)
        text = replacingMatches(#"^base\s+10\s+log\s+of\s+(.+)$"#, with: "log10($1)", in: text)
        text = replacingMatches(#"^([0-9]+)\s+choose\s+([0-9]+)$"#, with: "ncr($1,$2)", in: text)
        text = replacingMatches(#"^([0-9]+)\s+permutations?\s+of\s+([0-9]+)$"#, with: "npr($1,$2)", in: text)
        text = replacingMatches(#"^greatest\s+common\s+divisor\s+of\s+(.+?)\s+and\s+(.+)$"#, with: "gcd($1,$2)", in: text)
        text = replacingMatches(#"^least\s+common\s+multiple\s+of\s+(.+?)\s+and\s+(.+)$"#, with: "lcm($1,$2)", in: text)
        text = replacingMatches(#"^round\s+(.+?)\s+to\s+([0-9]+)\s+decimal\s+places?$"#, with: "round($1,$2)", in: text)
        text = replacingMatches(#"^standard\s+deviation\s+of\s+(.+)$"#, with: "stddev($1)", in: text)
        text = replacingMatches(#"^(.+?)\s+raised\s+to\s+the\s+tenth\s+power$"#, with: "($1)^10", in: text)
        text = replacingMatches(#"^(.+?)\s*\^\s*tenth\s+power$"#, with: "($1)^10", in: text)
        if text.hasPrefix("min(") || text.hasPrefix("max(") {
            text = replacingMatches(#"\s+and\s+"#, with: ",", in: text)
        }
        return text
    }

    private func rewriteExplicitAngles(in input: String) -> String {
        var text = input
        for function in ["sin", "cos", "tan"] {
            text = replacingMatches(
                "\\b\(function)\\(\\s*(.+?)\\s+(?:deg|degree|degrees)\\s*\\)",
                with: "\(function)d($1)",
                in: text
            )
            text = replacingMatches(
                "\\b\(function)\\(\\s*(.+?)\\s+(?:rad|radian|radians)\\s*\\)",
                with: "\(function)($1)",
                in: text
            )
        }
        return text
    }

    private func rewriteUnitQuestion(in input: String) -> String {
        replacingMatches(
            #"^how\s+many\s+(.+?)\s+are\s+in\s+([-+]?\d+(?:\.\d+)?)\s+(.+)$"#,
            with: "$2 $3 in $1",
            in: input
        )
    }

    /// Rewrites contiguous English number words without changing surrounding prose.
    /// The pass is linear over regex matches and runs before tokenization.
    private func replaceNumberWords(in input: String) -> String {
        let numberWords = [
            "zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine",
            "ten", "eleven", "twelve", "thirteen", "fourteen", "fifteen", "sixteen", "seventeen",
            "eighteen", "nineteen", "twenty", "thirty", "forty", "fifty", "sixty", "seventy",
            "eighty", "ninety", "hundred", "thousand", "million", "billion", "point",
        ]
        let alternatives = numberWords.joined(separator: "|")
        let pattern = "\\b(?:negative[\\s-]+)?(?:\(alternatives))(?:(?:[\\s-]+)(?:and[\\s-]+)?(?:\(alternatives)))*\\b"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return input
        }
        var result = input
        let matches = regex.matches(in: result, range: NSRange(result.startIndex..<result.endIndex, in: result))
        for match in matches.reversed() {
            guard let range = Range(match.range, in: result) else {
                continue
            }
            let phrase = String(result[range])
            let lowercasedPhrase = phrase.lowercased()
            if ["thousand", "million", "billion"].contains(lowercasedPhrase) {
                let prefix = String(result[..<range.lowerBound])
                if prefix.range(of: #"\d\s+$"#, options: .regularExpression) != nil {
                    // Preserve numeric magnitude forms such as `1 million` for
                    // `expandMagnitudeWords`, which runs after locale handling.
                    continue
                }
            }
            guard let value = parseNumberWords(phrase)
            else {
                continue
            }
            result.replaceSubrange(range, with: NSDecimalNumber(decimal: value).stringValue)
        }
        return result
    }

    private func parseNumberWords(_ phrase: String) -> Decimal? {
        let values: [String: Int64] = [
            "zero": 0, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5,
            "six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10,
            "eleven": 11, "twelve": 12, "thirteen": 13, "fourteen": 14,
            "fifteen": 15, "sixteen": 16, "seventeen": 17, "eighteen": 18,
            "nineteen": 19, "twenty": 20, "thirty": 30, "forty": 40,
            "fifty": 50, "sixty": 60, "seventy": 70, "eighty": 80, "ninety": 90,
        ]
        let tokens = phrase.lowercased().split(whereSeparator: { $0.isWhitespace || $0 == "-" }).map(String.init)
        guard tokens.isEmpty == false else { return nil }
        let isNegative = tokens.first == "negative"
        let significant = tokens.dropFirst(isNegative ? 1 : 0).filter { $0 != "and" }
        guard significant.isEmpty == false else { return nil }

        var total: Int64 = 0
        var group: Int64 = 0
        var fractionalDigits = ""
        var isFractional = false

        for token in significant {
            if token == "point" {
                guard isFractional == false else { return nil }
                isFractional = true
                continue
            }
            if isFractional {
                guard let digit = values[token], (0...9).contains(digit) else { return nil }
                fractionalDigits.append(String(digit))
                continue
            }
            if let value = values[token] {
                group += value
            } else if token == "hundred" {
                group = max(group, 1) * 100
            } else {
                let scale: Int64
                switch token {
                case "thousand": scale = 1_000
                case "million": scale = 1_000_000
                case "billion": scale = 1_000_000_000
                default: return nil
                }
                total += max(group, 1) * scale
                group = 0
            }
        }
        guard isFractional == false || fractionalDigits.isEmpty == false else { return nil }
        let integer = total + group
        let rendered = fractionalDigits.isEmpty ? String(integer) : "\(integer).\(fractionalDigits)"
        guard var decimal = Decimal(string: rendered, locale: Locale(identifier: "en_US_POSIX")) else { return nil }
        if isNegative { decimal *= -1 }
        return decimal
    }

    private func replaceAnswerAliases(
        in input: String,
        previousAnswer: Decimal?,
        previousValue: CalculatorValue?
    ) -> String {
        var text = input
        let aliases = ["previous answer", "last result", "previous", "answer", "ans"]
        for alias in aliases {
            guard let range = text.range(of: #"\b\#(alias)\b"#, options: [.regularExpression, .caseInsensitive]) else {
                continue
            }
            if let rendered = renderPrevious(previousValue) ?? previousAnswer.map({ NSDecimalNumber(decimal: $0).stringValue }) {
                text.replaceSubrange(range, with: rendered)
            } else {
                // Leave token for lexer/parser to fail with a clear error.
                text.replaceSubrange(range, with: "ans")
            }
        }
        return text
    }

    private func renderPrevious(_ value: CalculatorValue?) -> String? {
        switch value {
        case .decimal(let value): return NSDecimalNumber(decimal: value).stringValue
        case .double(let value): return String(value)
        case .measurement(let value): return "\(value.value) \(value.unitIdentifier)"
        case .currency(let value): return "\(NSDecimalNumber(decimal: value.amount).stringValue) \(value.code.rawValue)"
        case .date, .timeZoneInstant, .text, .none: return nil
        }
    }

    private func replaceVariables(in input: String, variables: [String: CalculatorVariable]) -> String {
        if input.range(of: #"^\s*[a-z][a-z0-9_ ]*\s*=\s*.+$"#, options: [.regularExpression, .caseInsensitive]) != nil
            || input.range(of: #"^\s*(?:save|set)\s+"#, options: [.regularExpression, .caseInsensitive]) != nil {
            return input
        }
        var result = input
        for name in variables.keys.sorted(by: { $0.count > $1.count }) {
            guard let variable = variables[name] else { continue }
            let escaped = NSRegularExpression.escapedPattern(for: name)
            let renderedValue = NSDecimalNumber(decimal: variable.isPercentage ? variable.value * 100 : variable.value).stringValue
            let rendered = variable.isPercentage ? "\(renderedValue)%" : renderedValue
            result = replacingMatches("(?<![a-z0-9_])\(escaped)(?![a-z0-9_])", with: rendered, in: result)
        }
        result = replacingMatches(#"^(.+?)\s*\+\s*([\d.]+)%\s+tip$"#, with: "$1 + $2%", in: result)
        return result
    }

    private func replaceContextualX(in input: String) -> String {
        // Replace "x" / "X" used as multiply between values: 2 x 3, (2)x(3), 2x3
        var result = ""
        let chars = Array(input)
        var index = 0
        while index < chars.count {
            let ch = chars[index]
            if (ch == "x" || ch == "X") && isMultiplicationX(chars, at: index) {
                result.append("*")
                index += 1
                continue
            }
            result.append(ch)
            index += 1
        }
        return result
    }

    private func isMultiplicationX(_ chars: [Character], at index: Int) -> Bool {
        // Only treat a standalone `x` as multiply — never rewrite letters inside words (e.g. "tax").
        let leftAdjacent = index > 0 ? chars[index - 1] : nil
        let rightAdjacent = index + 1 < chars.count ? chars[index + 1] : nil
        if leftAdjacent?.isLetter == true || rightAdjacent?.isLetter == true {
            return false
        }

        let left = nearestNonSpace(chars, from: index - 1, step: -1)
        let right = nearestNonSpace(chars, from: index + 1, step: 1)
        guard let left, let right else { return false }

        let leftOK = left.isNumber || left == ")"
        let rightOK = right.isNumber || right == "(" || right.isLetter
        // Avoid hex-looking sequences: 0xFF
        if left == "0" && (right == "F" || right == "f" || right.isHexDigit) {
            return false
        }
        return leftOK && rightOK
    }

    private func nearestNonSpace(_ chars: [Character], from start: Int, step: Int) -> Character? {
        var i = start
        while i >= 0 && i < chars.count {
            if chars[i] != " " {
                return chars[i]
            }
            i += step
        }
        return nil
    }

    private func replaceCaseInsensitivePhrase(_ phrase: String, with replacement: String, in text: String) -> String {
        var result = text
        let pattern = #"\b\#(NSRegularExpression.escapedPattern(for: phrase))\b"#
        while let range = result.range(of: pattern, options: [.regularExpression, .caseInsensitive]) {
            result.replaceSubrange(range, with: replacement)
        }
        return result
    }

    private func replacingMatches(_ pattern: String, with replacement: String, in input: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return input }
        let range = NSRange(input.startIndex..<input.endIndex, in: input)
        return regex.stringByReplacingMatches(in: input, options: [], range: range, withTemplate: replacement)
    }
}
