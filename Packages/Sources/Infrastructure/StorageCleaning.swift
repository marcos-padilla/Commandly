import Foundation

/// A reviewable class of disk space that Storage Cleaner can move to the Trash.
public enum StorageCleanupCategory: String, CaseIterable, Sendable, Equatable, Hashable {
    /// Identifier-named support data whose owning application is no longer installed.
    case applicationLeftover
    /// Re-creatable third-party data under the current user's Library/Caches directory.
    case cache
    /// Byte-for-byte identical files found inside a folder explicitly selected by the user.
    case duplicate
}

/// One file or directory found by a Storage Cleaner scan.
public struct StorageCleanupItem: Sendable, Equatable, Identifiable, Hashable {
    public var id: String { path }

    public let name: String
    /// Parent directory shown to the user, with the current user's home abbreviated to `~`.
    public let containerPath: String
    public let path: String
    public let byteCount: Int64
    public let category: StorageCleanupCategory
    /// Present for identifier-based application leftovers.
    public let associatedBundleIdentifier: String?
    /// Shared by byte-for-byte identical files in one duplicate group.
    public let duplicateGroupID: String?
    /// Whether the scanner recommends selecting this item for cleanup.
    ///
    /// Cache entries default to review-only. Duplicate groups recommend all but one copy.
    public let isSuggestedForRemoval: Bool

    public init(
        name: String,
        containerPath: String,
        path: String,
        byteCount: Int64,
        category: StorageCleanupCategory,
        associatedBundleIdentifier: String? = nil,
        duplicateGroupID: String? = nil,
        isSuggestedForRemoval: Bool
    ) {
        self.name = name
        self.containerPath = containerPath
        self.path = path
        self.byteCount = byteCount
        self.category = category
        self.associatedBundleIdentifier = associatedBundleIdentifier
        self.duplicateGroupID = duplicateGroupID
        self.isSuggestedForRemoval = isSuggestedForRemoval
    }
}

/// Result metadata for a bounded Storage Cleaner scan.
public struct StorageCleanupScanResult: Sendable, Equatable {
    public let items: [StorageCleanupItem]
    public let inspectedFileCount: Int
    /// True when an access error or safety limit prevented a complete scan of the requested scope.
    public let isPartial: Bool

    public init(
        items: [StorageCleanupItem],
        inspectedFileCount: Int = 0,
        isPartial: Bool = false
    ) {
        self.items = items
        self.inspectedFileCount = inspectedFileCount
        self.isPartial = isPartial
    }
}

/// Discovers reviewable cleanup candidates without mutating the filesystem.
public protocol StorageCleanupScanning: Sendable {
    /// Scans the current user's supported Library locations for app leftovers and caches.
    func scanLibrary() async throws -> StorageCleanupScanResult

    /// Finds exact duplicate regular files beneath an explicitly selected directory.
    func scanDuplicates(in directory: URL) async throws -> StorageCleanupScanResult
}

/// Presents a user-driven folder picker for an ephemeral duplicate scan.
@MainActor
public protocol StorageCleanupDirectoryChoosing: Sendable {
    /// Returns the folder selected by the user, or `nil` when the picker was cancelled.
    func chooseDuplicateScanDirectory() async -> URL?
}

/// Deterministic scanner used by tests and previews.
public actor InMemoryStorageCleanupScanner: StorageCleanupScanning {
    public var libraryResult: StorageCleanupScanResult
    public var duplicateResult: StorageCleanupScanResult
    public private(set) var duplicateDirectories: [URL] = []

    public init(
        libraryResult: StorageCleanupScanResult = StorageCleanupScanResult(items: []),
        duplicateResult: StorageCleanupScanResult = StorageCleanupScanResult(items: [])
    ) {
        self.libraryResult = libraryResult
        self.duplicateResult = duplicateResult
    }

    public func scanLibrary() async throws -> StorageCleanupScanResult {
        libraryResult
    }

    public func scanDuplicates(in directory: URL) async throws -> StorageCleanupScanResult {
        duplicateDirectories.append(directory)
        return duplicateResult
    }
}

/// Deterministic duplicate-scan folder picker used by tests and previews.
@MainActor
public final class InMemoryStorageCleanupDirectoryChooser: StorageCleanupDirectoryChoosing {
    public var selectedDirectory: URL?
    public private(set) var requestCount = 0

    public init(selectedDirectory: URL? = nil) {
        self.selectedDirectory = selectedDirectory
    }

    public func chooseDuplicateScanDirectory() async -> URL? {
        requestCount += 1
        return selectedDirectory
    }
}
