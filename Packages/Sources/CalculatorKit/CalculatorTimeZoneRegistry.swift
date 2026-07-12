import AppCore
import Foundation

/// Registry-backed time-zone resolution covering every Foundation IANA zone,
/// unique city components, explicit regional aliases, and safe fuzzy matches.
///
/// Safety: all lookup tables are fully constructed during initialization and
/// stored in immutable properties. Concurrent callers perform read-only lookup;
/// the registry exposes no mutation or reference to its internal collections.
final class CalculatorTimeZoneRegistry: @unchecked Sendable {
    static let shared = CalculatorTimeZoneRegistry()

    private let identifiersByLowercase: [String: String]
    private let identifiersByAlias: [String: [String]]
    private let displayByAlias: [String: String]
    private let ambiguousAbbreviations: Set<String> = [
        "cst", "ist", "bst", "pst", "est", "mst", "ast", "cdt", "edt", "mdt", "pdt",
    ]

    private init() {
        let identifiers = TimeZone.knownTimeZoneIdentifiers
        identifiersByLowercase = Dictionary(uniqueKeysWithValues: identifiers.map { ($0.lowercased(), $0) })

        var aliases: [String: Set<String>] = [:]
        var displays: [String: String] = [:]
        func register(_ alias: String, identifier: String, display: String? = nil) {
            let key = alias.lowercased()
            aliases[key, default: []].insert(identifier)
            displays[key] = display ?? alias.split(separator: " ").map(\.capitalized).joined(separator: " ")
        }

        for identifier in identifiers {
            register(identifier, identifier: identifier, display: identifier)
            guard let component = identifier.split(separator: "/").last else { continue }
            let city = component.replacingOccurrences(of: "_", with: " ")
            register(city, identifier: identifier, display: city)
        }

        let explicit: [String: String] = [
            "new york": "America/New_York", "nyc": "America/New_York",
            "miami": "America/New_York", "arizona": "America/Phoenix",
            "phoenix": "America/Phoenix", "los angeles": "America/Los_Angeles",
            "la": "America/Los_Angeles", "san francisco": "America/Los_Angeles",
            "hawaii": "Pacific/Honolulu", "alaska": "America/Anchorage",
            "washington dc": "America/New_York", "dc": "America/New_York",
            "utc": "UTC", "gmt": "GMT",
        ]
        for (alias, identifier) in explicit { register(alias, identifier: identifier) }

        identifiersByAlias = aliases.mapValues { Array($0).sorted() }
        displayByAlias = displays
    }

    func resolve(_ raw: String) throws -> TimeZone {
        let rawLowercase = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let identifier = identifiersByLowercase[rawLowercase], let zone = TimeZone(identifier: identifier) { return zone }
        let value = normalized(raw)
        if ambiguousAbbreviations.contains(value) { throw CalculatorError.ambiguousTimeZone(raw) }
        if let identifier = identifiersByLowercase[value], let zone = TimeZone(identifier: identifier) { return zone }
        if let candidates = identifiersByAlias[value] {
            guard candidates.count == 1, let identifier = candidates.first, let zone = TimeZone(identifier: identifier) else {
                throw CalculatorError.ambiguousTimeZone(raw)
            }
            return zone
        }
        guard value.count >= 4,
              let alias = StringDistance.uniqueBestMatch(
                for: value,
                in: identifiersByAlias.keys,
                minimumSimilarity: value.count <= 5 ? 0.8 : 0.74
              ),
              let candidates = identifiersByAlias[alias], candidates.count == 1,
              let identifier = candidates.first, let zone = TimeZone(identifier: identifier) else {
            throw CalculatorError.ambiguousTimeZone(raw)
        }
        return zone
    }

    func completion(for partial: String) -> String? {
        let value = normalized(partial)
        guard value.count >= 2 else { return nil }
        let prefixMatches = identifiersByAlias.keys
            .filter { $0.hasPrefix(value) && identifiersByAlias[$0]?.count == 1 }
            .sorted { lhs, rhs in lhs.count == rhs.count ? lhs < rhs : lhs.count < rhs.count }
        if let match = prefixMatches.first { return displayByAlias[match] ?? match }
        guard let match = StringDistance.uniqueBestMatch(for: value, in: identifiersByAlias.keys, minimumSimilarity: 0.78),
              identifiersByAlias[match]?.count == 1 else { return nil }
        return displayByAlias[match] ?? match
    }

    func containsKnownZone(in input: String) -> Bool {
        let words = normalized(input).split(separator: " ").map(String.init)
        for start in words.indices {
            for length in 1...min(3, words.count - start) {
                let phrase = words[start..<(start + length)].joined(separator: " ")
                if identifiersByAlias[phrase]?.count == 1 { return true }
            }
        }
        return input.contains("/") && identifiersByLowercase.keys.contains(normalized(input))
    }

    private func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "_", with: " ")
            .lowercased()
    }
}
