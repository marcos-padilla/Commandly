import Foundation

nonisolated struct UnicodeEmojiEntry: Codable, Equatable, Identifiable, Sendable {
    let symbol: String
    let name: String
    let category: String
    let subgroup: String
    let keywords: [String]
    let isComponent: Bool
    let family: String
    var id: String { symbol }
    var isVariant: Bool { symbol != family }
    var codePoints: String { symbol.unicodeScalars.map { String(format: "U+%04X", $0.value) }.joined(separator: " ") }
}

nonisolated struct UnicodeEmojiSearchRequest: Equatable, Sendable {
    var query = ""
    var category: String? = nil
    var includesVariants = false
}

nonisolated enum UnicodeEmojiError: Error, Equatable, LocalizedError {
    case unavailable, invalidCatalog, queryTooLong, invalidAIResponse, responseTooLarge
    var errorDescription: String? {
        switch self {
        case .unavailable: "The emoji catalog is unavailable. Reopen Emoji Search or reinstall Commandly."
        case .invalidCatalog: "The bundled emoji catalog could not be verified. Reinstall Commandly."
        case .queryTooLong: "Use a description of 1,024 UTF-8 bytes or fewer."
        case .invalidAIResponse: "The model did not return a valid list of catalog emoji. Try a different description or model."
        case .responseTooLarge: "The model returned too much text. Try a shorter description or another model."
        }
    }
}

/// Immutable, validated RGI sequences; no glyph artwork, platform scalar-name heuristic, or guessed variants.
nonisolated struct UnicodeEmojiCatalog: Sendable {
    let entries: [UnicodeEmojiEntry]
    let categories: [String]
    private let bySymbol: [String: UnicodeEmojiEntry]
    private let aliases: [String: String]
    private let searchable: [String]
    private let normalizedNames: [String]
    private let normalizedKeywords: [Set<String>]
    private let families: [String: [UnicodeEmojiEntry]]

    init(data: Data) throws {
        guard data.count <= 4 * 1_024 * 1_024 else { throw UnicodeEmojiError.invalidCatalog }
        let document: Document
        do { document = try JSONDecoder().decode(Document.self, from: data) }
        catch { throw UnicodeEmojiError.invalidCatalog }
        let entries = document.entries
        let symbols = Set(entries.map(\.symbol))
        guard document.schema == 1, document.unicodeVersion == "17.0", document.cldrVersion == "48",
              document.fullyQualifiedCount == 3_944, document.componentCount == 9,
              entries.count == 3_953, entries.filter(\.isComponent).count == 9,
              symbols.count == entries.count,
              entries.allSatisfy({ !$0.symbol.isEmpty && $0.symbol.utf8.count <= 128 && !$0.name.isEmpty
                  && symbols.contains($0.family) && !$0.category.isEmpty }),
              document.aliases.values.allSatisfy(symbols.contains) else { throw UnicodeEmojiError.invalidCatalog }
        self.entries = entries
        bySymbol = Dictionary(uniqueKeysWithValues: entries.map { ($0.symbol, $0) })
        aliases = document.aliases
        searchable = entries.map { Self.normalize(([$0.name, $0.category, $0.subgroup] + $0.keywords).joined(separator: " ")) }
        normalizedNames = entries.map { Self.normalize($0.name) }
        normalizedKeywords = entries.map { Set($0.keywords.map(Self.normalize)) }
        families = Dictionary(grouping: entries, by: \.family)
        var seen = Set<String>()
        categories = entries.compactMap { seen.insert($0.category).inserted ? $0.category : nil }
    }

    func entry(for symbol: String) -> UnicodeEmojiEntry? { bySymbol[symbol] ?? aliases[symbol].flatMap { bySymbol[$0] } }
    func variants(of entry: UnicodeEmojiEntry) -> [UnicodeEmojiEntry] { families[entry.family] ?? [entry] }

    func search(_ request: UnicodeEmojiSearchRequest) throws -> [UnicodeEmojiEntry] {
        try Task.checkCancellation()
        guard request.query.utf8.count <= 1_024 else { throw UnicodeEmojiError.queryTooLong }
        let query = request.query.trimmingCharacters(in: .whitespacesAndNewlines)
        if let exact = entry(for: query) { return request.category == nil || exact.category == request.category ? [exact] : [] }
        let normalized = Self.normalize(query)
        if !query.isEmpty && normalized.isEmpty { return [] }
        let words = normalized.split(separator: " ").map(String.init)
        let showVariants = request.includesVariants || !Set(["skin", "tone", "light", "medium", "dark"]).isDisjoint(with: words)
        var matches: [(Int, Int, UnicodeEmojiEntry)] = []
        for (index, entry) in entries.enumerated() {
            if index.isMultiple(of: 64) { try Task.checkCancellation() }
            guard request.category == nil || entry.category == request.category,
                  showVariants || !entry.isVariant,
                  words.allSatisfy(searchable[index].contains) else { continue }
            if query.isEmpty {
                matches.append((0, index, entry))
                continue
            }
            let name = normalizedNames[index]
            let rank = name == normalized ? 0 : (normalizedKeywords[index].contains(normalized) || (!normalized.isEmpty && (" " + name + " ").contains(" " + normalized + " "))) ? 1
                : name.hasPrefix(normalized) ? 2 : entry.isVariant ? 4 : 3
            matches.append((rank, index, entry))
        }
        return matches.sorted { $0.0 == $1.0 ? $0.1 < $1.1 : $0.0 < $1.0 }.map(\.2)
    }

    private static func normalize(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.joined(separator: " ")
    }

    private struct Document: Decodable {
        let schema: Int
        let unicodeVersion: String
        let cldrVersion: String
        let fullyQualifiedCount: Int
        let componentCount: Int
        let entries: [UnicodeEmojiEntry]
        let aliases: [String: String]
    }
}

nonisolated protocol UnicodeEmojiCatalogProviding: Sendable {
    func load() async throws -> UnicodeEmojiCatalog
    func search(_ request: UnicodeEmojiSearchRequest) async throws -> [UnicodeEmojiEntry]
}

/// The resource is read and indexed on this actor only when Emoji Search is opened.
actor BundledUnicodeEmojiCatalog: UnicodeEmojiCatalogProviding {
    private let resourceURL: URL?
    private var cached: UnicodeEmojiCatalog?
    init(resourceURL: URL?) { self.resourceURL = resourceURL }
    func load() throws -> UnicodeEmojiCatalog {
        try Task.checkCancellation()
        if let cached { return cached }
        guard let resourceURL else { throw UnicodeEmojiError.unavailable }
        let data: Data
        do { data = try Data(contentsOf: resourceURL, options: [.mappedIfSafe]) }
        catch { throw UnicodeEmojiError.unavailable }
        try Task.checkCancellation()
        let catalog = try UnicodeEmojiCatalog(data: data)
        cached = catalog
        return catalog
    }
    func search(_ request: UnicodeEmojiSearchRequest) throws -> [UnicodeEmojiEntry] { try load().search(request) }
}
