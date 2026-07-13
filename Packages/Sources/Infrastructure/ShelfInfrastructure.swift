import Foundation

/// A native sharing destination with a stable identity across launches.
public enum NativeShareDestination: String, CaseIterable, Sendable, Equatable, Hashable {
    /// The system AirDrop sharing service.
    case airDrop
    /// The system Messages compose service.
    case messages
    /// The system Mail compose service.
    case mail
}

/// Content-free filesystem metadata used to represent a staged file or folder.
public struct FileResourceMetadata: Sendable, Equatable, Identifiable, Hashable {
    /// The file URL whose resource values were read.
    public let url: URL
    /// A localized display name suitable for user interfaces.
    public let displayName: String
    /// Whether the resource is a directory.
    public let isDirectory: Bool
    /// The resource size in bytes when the system reports one.
    public let byteCount: Int64?
    /// The Uniform Type Identifier reported by the system, when available.
    public let contentTypeIdentifier: String?
    /// The resource creation date, when available.
    public let creationDate: Date?
    /// The resource modification date, when available.
    public let modificationDate: Date?

    /// Uses the resource URL as the stable identity for the current process.
    public var id: URL { url }

    /// Creates an immutable metadata snapshot.
    public init(
        url: URL,
        displayName: String,
        isDirectory: Bool,
        byteCount: Int64? = nil,
        contentTypeIdentifier: String? = nil,
        creationDate: Date? = nil,
        modificationDate: Date? = nil
    ) {
        self.url = url
        self.displayName = displayName
        self.isDirectory = isDirectory
        self.byteCount = byteCount
        self.contentTypeIdentifier = contentTypeIdentifier
        self.creationDate = creationDate
        self.modificationDate = modificationDate
    }
}

/// Reads filesystem metadata without exposing file contents.
public protocol FileResourceMetadataReading: Sendable {
    /// Returns metadata in the same order as the supplied URLs.
    func metadata(for urls: [URL]) async throws -> [FileResourceMetadata]
}

/// In-memory metadata reader for tests and previews.
public struct InMemoryFileResourceMetadataReader: FileResourceMetadataReading {
    /// Metadata snapshots keyed by their file URL.
    public let metadataByURL: [URL: FileResourceMetadata]
    /// Whether reads should fail with a typed infrastructure error.
    public let shouldFail: Bool

    /// Creates a reader backed by fixed metadata snapshots.
    public init(
        metadata: [FileResourceMetadata] = [],
        shouldFail: Bool = false
    ) {
        self.metadataByURL = Dictionary(
            metadata.map { ($0.url, $0) },
            uniquingKeysWith: { _, replacement in replacement }
        )
        self.shouldFail = shouldFail
    }

    public func metadata(for urls: [URL]) async throws -> [FileResourceMetadata] {
        if shouldFail {
            throw WorkspaceServiceError.failed("metadata")
        }
        return urls.compactMap { metadataByURL[$0] }
    }
}

/// Collection-aware native file operations used by temporary file staging interfaces.
///
/// Implementations preserve the order of supplied URLs and must keep blocking filesystem work off
/// the main actor.
@MainActor
public protocol FileCollectionActionServicing: Sendable {
    /// Returns applications that can open every supplied URL, in system preference order.
    func applications(toOpen urls: [URL]) async -> [FileActionOption]
    /// Opens the ordered URL collection with a previously returned application option.
    func open(_ urls: [URL], withApplication optionID: String) async throws
    /// Returns whether a named native destination can share the complete URL collection.
    func canShare(_ urls: [URL], to destination: NativeShareDestination) -> Bool
    /// Shares the ordered URL collection with a named native destination.
    func share(_ urls: [URL], to destination: NativeShareDestination) throws
    /// Returns available system sharing services for the complete URL collection.
    func sharingServices(for urls: [URL]) async -> [FileActionOption]
    /// Shares the ordered URL collection with a previously returned system service option.
    func share(_ urls: [URL], withService optionID: String) throws
    /// Presents a user-initiated directory picker.
    func chooseDestination(title: String) async -> URL?
    /// Duplicates every URL beside its source and returns destinations in source order.
    func duplicate(_ urls: [URL]) async throws -> [URL]
    /// Copies every URL into the directory and returns destinations in source order.
    func copy(_ urls: [URL], to directory: URL) async throws -> [URL]
    /// Moves every URL into the directory and returns destinations in source order.
    func move(_ urls: [URL], to directory: URL) async throws -> [URL]
    /// Renames one resource and returns its resulting URL.
    func rename(_ url: URL, to newName: String) async throws -> URL
    /// Moves every supplied resource to the Trash.
    func moveToTrash(_ urls: [URL]) async throws
}

/// Presents an ordered collection of file URLs in the system preview interface.
@MainActor
public protocol FilePreviewPresenting: Sendable {
    /// Presents previews with the requested item selected when the index is in range.
    func preview(urls: [URL], selectedIndex: Int)
}

