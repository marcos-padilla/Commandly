import Foundation

/// Expression AST produced by the recursive-descent parser.
indirect enum Expression: Sendable, Equatable {
    case number(Decimal)
    case constant(String)
    case answer
    case unary(UnaryOperator, Expression)
    case binary(BinaryOperator, Expression, Expression)
    case percentOf(Expression, Expression) // percent, base  → percent% of base
    case postfixPercent(Expression)
    case factorial(Expression)
    case call(String, [Expression])
    /// Contextual: base + percent% or base - percent%
    case percentAdjust(BinaryOperator, Expression, Expression)
}

enum UnaryOperator: Sendable, Equatable {
    case plus
    case minus
}

enum BinaryOperator: Sendable, Equatable {
    case add
    case subtract
    case multiply
    case divide
    case modulo
    case power
}

/// Recursive-descent parser with documented precedence.
///
/// Precedence (low → high):
/// 1. `+` `-` (left-associative)
/// 2. `*` `/` `%`(modulo) (left-associative); contextual `+ %` / `- %` handled specially
/// 3. unary `+` `-`
/// 4. `^` (right-associative)
/// 5. postfix `%`
/// 6. primary / implicit multiplication
///
/// Documented decisions:
/// - `-5^2` = `-(5^2)` = `-25` (unary applies outside exponentiation)
/// - `2^3^2` = `2^(3^2)` = `512` (right-associative exponentiation)
struct CalculatorParser: Sendable {
    private var tokens: [Token] = []
    private var current = 0

    mutating func parse(_ tokens: [Token]) throws -> Expression {
        self.tokens = tokens
        self.current = 0
        let expression = try parseExpression()
        if !isAtEnd {
            let token = peek
            throw CalculatorError.unexpectedToken(token.lexeme, token.location)
        }
        return expression
    }

    // MARK: - Grammar

    private mutating func parseExpression() throws -> Expression {
        try parseAdditive()
    }

    private mutating func parseAdditive() throws -> Expression {
        var left = try parseMultiplicative()

        while match(.plus) || match(.minus) {
            let op: BinaryOperator = previous.kind == .plus ? .add : .subtract
            // Contextual percentage: base + 15% / base - 15%
            if isNumberOrPrimaryStart() {
                let right = try parseMultiplicative()
                if case .postfixPercent(let percentExpr) = right {
                    left = .percentAdjust(op, left, percentExpr)
                    continue
                }
                left = .binary(op, left, right)
            } else {
                let right = try parseMultiplicative()
                left = .binary(op, left, right)
            }
        }
        return left
    }

    private mutating func parseMultiplicative() throws -> Expression {
        var left = try parseUnary()

        while true {
            if match(.star) || match(.slash) {
                let op: BinaryOperator = previous.kind == .star ? .multiply : .divide
                let right = try parseUnary()
                if op == .multiply, case .postfixPercent(let percentExpr) = right {
                    // 350 * 20% → 20% of 350
                    left = .percentOf(percentExpr, left)
                } else {
                    left = .binary(op, left, right)
                }
                continue
            }

            // Binary modulo: only when `%` is between two values and not postfix.
            // Postfix percent is handled in parsePostfix. Modulo uses keyword `mod`
            // or explicit `%` between numbers when next token starts a primary after `%`.
            // We treat identifier `mod` as modulo.
            if check(.identifier("mod")) || (check(.percent) && nextTokenStartsValue) {
                advance()
                let right = try parseUnary()
                left = .binary(.modulo, left, right)
                continue
            }

            // Implicit multiplication where unambiguous: 2(3+4), 3pi, 2sqrt(9)
            if canStartImplicitMultiplication() {
                let right = try parseUnary()
                left = .binary(.multiply, left, right)
                continue
            }

            break
        }
        return left
    }

    /// Unary binds looser than `^` so `-5^2` = `-(5^2)`.
    private mutating func parseUnary() throws -> Expression {
        if match(.plus) {
            return .unary(.plus, try parseUnary())
        }
        if match(.minus) {
            return .unary(.minus, try parseUnary())
        }
        return try parsePower()
    }

    /// Right-associative exponentiation.
    private mutating func parsePower() throws -> Expression {
        let base = try parsePostfix()
        if match(.caret) {
            let exponent = try parseUnary()
            return .binary(.power, base, exponent)
        }
        return base
    }

    private mutating func parsePostfix() throws -> Expression {
        var expression = try parsePrimary()
        while true {
            if check(.percent), !nextTokenStartsValue {
                advance()
                expression = .postfixPercent(expression)
            } else if match(.factorial) {
                expression = .factorial(expression)
            } else {
                break
            }
        }
        return expression
    }

