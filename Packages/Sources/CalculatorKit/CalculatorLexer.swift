import Foundation

/// Lexical token kinds produced by `CalculatorLexer`.
enum TokenKind: Sendable, Equatable {
    case number(Decimal)
    case identifier(String)
    case plus
    case minus
    case star
    case slash
    case caret
    case percent
    case factorial
    case leftParen
    case rightParen
    case comma
    case eof
}

/// A token with source location.
struct Token: Sendable, Equatable {
    let kind: TokenKind
    let location: SourceLocation
    let lexeme: String
}

/// Converts normalized calculator text into tokens.
struct CalculatorLexer: Sendable {
    func tokenize(_ input: String, locale: Locale) throws -> [Token] {
        var tokens: [Token] = []
        let chars = Array(input)
        var index = 0

        while index < chars.count {
            let ch = chars[index]
            if ch.isWhitespace {
                index += 1
                continue
            }

            let location = SourceLocation(index: index)

            switch ch {
            case "+":
                tokens.append(Token(kind: .plus, location: location, lexeme: "+"))
                index += 1
            case "-":
                tokens.append(Token(kind: .minus, location: location, lexeme: "-"))
                index += 1
            case "*":
                tokens.append(Token(kind: .star, location: location, lexeme: "*"))
                index += 1
            case "/":
                tokens.append(Token(kind: .slash, location: location, lexeme: "/"))
                index += 1
            case "^":
                tokens.append(Token(kind: .caret, location: location, lexeme: "^"))
                index += 1
            case "%":
                tokens.append(Token(kind: .percent, location: location, lexeme: "%"))
                index += 1
            case "!":
                tokens.append(Token(kind: .factorial, location: location, lexeme: "!"))
                index += 1
            case "(":
                tokens.append(Token(kind: .leftParen, location: location, lexeme: "("))
                index += 1
            case ")":
                tokens.append(Token(kind: .rightParen, location: location, lexeme: ")"))
                index += 1
            case ",":
                // Ambiguous: grouping separator vs argument separator.
                // If followed by a digit and we are mid-number context, handled in number scan.
                // Standalone comma between expressions is argument separator.
                tokens.append(Token(kind: .comma, location: location, lexeme: ","))
                index += 1
            default:
                if ch.isNumber || ch == "." {
                    let (token, nextIndex) = try scanNumber(chars, start: index, locale: locale)
                    tokens.append(token)
                    index = nextIndex
                } else if ch.isLetter || ch == "_" {
                    let (token, nextIndex) = scanIdentifier(chars, start: index)
                    tokens.append(token)
                    index = nextIndex
                } else {
                    throw CalculatorError.unexpectedCharacter(ch, location)
                }
            }
        }

        tokens.append(Token(kind: .eof, location: SourceLocation(index: chars.count), lexeme: ""))
        return tokens
    }

    private func scanNumber(_ chars: [Character], start: Int, locale: Locale) throws -> (Token, Int) {
        var index = start
        var raw = ""
        var sawDot = false
        var sawExponent = false

        // Locale-aware: treat grouping separators carefully.
        let decimalSeparator = locale.decimalSeparator ?? "."
        let groupingSeparator = locale.groupingSeparator ?? ","

        while index < chars.count {
            let ch = chars[index]
            if ch.isNumber {
                raw.append(ch)
                index += 1
                continue
            }

            if (ch == "e" || ch == "E"), !sawExponent, !raw.isEmpty {
                let signIndex = index + 1
                let digitIndex = signIndex < chars.count && (chars[signIndex] == "+" || chars[signIndex] == "-")
                    ? signIndex + 1
                    : signIndex
                if digitIndex < chars.count, chars[digitIndex].isNumber {
                    raw.append("e")
                    if digitIndex != signIndex {
                        raw.append(chars[signIndex])
                    }
                    index = digitIndex
                    sawExponent = true
                    continue
                }
            }

            let chString = String(ch)
            if chString == decimalSeparator && !sawDot {
                let next = index + 1 < chars.count ? chars[index + 1] : nil
                // A leading point needs a following digit; a populated literal
                // may end in a point (`5.`) as accepted by the grammar.
                if raw.isEmpty, next?.isNumber != true { break }
                raw.append(".")
                sawDot = true
                index += 1
                continue
            }

            if chString == groupingSeparator {
                // Never consume commas here — argument lists use `,` and
                // thousands separators are stripped in normalization (`1,250` → `1250`).
                break
            }

            // ASCII fallback: allow '.' as decimal when locale uses another sep but input uses '.'
            if ch == ".", !sawDot, decimalSeparator != "." {
                let next = index + 1 < chars.count ? chars[index + 1] : nil
                if next?.isNumber == true {
                    raw.append(".")
                    sawDot = true
                    index += 1
                    continue
                }
            }

            break
        }

        if raw.isEmpty || raw == "." {
            throw CalculatorError.invalidNumber(String(chars[start..<min(start + 1, chars.count)]), SourceLocation(index: start))
        }

        guard let decimal = Decimal(string: raw, locale: Locale(identifier: "en_US_POSIX")) else {
            throw CalculatorError.invalidNumber(raw, SourceLocation(index: start))
        }

        let lexeme = String(chars[start..<index])
        return (Token(kind: .number(decimal), location: SourceLocation(index: start), lexeme: lexeme), index)
    }

    private func scanIdentifier(_ chars: [Character], start: Int) -> (Token, Int) {
        var index = start
        while index < chars.count {
            let ch = chars[index]
            if ch.isLetter || ch.isNumber || ch == "_" {
                index += 1
            } else {
                break
            }
        }
        let lexeme = String(chars[start..<index]).lowercased()
        return (Token(kind: .identifier(lexeme), location: SourceLocation(index: start), lexeme: lexeme), index)
    }
}
