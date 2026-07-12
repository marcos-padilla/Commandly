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

        text = replaceNaturalLanguageAliases(in: text)
        text = replaceAnswerAliases(in: text, previousAnswer: context.previousAnswer)

        // Contextual `x` multiplication: digit/paren x digit/paren/identifier
        text = replaceContextualX(in: text)

        // Strip thousands separators: 1,250 / 5 → 1250 / 5 (keep decimals).
        text = stripThousandsSeparators(text)

        let display = text
        return NormalizedInput(original: raw, text: text, displayExpression: display)
    }

    private func stripThousandsSeparators(_ input: String) -> String {
        // Remove commas that are thousands separators: digit,digit{3}(?!\d)
        var result = input
        while let regex = try? NSRegularExpression(pattern: #"(\d),(\d{3})(?!\d)"#),
              let match = regex.firstMatch(in: result, range: NSRange(result.startIndex..., in: result)),
              let full = Range(match.range, in: result),
              let g1 = Range(match.range(at: 1), in: result),
              let g2 = Range(match.range(at: 2), in: result)
        {
            result.replaceSubrange(full, with: "\(result[g1])\(result[g2])")
        }
        return result
    }

    private func replaceNaturalLanguageAliases(in input: String) -> String {
        var text = input
        // Multi-word first.
        let phrases: [(String, String)] = [
            ("multiplied by", "*"),
            ("divided by", "/"),
            ("square root of", "sqrt"),
            ("percent of", "% of"),
            ("percentage of", "% of"),
            ("plus", "+"),
            ("minus", "-"),
            ("times", "*"),
            ("over", "/"),
            ("squared", "^2"),
            ("cubed", "^3"),
            ("percent", "%"),
            ("percentage", "%"),
        ]

        // Case-insensitive word replacements.
        for (phrase, replacement) in phrases {
            text = replaceCaseInsensitivePhrase(phrase, with: replacement, in: text)
        }
        return text
    }

    private func replaceAnswerAliases(in input: String, previousAnswer: Decimal?) -> String {
        var text = input
        let aliases = ["previous answer", "previous", "answer", "ans"]
        for alias in aliases {
            guard let range = text.range(of: #"\b\#(alias)\b"#, options: [.regularExpression, .caseInsensitive]) else {
                continue
            }
            if let previousAnswer {
                let rendered = NSDecimalNumber(decimal: previousAnswer).stringValue
                text.replaceSubrange(range, with: rendered)
            } else {
                // Leave token for lexer/parser to fail with a clear error.
                text.replaceSubrange(range, with: "ans")
            }
        }
        return text
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
}
