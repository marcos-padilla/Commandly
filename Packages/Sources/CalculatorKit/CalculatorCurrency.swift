import Foundation

/// ISO 4217 currency code.
public struct CurrencyCode: Hashable, Sendable, Codable, RawRepresentable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue.uppercased()
    }

    public init(_ rawValue: String) {
        self.init(rawValue: rawValue)
    }
}

/// A quoted exchange rate between two currencies.
public struct ExchangeRate: Sendable, Equatable {
    public let base: CurrencyCode
    public let quote: CurrencyCode
    public let rate: Decimal
    public let timestamp: Date
    public let isStale: Bool

    public init(
        base: CurrencyCode,
        quote: CurrencyCode,
        rate: Decimal,
        timestamp: Date,
        isStale: Bool = false
    ) {
        self.base = base
        self.quote = quote
        self.rate = rate
        self.timestamp = timestamp
        self.isStale = isStale
    }
}

/// Fetches exchange rates. Implementations must never fabricate rates.
public protocol ExchangeRateProviding: Sendable {
    /// Returns a rate to convert `amount` from `from` into `to`.
    func rate(from: CurrencyCode, to: CurrencyCode) async throws -> ExchangeRate
}

/// Optional cache for exchange rates.
public protocol ExchangeRateCaching: Sendable {
    func cachedRate(from: CurrencyCode, to: CurrencyCode) async -> ExchangeRate?
    func store(_ rate: ExchangeRate) async
}

/// In-memory cache suitable for tests and process lifetime.
public actor InMemoryExchangeRateCache: ExchangeRateCaching {
    private var storage: [String: ExchangeRate] = [:]

    public init() {}

    public func cachedRate(from: CurrencyCode, to: CurrencyCode) async -> ExchangeRate? {
        storage[key(from, to)]
    }

    public func store(_ rate: ExchangeRate) async {
        storage[key(rate.base, rate.quote)] = rate
    }

    private func key(_ from: CurrencyCode, _ to: CurrencyCode) -> String {
        "\(from.rawValue)->\(to.rawValue)"
    }
}

/// Deterministic provider for unit tests — never hits the network.
public struct InMemoryExchangeRateProvider: ExchangeRateProviding {
    private let rates: [String: Decimal]
    private let timestamp: Date
    private let isStale: Bool

    public init(rates: [String: Decimal], timestamp: Date = Date(timeIntervalSince1970: 1_700_000_000), isStale: Bool = false) {
        self.rates = rates
        self.timestamp = timestamp
        self.isStale = isStale
    }

    public func rate(from: CurrencyCode, to: CurrencyCode) async throws -> ExchangeRate {
        try Task.checkCancellation()
        if from == to {
            return ExchangeRate(base: from, quote: to, rate: 1, timestamp: timestamp, isStale: isStale)
        }
        let direct = "\(from.rawValue)->\(to.rawValue)"
        if let rate = rates[direct] {
            return ExchangeRate(base: from, quote: to, rate: rate, timestamp: timestamp, isStale: isStale)
        }
        let inverse = "\(to.rawValue)->\(from.rawValue)"
        if let rate = rates[inverse], rate != 0 {
            return ExchangeRate(base: from, quote: to, rate: 1 / rate, timestamp: timestamp, isStale: isStale)
        }
        throw CalculatorError.exchangeRateUnavailable
    }
}

/// Currency conversion evaluation (`100 USD in EUR`).
enum CalculatorCurrency {
    struct ConversionResult: Sendable, Equatable {
        let value: CalculatorCurrencyValue
        let metadata: CalculatorResultMetadata
        let displayExpression: String
    }

    static func evaluate(
        _ text: String,
        provider: any ExchangeRateProviding,
        locale: Locale
    ) async throws -> ConversionResult {
        try Task.checkCancellation()
        let canonical = text.lowercased()
        if let divided = try await evaluateRateDivision(canonical, provider: provider, locale: locale) {
            return divided
        }
        if let arithmetic = try await evaluateArithmetic(canonical, provider: provider, locale: locale) {
            return arithmetic
        }
        guard let parsed = try parse(canonical, locale: locale) else {
            throw CalculatorError.unsupportedOperation
        }

        let exchange = try await provider.rate(from: parsed.from, to: parsed.to)
        try Task.checkCancellation()

        let converted = parsed.amount * exchange.rate
        var metadata = CalculatorResultMetadata(
            exchangeRate: exchange.rate,
            rateTimestamp: exchange.timestamp,
            rateIsStale: exchange.isStale,
            fromCurrency: parsed.from.rawValue,
            toCurrency: parsed.to.rawValue
        )
        metadata.baseAmount = parsed.amount
        metadata.total = converted

        var hintsNote = "Rate \(exchange.rate)"
        if exchange.isStale {
            hintsNote += " (stale)"
        }
        metadata.notes.append(hintsNote)

        return ConversionResult(
            value: CalculatorCurrencyValue(amount: converted, code: parsed.to),
            metadata: metadata,
            displayExpression: "\(parsed.amount) \(parsed.from.rawValue) → \(parsed.to.rawValue)"
        )
    }

