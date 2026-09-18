import Foundation

nonisolated protocol SVGLServicing: Sendable {
    func catalog(forceRefresh: Bool) async throws -> [LogoAsset]
    func svgData(from url: URL) async throws -> Data
}

actor LiveSVGLService: SVGLServicing {
    private struct CatalogCache {
        let loadedAt: Date
        let assets: [LogoAsset]
    }

    private static let catalogURL = URL(string: "https://api.svgl.app")
    private static let catalogCacheLifetime: TimeInterval = 10 * 60
    private static let maximumCatalogBytes = 5 * 1_024 * 1_024
    private static let maximumSVGBytes = 2 * 1_024 * 1_024
    private static let maximumCachedSVGs = 80

    private let session: URLSession
    private let now: @Sendable () -> Date
    private var catalogCache: CatalogCache?
    private var svgCache: [URL: Data] = [:]
    private var svgCacheOrder: [URL] = []

    init(
        session: URLSession? = nil,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.httpCookieStorage = nil
            configuration.urlCache = nil
            configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
            self.session = URLSession(configuration: configuration)
        }
        self.now = now
    }

    func catalog(forceRefresh: Bool) async throws -> [LogoAsset] {
        if forceRefresh == false,
           let catalogCache,
           now().timeIntervalSince(catalogCache.loadedAt) < Self.catalogCacheLifetime {
            return catalogCache.assets
        }
        guard let url = Self.catalogURL else { throw SVGLServiceError.invalidResponse }

        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 20
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            let (data, response) = try await session.data(for: request)
            try Task.checkCancellation()
            try Self.validate(
                response: response,
                maximumBytes: Self.maximumCatalogBytes,
                data: data
            )
            let assets = try SVGLCatalogDecoder.decode(data)
            catalogCache = CatalogCache(loadedAt: now(), assets: assets)
            return assets
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as SVGLServiceError {
            throw error
        } catch {
            throw SVGLServiceError.catalogUnavailable
        }
    }

    func svgData(from url: URL) async throws -> Data {
        guard LogoAsset.validAssetURL(url.absoluteString) != nil else {
            throw SVGLServiceError.invalidAssetURL
        }
        if let cached = svgCache[url] { return cached }

        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 20
            request.setValue("image/svg+xml", forHTTPHeaderField: "Accept")
            let (data, response) = try await session.data(for: request)
            try Task.checkCancellation()
            try Self.validate(
                response: response,
                maximumBytes: Self.maximumSVGBytes,
                data: data
            )
            guard let source = String(data: data, encoding: .utf8),
                  source.range(of: "<svg", options: [.caseInsensitive]) != nil else {
                throw SVGLServiceError.invalidSVG
            }
            cacheSVG(data, for: url)
            return data
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as SVGLServiceError {
            throw error
        } catch {
            throw SVGLServiceError.assetUnavailable
        }
    }

    private static func validate(
        response: URLResponse,
        maximumBytes: Int,
        data: Data
    ) throws {
        guard let response = response as? HTTPURLResponse,
              (200 ..< 300).contains(response.statusCode),
              data.isEmpty == false,
              data.count <= maximumBytes else {
            throw SVGLServiceError.invalidResponse
        }
    }

    private func cacheSVG(_ data: Data, for url: URL) {
        svgCache[url] = data
        svgCacheOrder.removeAll { $0 == url }
        svgCacheOrder.append(url)
        while svgCacheOrder.count > Self.maximumCachedSVGs {
            let removedURL = svgCacheOrder.removeFirst()
            svgCache.removeValue(forKey: removedURL)
        }
    }
}

actor InMemorySVGLService: SVGLServicing {
    var assets: [LogoAsset]
    var svgByURL: [URL: Data]
    var catalogError: SVGLServiceError?

    init(
        assets: [LogoAsset] = [],
        svgByURL: [URL: Data] = [:],
        catalogError: SVGLServiceError? = nil
    ) {
        self.assets = assets
        self.svgByURL = svgByURL
        self.catalogError = catalogError
    }

    func catalog(forceRefresh: Bool) throws -> [LogoAsset] {
        _ = forceRefresh
        if let catalogError { throw catalogError }
        return assets
    }

    func svgData(from url: URL) throws -> Data {
        guard let data = svgByURL[url] else { throw SVGLServiceError.assetUnavailable }
        return data
    }
}
