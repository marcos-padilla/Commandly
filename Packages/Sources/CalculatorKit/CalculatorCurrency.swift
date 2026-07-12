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
        provider: any ExchangeRateProviding
    ) async throws -> ConversionResult {
        try Task.checkCancellation()
        guard let parsed = parse(text) else {
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

    private static func parse(_ text: String) -> Parsed? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Symbol forms: $100 in EUR, 100$ in EUR
        if let symbolParsed = parseSymbolForm(trimmed) {
            return symbolParsed
        }

        let pattern = #"^([-+]?\d+(?:[.,]\d+)?)\s*([A-Za-z]{3})\s+(?:in|to|into|as)\s+([A-Za-z]{3})$"#
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
        return Parsed(
            amount: amount,
            from: CurrencyCode(String(trimmed[fromRange])),
            to: CurrencyCode(String(trimmed[toRange]))
        )
    }

    private static func parseSymbolForm(_ text: String) -> Parsed? {
        // Ambiguous symbols map to failure via known set.
        let ambiguous: Set<Character> = ["$"] // could be USD/CAD/AUD — require ISO when ambiguous without context
        // Allow $ only as USD for unambiguous US-centric default? Spec says prefer clarification.
        // Treat bare $ as ambiguous.
        if text.contains("$") {
            // If explicitly "USD" not present and only $, fail ambiguous.
            let pattern = #"^\$?\s*([-+]?\d+(?:[.,]\d+)?)\s*\$?\s+(?:in|to|into|as)\s+([A-Za-z]{3})$"#
            if text.contains("$"),
               let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: text, options: [], range: NSRange(text.startIndex..<text.endIndex, in: text)),
               match.numberOfRanges == 3 {
                // Ambiguous $
                _ = ambiguous
                return nil
            }
        }
        return nil
    }

    static func ambiguousSymbolError(for symbol: String) -> CalculatorError {
        .ambiguousCurrencySymbol(symbol)
    }
}
