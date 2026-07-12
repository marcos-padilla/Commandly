import Foundation

/// Opens applications by bundle identifier or URL.
public protocol ApplicationOpening: Sendable {
    /// Opens an application identified by bundle identifier.
    func openApplication(bundleIdentifier: String) async throws
}

/// Opens URLs after validation by higher layers.
public protocol URLOpening: Sendable {
    /// Opens a URL.
    func openURL(_ url: URL) async throws
}

/// Constrained filesystem access boundary.
public protocol FileSystemAccessing: Sendable {
    /// Checks whether a path exists.
    func fileExists(at path: String) async -> Bool
}

/// Pasteboard access boundary. Implementations must not log pasteboard contents.
public protocol PasteboardAccessing: Sendable {
    /// Reads a string from the pasteboard, if present.
    func readString() async -> String?
    /// Writes a string to the pasteboard.
    func writeString(_ string: String) async
}

/// User notification posting boundary.
public protocol NotificationPosting: Sendable {
    /// Posts a user-visible notification with a title and body.
    func post(title: String, body: String) async throws
}

/// Workspace / running-application introspection boundary.
public protocol WorkspaceAccessing: Sendable {
    /// Returns bundle identifiers of running applications.
    func runningApplicationBundleIdentifiers() async -> [String]
}
