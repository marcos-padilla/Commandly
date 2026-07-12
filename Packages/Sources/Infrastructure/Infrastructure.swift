import Foundation

/// Opens applications by bundle identifier or URL.
public protocol ApplicationOpening: Sendable {
    /// Opens an application identified by bundle identifier.
    func openApplication(bundleIdentifier: String) async throws
}

/// A discovered installed application.
public struct InstalledApplication: Sendable, Equatable, Identifiable, Hashable {
    public var id: String { bundleIdentifier }
    public let bundleIdentifier: String
    public let name: String
    public let path: String

    /// Creates an installed application record.
    public init(bundleIdentifier: String, name: String, path: String) {
        self.bundleIdentifier = bundleIdentifier
        self.name = name
        self.path = path
    }
}

/// Enumerates applications available to launch from the launcher.
///
/// Implementations must not block the main actor and must not log user file contents.
public protocol InstalledApplicationQuerying: Sendable {
    /// Returns installed applications (may be cached).
    func installedApplications() async -> [InstalledApplication]
}

/// In-memory application catalog for tests and previews.
public struct InMemoryInstalledApplicationQuery: InstalledApplicationQuerying {
    private let applications: [InstalledApplication]

    /// Creates a query backed by a fixed list.
    public init(applications: [InstalledApplication] = []) {
        self.applications = applications
    }

    public func installedApplications() async -> [InstalledApplication] {
        applications
    }
}

/// No-op application opener for tests.
public struct NoOpApplicationOpener: ApplicationOpening {
    public init() {}

    public func openApplication(bundleIdentifier: String) async throws {
        _ = bundleIdentifier
    }
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

/// Status of the app's login-item registration.
public enum LoginItemStatus: String, Sendable, Equatable {
    /// Registered and allowed to launch at login.
    case enabled
    /// Not registered.
    case disabled
    /// Registered, but the user must approve it in System Settings.
    case requiresApproval
    /// Login items are unavailable in this environment.
    case unavailable
}

/// Registers or unregisters the app as a login item.
///
/// Call only after explicit user intent (for example, an onboarding toggle).
public protocol LoginItemManaging: Sendable {
    /// Returns the current login-item status.
    func status() async -> LoginItemStatus
    /// Enables or disables launching at login.
    func setEnabled(_ enabled: Bool) async throws
}

/// In-memory login item manager for tests and previews. Never touches the system.
///
/// `@unchecked Sendable`: guarded by an internal lock; safe for concurrent test use.
public final class InMemoryLoginItemManager: LoginItemManaging, @unchecked Sendable {
    private let lock = NSLock()
    private var currentStatus: LoginItemStatus
    private let shouldFail: Bool

    /// Creates a manager with an optional starting status.
    public init(status: LoginItemStatus = .disabled, shouldFail: Bool = false) {
        self.currentStatus = status
        self.shouldFail = shouldFail
    }

    public func status() async -> LoginItemStatus {
        lock.withLock { currentStatus }
    }

    public func setEnabled(_ enabled: Bool) async throws {
        try lock.withLock {
            if shouldFail {
                throw LoginItemError.updateFailed
            }
            currentStatus = enabled ? .enabled : .disabled
        }
    }
}

/// Errors produced while updating login-item registration.
public enum LoginItemError: Error, Sendable, Equatable {
    /// The system rejected or failed the registration change.
    case updateFailed
}

/// Privacy panes that Commandly may deep-link into for recovery.
public enum PrivacySettingsPane: String, Sendable, Equatable {
    case accessibility
    case calendars
    case contacts
    case filesAndFolders
}

/// Opens macOS System Settings privacy panes after user intent.
public protocol PrivacySettingsOpening: Sendable {
    /// Opens the given privacy pane when possible.
    func open(_ pane: PrivacySettingsPane) async
}

/// In-memory privacy settings opener for tests.
public struct InMemoryPrivacySettingsOpener: PrivacySettingsOpening, Sendable {
    /// Creates a no-op opener.
    public init() {}

    public func open(_ pane: PrivacySettingsPane) async {}
}
