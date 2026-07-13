import Foundation

/// A locally stored reusable item in Commandly's productivity library.
enum ProductivityLibraryItemKind: String, CaseIterable, Codable, Identifiable, Sendable {
    case snippet
    case quickNote
    case quicklink
    case emojiKeyword

    var id: String { rawValue }

    var title: String {
        switch self {
        case .snippet: return "Snippet"
        case .quickNote: return "Quick Note"
        case .quicklink: return "Quicklink"
        case .emojiKeyword: return "Emoji Keyword"
        }
    }

    var pluralTitle: String {
        switch self {
        case .snippet: return "Snippets"
        case .quickNote: return "Quick Notes"
        case .quicklink: return "Quicklinks"
        case .emojiKeyword: return "Emoji Keywords"
        }
    }

    var systemImage: String {
        switch self {
        case .snippet: return "chevron.left.forwardslash.chevron.right"
        case .quickNote: return "note.text"
        case .quicklink: return "link"
        case .emojiKeyword: return "face.smiling"
        }
    }

    var primaryActionTitle: String {
        switch self {
        case .snippet: return "Copy Snippet"
        case .quickNote: return "Copy Note"
        case .quicklink: return "Open Quicklink"
        case .emojiKeyword: return "Copy Emoji"
        }
    }

    var contentLabel: String {
        switch self {
        case .snippet: return "Snippet body"
        case .quickNote: return "Note"
        case .quicklink: return "URL or path"
        case .emojiKeyword: return "Emoji"
        }
    }

    var contentPlaceholder: String {
        switch self {
        case .snippet:
            return "Paste reusable text or code. Use {{clipboard}} to insert current clipboard text."
        case .quickNote:
            return "Write a note you want nearby."
        case .quicklink:
            return "https://example.com, file:///…, /a/local/path, or an app deeplink"
        case .emojiKeyword:
            return "Add the emoji associated with this keyword."
        }
    }
}

/// Immutable value persisted by the productivity library store.
struct ProductivityLibraryItem: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    var kind: ProductivityLibraryItemKind
    var title: String
    var content: String
    let createdAt: Date
    var updatedAt: Date
}

/// Validation errors intentionally omit user-authored values so they remain safe to surface or log.
enum ProductivityLibraryValidationError: Error, Equatable, Sendable {
    case missingTitle
    case missingContent
    case invalidQuicklink

    var message: String {
        switch self {
        case .missingTitle:
            return "Add a name before saving."
        case .missingContent:
            return "Add content before saving."
        case .invalidQuicklink:
            return "Use a valid web URL, file path, folder path, or app deeplink."
        }
    }
}

/// Validates Quicklinks without opening them or touching the filesystem.
struct ProductivityQuicklinkValidator: Sendable {
    private nonisolated static let forbiddenSchemes: Set<String> = ["data", "javascript"]

    nonisolated func validatedURL(from value: String) throws -> URL {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false,
              trimmed.rangeOfCharacter(from: .newlines) == nil else {
            throw ProductivityLibraryValidationError.invalidQuicklink
        }

        if trimmed.hasPrefix("/") || trimmed.hasPrefix("~/") {
            let expanded = (trimmed as NSString).expandingTildeInPath
            guard expanded.hasPrefix("/") else {
                throw ProductivityLibraryValidationError.invalidQuicklink
            }
            return URL(fileURLWithPath: expanded)
        }

        guard let components = URLComponents(string: trimmed),
              let rawScheme = components.scheme,
              rawScheme.isEmpty == false else {
            throw ProductivityLibraryValidationError.invalidQuicklink
        }
        let scheme = rawScheme.lowercased()
        guard Self.forbiddenSchemes.contains(scheme) == false,
              Self.isValidScheme(scheme),
              let url = components.url else {
            throw ProductivityLibraryValidationError.invalidQuicklink
        }

        switch scheme {
        case "http", "https":
            guard let host = components.host, host.isEmpty == false else {
                throw ProductivityLibraryValidationError.invalidQuicklink
            }
        case "file":
            guard url.isFileURL, url.path.isEmpty == false else {
                throw ProductivityLibraryValidationError.invalidQuicklink
            }
        default:
            // Valid custom schemes are intentional app deeplinks. Their owning app performs
            // any scheme-specific validation after NSWorkspace dispatches the URL.
            break
        }
        return url
    }

    private nonisolated static func isValidScheme(_ value: String) -> Bool {
        guard let first = value.unicodeScalars.first,
              CharacterSet.letters.contains(first) else {
            return false
        }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "+-."))
        return value.unicodeScalars.allSatisfy { allowed.contains($0) }
    }
}
