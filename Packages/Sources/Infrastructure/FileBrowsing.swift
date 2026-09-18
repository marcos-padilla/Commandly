import Foundation

/// An opaque, session-local identity for one explicitly authorized folder.
public struct FileBrowserRoot: Identifiable, Sendable, Equatable {
    public let id: String
    public let name: String
    public init(id: String, name: String) { self.id = id; self.name = name }
}

/// A location relative to one authorized root. Services must validate every component.
public struct FileBrowserLocation: Sendable, Equatable, Hashable {
    public let rootID: String
    public let components: [String]
    public init(rootID: String, components: [String] = []) { self.rootID = rootID; self.components = components }
    public var parent: FileBrowserLocation? {
        components.isEmpty ? nil : FileBrowserLocation(rootID: rootID, components: Array(components.dropLast()))
    }
}

/// Filesystem identity captured during enumeration and revalidated before opening.
public struct FileBrowserIdentity: Sendable, Equatable {
    public let device: UInt64
    public let inode: UInt64
    public init(device: UInt64, inode: UInt64) { self.device = device; self.inode = inode }
}

/// Read-only metadata for one immediate directory child; no file contents are included.
public struct FileBrowserEntry: Identifiable, Sendable, Equatable {
    public enum Kind: String, Sendable { case folder, file, package, symbolicLink, alias }
    public let location: FileBrowserLocation
    public let name: String
    public let kind: Kind
    public let identity: FileBrowserIdentity
    public let byteCount: Int64?
    public let modifiedAt: Date?
    public var id: FileBrowserLocation { location }
    public var isActionable: Bool { kind != .symbolicLink && kind != .alias }
    public init(location: FileBrowserLocation, name: String, kind: Kind, identity: FileBrowserIdentity,
                byteCount: Int64? = nil, modifiedAt: Date? = nil) {
        self.location = location; self.name = name; self.kind = kind; self.identity = identity
        self.byteCount = byteCount; self.modifiedAt = modifiedAt
    }
}

/// A bounded, one-level snapshot. Truncation must remain visible to the user.
public struct FileBrowserSnapshot: Sendable, Equatable {
    public let location: FileBrowserLocation
    public let entries: [FileBrowserEntry]
    public let isTruncated: Bool
    public init(location: FileBrowserLocation, entries: [FileBrowserEntry], isTruncated: Bool = false) {
        self.location = location; self.entries = entries; self.isTruncated = isTruncated
    }
}

/// Errors intentionally omit private paths and filesystem error descriptions.
public enum FileBrowserError: Error, Sendable, Equatable {
    case noAuthorizedFolders, authorizationUnavailable, accessDenied, folderUnavailable
    case unsafeLocation, itemChanged, unsupportedItem, openFailed
}

/// Browses only current user-authorized folders and opens only revalidated selected files.
public protocol FileBrowsing: Sendable {
    func roots() async throws -> [FileBrowserRoot]
    func list(_ location: FileBrowserLocation) async throws -> FileBrowserSnapshot
    /// The service must retain authorization through the injected opener's completion.
    func open(_ entry: FileBrowserEntry, using opener: any URLOpening) async throws
}
