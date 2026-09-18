import Foundation

nonisolated enum LogoVariant: String, CaseIterable, Identifiable, Sendable {
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }
}

nonisolated struct LogoRoutes: Equatable, Hashable, Sendable {
    let standard: URL?
    let light: URL?
    let dark: URL?

    var hasAppearanceVariants: Bool { light != nil && dark != nil }

    func url(for variant: LogoVariant) -> URL? {
        if let standard { return standard }
        switch variant {
        case .light: return light ?? dark
        case .dark: return dark ?? light
        }
    }
}

nonisolated struct LogoAsset: Identifiable, Equatable, Hashable, Sendable {
    let id: Int
    let title: String
    let categories: [String]
    let routes: LogoRoutes
    let websiteURL: URL?
    let brandURL: URL?
}

nonisolated enum SVGLServiceError: LocalizedError, Equatable, Sendable {
    case invalidResponse
    case catalogUnavailable
    case invalidCatalog
    case invalidAssetURL
    case assetUnavailable
    case invalidSVG

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "SVGL returned an unexpected response."
        case .catalogUnavailable: return "The logo catalog is temporarily unavailable."
        case .invalidCatalog: return "The logo catalog could not be read."
        case .invalidAssetURL: return "This logo does not have a valid download URL."
        case .assetUnavailable: return "The selected logo could not be downloaded."
        case .invalidSVG: return "The downloaded asset is not a valid SVG."
        }
    }
}

nonisolated enum SVGLCatalogDecoder {
    static func decode(_ data: Data) throws -> [LogoAsset] {
        let records: [SVGLRecord]
        do {
            records = try JSONDecoder().decode([SVGLRecord].self, from: data)
        } catch {
            throw SVGLServiceError.invalidCatalog
        }

        let assets = records.compactMap(LogoAsset.init(record:))
        guard assets.isEmpty == false else { throw SVGLServiceError.invalidCatalog }
        return assets.sorted {
            let titleOrder = $0.title.localizedStandardCompare($1.title)
            if titleOrder != .orderedSame { return titleOrder == .orderedAscending }
            return $0.id < $1.id
        }
    }
}

nonisolated private struct SVGLRecord: Decodable {
    let id: Int
    let title: String
    let category: FlexibleStringList
    let route: FlexibleRoute
    let url: String?
    let brandUrl: String?
}

nonisolated private enum FlexibleStringList: Decodable {
    case one(String)
    case many([String])

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(String.self) {
            self = .one(value)
        } else {
            self = .many(try container.decode([String].self))
        }
    }

    var values: [String] {
        switch self {
        case .one(let value): return [value]
        case .many(let values): return values
        }
    }
}

nonisolated private enum FlexibleRoute: Decodable {
    case standard(String)
    case variants(light: String, dark: String)

    private enum CodingKeys: String, CodingKey {
        case light
        case dark
    }

    init(from decoder: any Decoder) throws {
        let single = try decoder.singleValueContainer()
        if let value = try? single.decode(String.self) {
            self = .standard(value)
            return
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self = try .variants(
            light: container.decode(String.self, forKey: .light),
            dark: container.decode(String.self, forKey: .dark)
        )
    }
}

nonisolated extension LogoAsset {
    fileprivate init?(record: SVGLRecord) {
        let title = record.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let categories = record.category.values
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false }
        guard title.isEmpty == false, categories.isEmpty == false else { return nil }

        let routes: LogoRoutes
        switch record.route {
        case .standard(let rawURL):
            guard let url = Self.validAssetURL(rawURL) else { return nil }
            routes = LogoRoutes(standard: url, light: nil, dark: nil)
        case .variants(let rawLightURL, let rawDarkURL):
            guard let lightURL = Self.validAssetURL(rawLightURL),
                  let darkURL = Self.validAssetURL(rawDarkURL) else { return nil }
            routes = LogoRoutes(standard: nil, light: lightURL, dark: darkURL)
        }

        self.init(
            id: record.id,
            title: title,
            categories: categories,
            routes: routes,
            websiteURL: Self.validExternalURL(record.url),
            brandURL: Self.validExternalURL(record.brandUrl)
        )
    }

    static func validAssetURL(_ value: String?) -> URL? {
        guard let value,
              let url = URL(string: value),
              url.scheme?.lowercased() == "https",
              url.host?.lowercased() == "svgl.app",
              url.pathExtension.lowercased() == "svg" else {
            return nil
        }
        return url
    }

    private static func validExternalURL(_ value: String?) -> URL? {
        guard let value,
              let url = URL(string: value),
              let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http" else {
            return nil
        }
        return url
    }
}
