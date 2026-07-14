import CoreTransferable
import Foundation
import UniformTypeIdentifiers

/// User-facing semantic kind for homogeneous Shelf counts.
nonisolated enum ShelfItemKind: Hashable, Sendable {
    case folder
    case image
    case pdf
    case document
    case audio
    case video
    case archive
    case application
    case file

    func countDescription(_ count: Int) -> String {
        let noun = count == 1 ? singularNoun : pluralNoun
        return "\(count) \(noun)"
    }

    private var singularNoun: String {
        switch self {
        case .folder: return "folder"
        case .image: return "image"
        case .pdf: return "PDF"
        case .document: return "document"
        case .audio: return "audio file"
        case .video: return "video"
        case .archive: return "archive"
        case .application: return "application"
        case .file: return "file"
        }
    }

    private var pluralNoun: String {
        switch self {
        case .folder: return "folders"
        case .image: return "images"
        case .pdf: return "PDFs"
        case .document: return "documents"
        case .audio: return "audio files"
        case .video: return "videos"
        case .archive: return "archives"
        case .application: return "applications"
        case .file: return "files"
        }
    }
}

/// Whether Shelf owns the underlying file or only keeps a reference supplied by the user.
nonisolated enum ShelfItemOwnership: Hashable, Sendable {
    case externalReference
    case shelfTemporary
}

/// A temporary reference to a file or folder staged on a Shelf board.
///
/// Shelf does not copy an item when it is added. The URL remains the source of truth until the
/// reference is removed, the file moves, or the board closes.
nonisolated struct ShelfItem: Identifiable, Hashable, Sendable {
    typealias ID = String

    let id: ID
    var url: URL
    var displayName: String
    var isDirectory: Bool
    var byteCount: Int64?
    var contentTypeIdentifier: String?
    var isAvailable: Bool
    var ownership: ShelfItemOwnership

    init(
        url: URL,
        displayName: String? = nil,
        isDirectory: Bool = false,
        byteCount: Int64? = nil,
        contentTypeIdentifier: String? = nil,
        isAvailable: Bool = true,
        ownership: ShelfItemOwnership = .externalReference
    ) {
        let normalizedURL = Self.normalized(url)
        self.id = normalizedURL.path
        self.url = normalizedURL
        self.displayName = displayName ?? normalizedURL.lastPathComponent
        self.isDirectory = isDirectory
        self.byteCount = byteCount
        self.contentTypeIdentifier = contentTypeIdentifier
        self.isAvailable = isAvailable
        self.ownership = ownership
    }

    static func normalized(_ url: URL) -> URL {
        url.standardizedFileURL
    }

    var kind: ShelfItemKind {
        let type = contentTypeIdentifier.map(UTType.init)
            ?? UTType(filenameExtension: url.pathExtension)
        if type?.conforms(to: .application) == true { return .application }
        if isDirectory { return .folder }
        if type?.conforms(to: .image) == true { return .image }
        if type?.conforms(to: .pdf) == true { return .pdf }
        if type?.conforms(to: .audio) == true { return .audio }
        if type?.conforms(to: .movie) == true { return .video }
        if type?.conforms(to: .archive) == true { return .archive }
        if type?.conforms(to: .text) == true
            || type?.conforms(to: .sourceCode) == true
            || type?.conforms(to: .spreadsheet) == true
            || type?.conforms(to: .presentation) == true
            || type?.conforms(to: .compositeContent) == true
            || Self.documentExtensions.contains(url.pathExtension.lowercased()) {
            return .document
        }
        return .file
    }

    private static let documentExtensions: Set<String> = [
        "doc", "docx", "pages", "rtf", "txt", "md", "csv", "tsv", "xls", "xlsx",
        "numbers", "ppt", "pptx", "key"
    ]
}

nonisolated extension ShelfItem: Transferable {
    static var transferRepresentation: some TransferRepresentation {
        ProxyRepresentation(exporting: \.url)
    }
}