    private mutating func parsePrimary() throws -> Expression {
        if matchNumber() {
            if case .number(let value) = previous.kind {
                return .number(value)
            }
        }

        if matchIdentifier() {
            let name: String
            if case .identifier(let identifier) = previous.kind {
                name = identifier
            } else {
                name = previous.lexeme
            }

            if name == "ans" || name == "answer" || name == "previous" {
                return .answer
            }

            if match(.leftParen) {
                var args: [Expression] = []
                if !check(.rightParen) {
                    repeat {
                        // Argument lists use commas; stop an argument before comma/paren.
                        args.append(try parseExpressionStoppingAtComma())
                    } while match(.comma)
                }
                try consume(.rightParen, message: "Expected ')' after arguments")
                return .call(name, args)
            }

            // Constant or bare identifier (unit names handled outside expression parser).
            return .constant(name)
        }

        if match(.leftParen) {
            let expression = try parseExpression()
            try consume(.rightParen, message: "Expected ')' after expression")
            return expression
        }

        throw CalculatorError.unexpectedToken(peek.lexeme.isEmpty ? "end" : peek.lexeme, peek.location)
    }

    private mutating func parseExpressionStoppingAtComma() throws -> Expression {
        // Same as parseExpression, but callers stop at comma via check in the arg loop.
        // The additive parser naturally stops before comma because comma is not an operator.
        try parseAdditive()
    }

    // MARK: - Helpers

    private func canStartImplicitMultiplication() -> Bool {
        switch peek.kind {
        case .leftParen:
            return true
        case .identifier:
            return true
        case .number:
            // 2 3 is ambiguous — disallow bare number juxtaposition.
            return false
        default:
            return false
        }
    }

    private func isNumberOrPrimaryStart() -> Bool {
        switch peek.kind {
        case .identifier, .leftParen, .number:
            return true
        default:
            return false
        }
    }

    private func checkIdentifierOrParenStart() -> Bool {
        isNumberOrPrimaryStart()
    }

    private var nextTokenStartsValue: Bool {
        guard current + 1 < tokens.count else { return false }
        switch tokens[current + 1].kind {
        case .number, .identifier, .leftParen, .plus, .minus:
            return true
        default:
            return false
        }
    }

    private var isAtEnd: Bool {
        if case .eof = peek.kind { return true }
        return false
    }

    private var peek: Token {
        tokens[current]
    }

    private var previous: Token {
        tokens[current - 1]
    }

    @discardableResult
    private mutating func advance() -> Token {
        if !isAtEnd {
            current += 1
        }
        return previous
    }

    private func check(_ kind: TokenKind) -> Bool {
        if isAtEnd { return false }
        return tokenKindsEqual(peek.kind, rhs: kind)
    }

    private mutating func match(_ kind: TokenKind) -> Bool {
        guard check(kind) else { return false }
        advance()
        return true
    }

    private mutating func matchNumber() -> Bool {
        if case .number = peek.kind {
            advance()
            return true
        }
        return false
    }

    private mutating func matchIdentifier() -> Bool {
        if case .identifier = peek.kind {
            advance()
            return true
        }
        return false
    }

    private mutating func consume(_ kind: TokenKind, message: String) throws {
        if check(kind) {
            advance()
            return
        }
        if kind == .rightParen {
            throw CalculatorError.missingClosingParenthesis(peek.location)
        }
        throw CalculatorError.unexpectedToken(message, peek.location)
    }

    private func tokenKindsEqual(_ lhs: TokenKind, rhs: TokenKind) -> Bool {
        switch (lhs, rhs) {
        case (.plus, .plus),
             (.minus, .minus),
             (.star, .star),
             (.slash, .slash),
             (.caret, .caret),
             (.percent, .percent),
             (.factorial, .factorial),
             (.leftParen, .leftParen),
             (.rightParen, .rightParen),
             (.comma, .comma),
             (.eof, .eof):
            return true
        case (.number, .number):
            return true
        case (.identifier(let a), .identifier(let b)):
            return a == b
        default:
            return false
        }
    }
}