    private struct Parsed {
        let amount: Decimal
        let from: CurrencyCode
        let to: CurrencyCode
    }

    private static func parse(_ text: String, locale: Locale) throws -> Parsed? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        if let symbolParsed = try parseSymbolForm(trimmed, locale: locale) {
            return symbolParsed
        }
        if let short = try parseShortForm(trimmed, locale: locale) {
            return short
        }

        let pattern = #"^([-+]?\d+(?:[.,]\d+)?)\s*(.+?)\s+(?:in|to|into|as)\s+(.+)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return nil
        }
        let range = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
        guard let match = regex.firstMatch(in: trimmed, options: [], range: range),
              match.numberOfRanges == 4,
              let amountRange = Range(match.range(at: 1), in: trimmed),
              let fromRange = Range(match.range(at: 2), in: trimmed),
              let toRange = Range(match.range(at: 3), in: trimmed)
        else {
            return nil
        }
        let amountText = String(trimmed[amountRange]).replacingOccurrences(of: ",", with: "")
        guard let amount = Decimal(string: amountText, locale: Locale(identifier: "en_US_POSIX")) else {
            return nil
        }
        let source = try currencyCode(for: String(trimmed[fromRange]), locale: locale)
        let target = try currencyCode(for: String(trimmed[toRange]), locale: locale)
        return Parsed(amount: amount, from: source, to: target)
    }

    private static func parseShortForm(_ text: String, locale: Locale) throws -> Parsed? {
        let pattern = #"^([-+]?\d+(?:[.,]\d+)?)\s*([A-Za-z]{3})\s+([A-Za-z]{3})$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text)),
              let amountRange = Range(match.range(at: 1), in: text),
              let sourceRange = Range(match.range(at: 2), in: text),
              let targetRange = Range(match.range(at: 3), in: text),
              let amount = Decimal(string: String(text[amountRange]).replacingOccurrences(of: ",", with: ""))
        else { return nil }
        return Parsed(
            amount: amount,
            from: try currencyCode(for: String(text[sourceRange]), locale: locale),
            to: try currencyCode(for: String(text[targetRange]), locale: locale)
        )
    }

    private static func parseSymbolForm(_ text: String, locale: Locale) throws -> Parsed? {
        let patterns = [
            #"^([$€£¥])\s*([-+]?\d+(?:[.,]\d+)?)\s+(?:in|to|into|as)\s+(.+)$"#,
            #"^([-+]?\d+(?:[.,]\d+)?)\s*([$€£¥])\s+(?:in|to|into|as)\s+(.+)$"#,
        ]
        for (index, pattern) in patterns.enumerated() {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text)),
                  let firstRange = Range(match.range(at: 1), in: text),
                  let secondRange = Range(match.range(at: 2), in: text),
                  let targetRange = Range(match.range(at: 3), in: text)
            else { continue }
            let symbol = index == 0 ? String(text[firstRange]) : String(text[secondRange])
            let amountText = index == 0 ? String(text[secondRange]) : String(text[firstRange])
            guard let amount = Decimal(string: amountText.replacingOccurrences(of: ",", with: ""), locale: Locale(identifier: "en_US_POSIX")) else {
                return nil
            }
            return Parsed(
                amount: amount,
                from: try currencyCode(for: symbol, locale: locale),
                to: try currencyCode(for: String(text[targetRange]), locale: locale)
            )
        }
        return nil
    }

    private static func evaluateArithmetic(
        _ text: String,
        provider: any ExchangeRateProviding,
        locale: Locale
    ) async throws -> ConversionResult? {
        let pattern = #"^([-+]?\d+(?:[.,]\d+)?)\s*(.+?)\s*\+\s*([-+]?\d+(?:[.,]\d+)?)\s*(.+?)\s+in\s+(.+)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text)),
              match.numberOfRanges == 6,
              let firstAmountRange = Range(match.range(at: 1), in: text),
              let firstCodeRange = Range(match.range(at: 2), in: text),
              let secondAmountRange = Range(match.range(at: 3), in: text),
              let secondCodeRange = Range(match.range(at: 4), in: text),
              let targetRange = Range(match.range(at: 5), in: text),
              let firstAmount = Decimal(string: String(text[firstAmountRange]).replacingOccurrences(of: ",", with: "")),
              let secondAmount = Decimal(string: String(text[secondAmountRange]).replacingOccurrences(of: ",", with: ""))
        else { return nil }

        let firstCode = try currencyCode(for: String(text[firstCodeRange]), locale: locale)
        let secondCode = try currencyCode(for: String(text[secondCodeRange]), locale: locale)
        let target = try currencyCode(for: String(text[targetRange]), locale: locale)
        async let firstRate = provider.rate(from: firstCode, to: target)
        async let secondRate = provider.rate(from: secondCode, to: target)
        let (firstExchange, secondExchange) = try await (firstRate, secondRate)
        try Task.checkCancellation()
        let total = firstAmount * firstExchange.rate + secondAmount * secondExchange.rate
        var metadata = CalculatorResultMetadata(
            rateTimestamp: max(firstExchange.timestamp, secondExchange.timestamp),
            rateIsStale: firstExchange.isStale || secondExchange.isStale,
            fromCurrency: "\(firstCode.rawValue)+\(secondCode.rawValue)",
            toCurrency: target.rawValue
        )
        metadata.total = total
        metadata.notes.append("Rates: \(firstCode.rawValue)/\(target.rawValue) \(firstExchange.rate), \(secondCode.rawValue)/\(target.rawValue) \(secondExchange.rate)")
        return ConversionResult(
            value: CalculatorCurrencyValue(amount: total, code: target),
            metadata: metadata,
            displayExpression: "\(firstAmount) \(firstCode.rawValue) + \(secondAmount) \(secondCode.rawValue) → \(target.rawValue)"
        )
    }

    private static func evaluateRateDivision(
        _ text: String,
        provider: any ExchangeRateProviding,
        locale: Locale
    ) async throws -> ConversionResult? {
        let pattern = #"^([-+]?\d+(?:[.,]\d+)?)\s*(.+?)\s*/\s*(?:the\s+)?(.+?)\s+exchange rate$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text)),
              let amountRange = Range(match.range(at: 1), in: text),
              let sourceRange = Range(match.range(at: 2), in: text),
              let targetRange = Range(match.range(at: 3), in: text),
              let amount = Decimal(string: String(text[amountRange]).replacingOccurrences(of: ",", with: ""))
        else { return nil }
        let source = try currencyCode(for: String(text[sourceRange]), locale: locale)
        let target = try currencyCode(for: String(text[targetRange]), locale: locale)
        let exchange = try await provider.rate(from: target, to: source)
        guard exchange.rate != 0 else { throw CalculatorError.divisionByZero }
        let converted = amount / exchange.rate
        var metadata = CalculatorResultMetadata(
            exchangeRate: exchange.rate,
            rateTimestamp: exchange.timestamp,
            rateIsStale: exchange.isStale,
            fromCurrency: source.rawValue,
            toCurrency: target.rawValue
        )
        metadata.baseAmount = amount
        metadata.total = converted
        metadata.notes.append("Divided by quoted \(target.rawValue)/\(source.rawValue) rate \(exchange.rate)")
        return ConversionResult(
            value: CalculatorCurrencyValue(amount: converted, code: target),
            metadata: metadata,
            displayExpression: "\(amount) \(source.rawValue) ÷ \(target.rawValue)/\(source.rawValue) rate → \(target.rawValue)"
        )
    }

    private static func currencyCode(for raw: String, locale: Locale) throws -> CurrencyCode {
        let token = raw.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let aliases: [String: String] = [
            "usd": "USD", "us dollar": "USD", "us dollars": "USD", "american dollar": "USD", "american dollars": "USD",
            "eur": "EUR", "euro": "EUR", "euros": "EUR", "€": "EUR",
            "gbp": "GBP", "british pound": "GBP", "british pounds": "GBP", "pound sterling": "GBP", "£": "GBP",
            "jpy": "JPY", "yen": "JPY", "japanese yen": "JPY",
            "cad": "CAD", "canadian dollar": "CAD", "canadian dollars": "CAD",
            "aud": "AUD", "australian dollar": "AUD", "australian dollars": "AUD",
            "nzd": "NZD", "new zealand dollar": "NZD", "new zealand dollars": "NZD",
            "cny": "CNY", "chinese yuan": "CNY", "yuan": "CNY",
            "mxn": "MXN", "mexican peso": "MXN", "mexican pesos": "MXN",
        ]
        if let code = aliases[token] { return CurrencyCode(code) }
        if token.count == 3, token.allSatisfy(\.isLetter) { return CurrencyCode(token) }

        let region = locale.region?.identifier.uppercased()
        if token == "$" || token == "dollar" || token == "dollars" {
            switch region {
            case "US": return CurrencyCode("USD")
            case "CA": return CurrencyCode("CAD")
            case "AU": return CurrencyCode("AUD")
            case "NZ": return CurrencyCode("NZD")
            default: throw CalculatorError.ambiguousCurrencySymbol(raw)
            }
        }
        if token == "¥" {
            switch region {
            case "JP": return CurrencyCode("JPY")
            case "CN": return CurrencyCode("CNY")
            default: throw CalculatorError.ambiguousCurrencySymbol(raw)
            }
        }
        if ["peso", "pesos", "kr"].contains(token) {
            throw CalculatorError.ambiguousCurrencySymbol(raw)
        }
        throw CalculatorError.unknownCurrency(raw)
    }

    static func ambiguousSymbolError(for symbol: String) -> CalculatorError {
        .ambiguousCurrencySymbol(symbol)
    }
}
