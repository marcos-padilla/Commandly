import Foundation

/// Bounded, case-insensitive labels kept with private library content, never in logs.
nonisolated enum ProductivityLibraryTags {
    static let maximumCount = 12
    static let maximumLength = 32

    static func normalized(_ values: [String], limit: Int = maximumCount) -> [String] {
        var seen = Set<String>()
        return values.compactMap { raw in
            let tag = String(raw.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maximumLength))
            guard !tag.isEmpty, seen.insert(tag.lowercased()).inserted else { return nil }
            return tag
        }.prefix(limit).map { $0 }
    }

    static func parse(_ text: String) -> [String] {
        normalized(text.components(separatedBy: CharacterSet(charactersIn: ",\n")))
    }
}