/// Phrase-level percentage rewriter for `20% of 350`, tip/tax/discount forms.
enum PercentagePhraseParser {
    static func parse(_ text: String) -> (expression: Expression, tag: String?)? {
        let lowered = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        if let match = matchPattern(#"^([-+]?[0-9][0-9.,]*)\s*%\s*of\s*([-+]?[0-9][0-9.,]*)$"#, in: lowered) {
            return makePercentOf(percent: match.0, base: match.1, tagged: nil)
        }
        if let match = matchPattern(#"^([-+]?[0-9][0-9.,]*)\s*%\s*tip\s+on\s*([-+]?[0-9][0-9.,]*)$"#, in: lowered) {
            return makePercentOf(percent: match.0, base: match.1, tagged: "tip")
        }
        if let match = matchPattern(#"^tip\s+([-+]?[0-9][0-9.,]*)\s*%\s+on\s+([-+]?[0-9][0-9.,]*)$"#, in: lowered) {
            return makePercentOf(percent: match.0, base: match.1, tagged: "tip")
        }
        if let match = matchPattern(#"^([-+]?[0-9][0-9.,]*)\s*%\s*tax\s+on\s*([-+]?[0-9][0-9.,]*)$"#, in: lowered) {
            return makePercentOf(percent: match.0, base: match.1, tagged: "tax")
        }
        if let match = matchPattern(#"^([-+]?[0-9][0-9.,]*)\s*%\s*discount\s+from\s*([-+]?[0-9][0-9.,]*)$"#, in: lowered) {
            return makePercentOf(percent: match.0, base: match.1, tagged: "discount")
        }
        if let match = matchPattern(#"^([-+]?[0-9][0-9.,]*)\s*%\s*discount\s+(?:on|from)\s*([-+]?[0-9][0-9.,]*)$"#, in: lowered) {
            return makePercentOf(percent: match.0, base: match.1, tagged: "discount")
        }
        if let match = matchPattern(#"^(?:increase|add)\s+([-+]?[0-9][0-9.,]*)\s+(?:by\s+)?([-+]?[0-9][0-9.,]*)\s*%$"#, in: lowered) {
            return makePercentAdjustment(base: match.0, percent: match.1, operation: .add)
        }
        if let match = matchPattern(#"^add\s+([-+]?[0-9][0-9.,]*)\s*%\s+to\s+([-+]?[0-9][0-9.,]*)$"#, in: lowered) {
            return makePercentAdjustment(base: match.1, percent: match.0, operation: .add)
        }
        if let match = matchPattern(#"^(?:decrease|reduce)\s+([-+]?[0-9][0-9.,]*)\s+by\s+([-+]?[0-9][0-9.,]*)\s*%$"#, in: lowered) {
            return makePercentAdjustment(base: match.0, percent: match.1, operation: .subtract)
        }
        if let match = matchPattern(#"^subtract\s+([-+]?[0-9][0-9.,]*)\s*%\s+from\s+([-+]?[0-9][0-9.,]*)$"#, in: lowered) {
            return makePercentAdjustment(base: match.1, percent: match.0, operation: .subtract)
        }
        if let match = matchPattern(#"^(?:%\s*change|%\s*increase)\s+from\s+([-+]?[0-9][0-9.,]*)\s+to\s+([-+]?[0-9][0-9.,]*)$"#, in: lowered) {
            return makePercentageChange(from: match.0, to: match.1)
        }
        if let match = matchPattern(#"^%\s*decrease\s+from\s+([-+]?[0-9][0-9.,]*)\s+to\s+([-+]?[0-9][0-9.,]*)$"#, in: lowered) {
            return makePercentageChange(from: match.0, to: match.1)
        }
        if let match = matchPattern(#"^([-+]?[0-9][0-9.,]*)\s+is\s+what\s+%\s+of\s+([-+]?[0-9][0-9.,]*)$"#, in: lowered) {
            return makePercentageOfTotal(part: match.0, total: match.1)
        }
        if let match = matchPattern(#"^what\s+%\s+of\s+([-+]?[0-9][0-9.,]*)\s+is\s+([-+]?[0-9][0-9.,]*)$"#, in: lowered) {
            return makePercentageOfTotal(part: match.1, total: match.0)
        }
        return nil
    }

    private static func makePercentAdjustment(
        base: String,
        percent: String,
        operation: BinaryOperator
    ) -> (Expression, String?)? {
        guard let baseDecimal = parseSimpleDecimal(base), let percentDecimal = parseSimpleDecimal(percent) else { return nil }
        return (.percentAdjust(operation, .number(baseDecimal), .number(percentDecimal)), nil)
    }

    private static func makePercentageChange(from: String, to: String) -> (Expression, String?)? {
        guard let start = parseSimpleDecimal(from), let end = parseSimpleDecimal(to), start != 0 else { return nil }
        let expression = Expression.binary(
            .multiply,
            .binary(.divide, .binary(.subtract, .number(end), .number(start)), .number(start)),
            .number(100)
        )
        return (expression, nil)
    }

    private static func makePercentageOfTotal(part: String, total: String) -> (Expression, String?)? {
        guard let part = parseSimpleDecimal(part), let total = parseSimpleDecimal(total), total != 0 else { return nil }
        return (.binary(.multiply, .binary(.divide, .number(part), .number(total)), .number(100)), nil)
    }

    private static func makePercentOf(percent: String, base: String, tagged: String?) -> (Expression, String?)? {
        guard let percentDecimal = parseSimpleDecimal(percent),
              let baseDecimal = parseSimpleDecimal(base)
        else {
            return nil
        }
        return (.percentOf(.number(percentDecimal), .number(baseDecimal)), tagged)
    }

    private static func parseSimpleDecimal(_ text: String) -> Decimal? {
        let cleaned = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: "")
        return Decimal(string: cleaned, locale: Locale(identifier: "en_US_POSIX"))
    }

    private static func matchPattern(_ pattern: String, in text: String) -> (String, String)? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              match.numberOfRanges >= 3,
              let r1 = Range(match.range(at: 1), in: text),
              let r2 = Range(match.range(at: 2), in: text)
        else {
            return nil
        }
        return (String(text[r1]), String(text[r2]))
    }
}
