import Foundation
import SearchKit

/// Normalizes user-authored installed-app nicknames without changing bundle identity or execution.
nonisolated enum ApplicationAlias {
    static let maximumLength = 64

    enum ValidationError: Error, Equatable {
        case tooLong
        case invalidCharacters
        case alreadyAssigned

        var message: String {
            switch self {
            case .tooLong: return "Use 64 characters or fewer for the alias."
            case .invalidCharacters: return "Use a plain-text nickname for the alias."
            case .alreadyAssigned: return "Another application already uses this alias. Choose a different nickname."
            }
        }
    }

    /// Empty input removes the override. Whitespace becomes one space and Unicode stays intact.
    static func normalized(_ value: String) throws -> String? {
        let normalized = value.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard normalized.isEmpty == false else { return nil }
        guard normalized.count <= maximumLength else { throw ValidationError.tooLong }
        guard normalized.unicodeScalars.contains(where: { $0.properties.generalCategory == .control }) == false else {
            throw ValidationError.invalidCharacters
        }
        return normalized
    }

    static func comparisonKey(_ value: String) -> String {
        value.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }

    static func validate(
        _ value: String,
        for bundleIdentifier: String,
        aliases: [String: String]
    ) throws -> String? {
        guard let normalized = try normalized(value) else { return nil }
        let key = comparisonKey(normalized)
        guard aliases.contains(where: {
            $0.key != bundleIdentifier && comparisonKey($0.value) == key
        }) == false else { throw ValidationError.alreadyAssigned }
        return normalized
    }

    /// An exact nickname outranks incidental title matches; partial aliases remain searchable.
    static func score(query: String, alias: String?) -> Double? {
        guard let alias, let normalized = try? normalized(alias) else { return nil }
        let needle = comparisonKey(query)
        guard needle.isEmpty == false else { return nil }
        let key = comparisonKey(normalized)
        if key == needle { return SearchMatchScorer.exactTitle + 0.4 }
        if key.hasPrefix(needle) { return SearchMatchScorer.titlePrefix }
        if key.contains(needle) { return SearchMatchScorer.keywordContains }
        return nil
    }
}
