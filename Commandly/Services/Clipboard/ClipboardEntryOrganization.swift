import Foundation

/// User-authored metadata for one ephemeral clipboard entry. Never persisted or logged.
nonisolated struct ClipboardEntryOrganization: Hashable, Sendable {
    static let maximumNameLength = 120
    static let maximumCollectionLength = 40

    var name: String?
    var collection: String?
    var isPinned: Bool

    init(name: String? = nil, collection: String? = nil, isPinned: Bool = false) {
        self.name = name
        self.collection = collection
        self.isPinned = isPinned
    }

    static func normalized(_ value: String) -> String? {
        let normalized = value.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return normalized.isEmpty ? nil : normalized
    }
}

/// Fixed error messages omit clipboard contents and user-authored metadata.
enum ClipboardOrganizationError: Error, LocalizedError {
    case entryMissing
    case nameTooLong
    case collectionTooLong
    case pinLimitReached

    var errorDescription: String? {
        switch self {
        case .entryMissing:
            return "This entry is no longer in clipboard history."
        case .nameTooLong:
            return "Use a name of at most 120 characters."
        case .collectionTooLong:
            return "Use a collection name of at most 40 characters."
        case .pinLimitReached:
            return "Unpin an entry first. One history slot stays available for new copies."
        }
    }
}
