import Foundation

/// Live Frankfurter exchange-rate provider (`https://api.frankfurter.app`).
///
/// No API key is required. Requests are cancelable via structured concurrency.
/// Rates are never fabricated on failure.
public struct FrankfurterExchangeRateProvider: ExchangeRateProviding {
    private let session: URLSession
    private let cache: (any ExchangeRateCaching)?
    private let staleInterval: TimeInterval
    private let baseURL: URL

    /// Creates a Frankfurter-backed provider.
    ///
    /// - Parameters:
    ///   - session: URL session used for fetches (injectable for tests of the live adapter).
    ///   - cache: Optional rate cache.
    ///   - staleInterval: Age after which a cached rate is marked stale.
    ///   - baseURL: API root; defaults to the public Frankfurter endpoint.
    public init(
        session: URLSession = .shared,
        cache: (any ExchangeRateCaching)? = nil,
        staleInterval: TimeInterval = 60 * 60,
        baseURL: URL = URL(string: "https://api.frankfurter.app") ?? URL(fileURLWithPath: "/")
    ) {
        self.session = session
        self.cache = cache
        self.staleInterval = staleInterval
        self.baseURL = baseURL
    }

    public func rate(from: CurrencyCode, to: CurrencyCode) async throws -> ExchangeRate {
        try Task.checkCancellation()

        if from == to {
            return ExchangeRate(base: from, quote: to, rate: 1, timestamp: Date(), isStale: false)
        }

        if let cache,
           let cached = await cache.cachedRate(from: from, to: to) {
            let age = Date().timeIntervalSince(cached.timestamp)
            if age <= staleInterval {
                return cached
            }
            // Return stale cached value marked stale; caller may refresh.
            return ExchangeRate(
                base: cached.base,
                quote: cached.quote,
                rate: cached.rate,
                timestamp: cached.timestamp,
                isStale: true
            )
        }

        try Task.checkCancellation()

        var components = URLComponents(url: baseURL.appendingPathComponent("latest"), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "from", value: from.rawValue),
            URLQueryItem(name: "to", value: to.rawValue),
        ]
        guard let url = components?.url else {
            throw CalculatorError.exchangeRateUnavailable
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(from: url)
        } catch is CancellationError {
            throw CalculatorError.cancelled
        } catch {
            throw CalculatorError.exchangeRateUnavailable
        }

        try Task.checkCancellation()

        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw CalculatorError.exchangeRateUnavailable
        }

        let decoded: FrankfurterResponse
        do {
            decoded = try JSONDecoder().decode(FrankfurterResponse.self, from: data)
        } catch {
            throw CalculatorError.exchangeRateUnavailable
        }

        guard let rateDouble = decoded.rates[to.rawValue],
              let rate = DecimalMath.fromDouble(rateDouble)
        else {
            throw CalculatorError.exchangeRateUnavailable
        }

        let timestamp = ISO8601DateFormatter().date(from: decoded.date + "T00:00:00Z") ?? Date()
        let exchange = ExchangeRate(
            base: from,
            quote: to,
            rate: rate,
            timestamp: timestamp,
            isStale: false
        )
        if let cache {
            await cache.store(exchange)
        }
        return exchange
    }
}

private struct FrankfurterResponse: Decodable, Sendable {
    let amount: Double
    let base: String
    let date: String
    let rates: [String: Double]
}
