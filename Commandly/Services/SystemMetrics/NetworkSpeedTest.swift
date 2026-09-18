import Foundation

/// What one finished speed test measured.
nonisolated struct NetworkSpeedTestResult: Equatable, Sendable {
    let downloadMegabitsPerSecond: Double
    let uploadMegabitsPerSecond: Double
    let latencyMilliseconds: Double
    let finishedAt: Date
}

nonisolated enum NetworkSpeedTestError: Error, Equatable, Sendable {
    case transferFailed
    case tooShortToMeasure
}

/// Measures the connection against Cloudflare's public speed endpoints.
///
/// This is the one place in the panel that sends data to a third party, so it runs only when
/// the user asks for it. The upload body is generated zeroes, never anything from this Mac.
nonisolated struct NetworkSpeedTest: Sendable {
    /// Cloudflare's speed backend, the one behind speed.cloudflare.com.
    private static let host = "https://speed.cloudflare.com"
    /// Payload sizes chosen to be long enough to measure without being a large transfer.
    private static let downloadBytes = 25_000_000
    private static let uploadBytes = 10_000_000
    /// How many round trips the latency figure averages.
    private static let latencySamples = 4
    /// A measurement shorter than this is dominated by setup rather than throughput.
    private static let minimumMeasurableDuration: TimeInterval = 0.05

    private let session: URLSession

    init(session: URLSession? = nil) {
        if let session {
            self.session = session
            return
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60
        self.session = URLSession(configuration: configuration)
    }

    func run() async throws -> NetworkSpeedTestResult {
        let latency = try await measureLatency()
        try Task.checkCancellation()
        let download = try await measureDownload()
        try Task.checkCancellation()
        let upload = try await measureUpload()

        return NetworkSpeedTestResult(
            downloadMegabitsPerSecond: download,
            uploadMegabitsPerSecond: upload,
            latencyMilliseconds: latency,
            finishedAt: Date()
        )
    }

    /// Round-trip time to a zero-byte response, averaged so one slow trip does not stand in for
    /// the connection.
    private func measureLatency() async throws -> Double {
        guard let url = URL(string: "\(Self.host)/__down?bytes=0") else {
            throw NetworkSpeedTestError.transferFailed
        }
        var samples: [Double] = []
        for _ in 0..<Self.latencySamples {
            try Task.checkCancellation()
            let start = Date()
            guard (try? await session.data(from: url)) != nil else {
                throw NetworkSpeedTestError.transferFailed
            }
            samples.append(Date().timeIntervalSince(start) * 1_000)
        }
        guard samples.isEmpty == false else { throw NetworkSpeedTestError.transferFailed }
        return samples.reduce(0, +) / Double(samples.count)
    }

    private func measureDownload() async throws -> Double {
        guard let url = URL(string: "\(Self.host)/__down?bytes=\(Self.downloadBytes)") else {
            throw NetworkSpeedTestError.transferFailed
        }
        let start = Date()
        let (data, _) = try await session.data(from: url)
        return try megabitsPerSecond(bytes: data.count, seconds: Date().timeIntervalSince(start))
    }

    private func measureUpload() async throws -> Double {
        guard let url = URL(string: "\(Self.host)/__up") else {
            throw NetworkSpeedTestError.transferFailed
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")

        let payload = Data(count: Self.uploadBytes)
        let start = Date()
        _ = try await session.upload(for: request, from: payload)
        return try megabitsPerSecond(bytes: payload.count, seconds: Date().timeIntervalSince(start))
    }

    private func megabitsPerSecond(bytes: Int, seconds: TimeInterval) throws -> Double {
        guard bytes > 0 else { throw NetworkSpeedTestError.transferFailed }
        guard seconds >= Self.minimumMeasurableDuration else {
            throw NetworkSpeedTestError.tooShortToMeasure
        }
        return Double(bytes) * 8 / seconds / 1_000_000
    }
}