/// In-memory collection file actions for tests and previews.
@MainActor
public final class InMemoryFileCollectionActionService: FileCollectionActionServicing {
    /// Application options returned by `applications(toOpen:)`.
    public var applicationOptions: [FileActionOption]
    /// System sharing options returned by `sharingServices(for:)`.
    public var systemSharingOptions: [FileActionOption]
    /// Named destinations reported as capable.
    public var capableDestinations: Set<NativeShareDestination>
    /// Destination returned by `chooseDestination(title:)`.
    public var chosenDestination: URL?
    /// Whether mutating actions should fail with a typed infrastructure error.
    public var shouldFail = false
    /// Open requests in invocation order.
    public private(set) var opened: [([URL], String)] = []
    /// Named share requests in invocation order.
    public private(set) var namedShares: [([URL], NativeShareDestination)] = []
    /// System share requests in invocation order.
    public private(set) var systemShares: [([URL], String)] = []
    /// Duplicate requests in invocation order.
    public private(set) var duplicated: [[URL]] = []
    /// Copy requests in invocation order.
    public private(set) var copied: [([URL], URL)] = []
    /// Move requests in invocation order.
    public private(set) var moved: [([URL], URL)] = []
    /// Rename requests in invocation order.
    public private(set) var renamed: [(URL, String)] = []
    /// Trash requests in invocation order.
    public private(set) var trashed: [[URL]] = []

    /// Creates configurable in-memory file actions.
    public init(
        applicationOptions: [FileActionOption] = [],
        systemSharingOptions: [FileActionOption] = [],
        capableDestinations: Set<NativeShareDestination> = [],
        chosenDestination: URL? = nil
    ) {
        self.applicationOptions = applicationOptions
        self.systemSharingOptions = systemSharingOptions
        self.capableDestinations = capableDestinations
        self.chosenDestination = chosenDestination
    }

    public func applications(toOpen urls: [URL]) async -> [FileActionOption] {
        _ = urls
        return applicationOptions
    }

    public func open(_ urls: [URL], withApplication optionID: String) async throws {
        try failIfNeeded()
        opened.append((urls, optionID))
    }

    public func canShare(_ urls: [URL], to destination: NativeShareDestination) -> Bool {
        urls.isEmpty == false && capableDestinations.contains(destination)
    }

    public func share(_ urls: [URL], to destination: NativeShareDestination) throws {
        try failIfNeeded()
        namedShares.append((urls, destination))
    }

    public func sharingServices(for urls: [URL]) async -> [FileActionOption] {
        _ = urls
        return systemSharingOptions
    }

    public func share(_ urls: [URL], withService optionID: String) throws {
        try failIfNeeded()
        systemShares.append((urls, optionID))
    }

    public func chooseDestination(title: String) async -> URL? {
        _ = title
        return chosenDestination
    }

    public func duplicate(_ urls: [URL]) async throws -> [URL] {
        try failIfNeeded()
        duplicated.append(urls)
        return urls.map { Self.duplicateDestination(for: $0) }
    }

    public func copy(_ urls: [URL], to directory: URL) async throws -> [URL] {
        try failIfNeeded()
        copied.append((urls, directory))
        return urls.map { directory.appendingPathComponent($0.lastPathComponent) }
    }

    public func move(_ urls: [URL], to directory: URL) async throws -> [URL] {
        try failIfNeeded()
        moved.append((urls, directory))
        return urls.map { directory.appendingPathComponent($0.lastPathComponent) }
    }

    public func rename(_ url: URL, to newName: String) async throws -> URL {
        try failIfNeeded()
        renamed.append((url, newName))
        return url.deletingLastPathComponent().appendingPathComponent(newName)
    }

    public func moveToTrash(_ urls: [URL]) async throws {
        try failIfNeeded()
        trashed.append(urls)
    }

    private func failIfNeeded() throws {
        if shouldFail {
            throw WorkspaceServiceError.failed("file collection action")
        }
    }

    private static func duplicateDestination(for url: URL) -> URL {
        let extensionName = url.pathExtension
        var destination = url.deletingLastPathComponent()
            .appendingPathComponent("\(url.deletingPathExtension().lastPathComponent) copy")
        if extensionName.isEmpty == false {
            destination.appendPathExtension(extensionName)
        }
        return destination
    }
}

/// In-memory preview presenter for tests and previews.
@MainActor
public final class InMemoryFilePreviewPresenter: FilePreviewPresenting {
    /// Preview requests in invocation order.
    public private(set) var requests: [([URL], Int)] = []
    /// Creates an empty preview recorder.
    public init() {}

    public func preview(urls: [URL], selectedIndex: Int) {
        requests.append((urls, selectedIndex))
    }
}
