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

/// Reveals files or folders in Finder.
public protocol FileRevealing: Sendable {
    /// Selects the given file URLs in a Finder window.
    func revealInFinder(urls: [URL]) async throws
}

/// A system-provided application, sharing service, or destination shown by file actions.
public struct FileActionOption: Sendable, Equatable, Identifiable, Hashable {
    public let id: String
    public let title: String
    public let subtitle: String?

    public init(id: String, title: String, subtitle: String? = nil) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
    }
}

/// File operations and native system integrations used by File Search.
@MainActor
public protocol FileActionServicing: Sendable {
    func applications(toOpen url: URL) async -> [FileActionOption]
    func open(_ url: URL, withApplication optionID: String) async throws
    func sharingServices(for url: URL) async -> [FileActionOption]
    func share(_ url: URL, withService optionID: String) async throws
    func chooseDestination(title: String) async -> URL?
    func duplicate(_ url: URL) async throws -> URL
    func copy(_ url: URL, to directory: URL) async throws -> URL
    func move(_ url: URL, to directory: URL) async throws -> URL
    func createShortcut(for url: URL, in directory: URL) async throws -> URL
    func moveToTrash(_ url: URL) async throws
}

/// No-op file actions used by previews and tests that do not exercise actions.
@MainActor
public final class InMemoryFileActionService: FileActionServicing {
    public var applicationOptions: [FileActionOption]
    public var sharingOptions: [FileActionOption]
    public var chosenDestination: URL?
    public private(set) var opened: [(URL, String)] = []
    public private(set) var shared: [(URL, String)] = []
    public private(set) var duplicated: [URL] = []
    public private(set) var copied: [(URL, URL)] = []
    public private(set) var moved: [(URL, URL)] = []
    public private(set) var shortcuts: [(URL, URL)] = []
    public private(set) var trashed: [URL] = []

    public init(
        applicationOptions: [FileActionOption] = [],
        sharingOptions: [FileActionOption] = [],
        chosenDestination: URL? = nil
    ) {
        self.applicationOptions = applicationOptions
        self.sharingOptions = sharingOptions
        self.chosenDestination = chosenDestination
    }

    public func applications(toOpen url: URL) async -> [FileActionOption] { applicationOptions }
    public func open(_ url: URL, withApplication optionID: String) async throws { opened.append((url, optionID)) }
    public func sharingServices(for url: URL) async -> [FileActionOption] { sharingOptions }
    public func share(_ url: URL, withService optionID: String) async throws { shared.append((url, optionID)) }
    public func chooseDestination(title: String) async -> URL? { chosenDestination }
    public func duplicate(_ url: URL) async throws -> URL {
        duplicated.append(url)
        return url.deletingPathExtension().appendingPathExtension("copy.\(url.pathExtension)")
    }
    public func copy(_ url: URL, to directory: URL) async throws -> URL {
        copied.append((url, directory))
        return directory.appendingPathComponent(url.lastPathComponent)
    }
    public func move(_ url: URL, to directory: URL) async throws -> URL {
        moved.append((url, directory))
        return directory.appendingPathComponent(url.lastPathComponent)
    }
    public func createShortcut(for url: URL, in directory: URL) async throws -> URL {
        shortcuts.append((url, directory))
        return directory.appendingPathComponent("\(url.deletingPathExtension().lastPathComponent) Commandly Shortcut.webloc")
    }
    public func moveToTrash(_ url: URL) async throws { trashed.append(url) }
}

/// Application-bundle file operations (package contents, trash).
public protocol ApplicationBundleManaging: Sendable {
    /// Opens the `Contents` directory inside an `.app` bundle.
    func showPackageContents(atApplicationPath path: String) async throws
    /// Moves a file or folder to the Trash when the sandbox allows it.
    func moveItemToTrash(atPath path: String) async throws
}

extension ApplicationBundleManaging {
    /// Moves an application bundle to the Trash when the sandbox allows it.
    public func moveApplicationToTrash(atPath path: String) async throws {
        try await moveItemToTrash(atPath: path)
    }
}

/// Kind of related uninstall candidate.
public enum ApplicationRelatedItemKind: String, Sendable, Equatable, Hashable {
    case application
    case folder
    case file
    case preferences
}

/// A file or folder associated with an installed application.
public struct ApplicationRelatedItem: Sendable, Equatable, Identifiable, Hashable {
    public var id: String { path }
    public let name: String
    /// Parent directory shown as muted path text (e.g. `~/Library/Caches`).
    public let containerPath: String
    public let path: String
    public let byteCount: Int64
    public let kind: ApplicationRelatedItemKind

    public init(
        name: String,
        containerPath: String,
        path: String,
        byteCount: Int64,
        kind: ApplicationRelatedItemKind
    ) {
        self.name = name
        self.containerPath = containerPath
        self.path = path
        self.byteCount = byteCount
        self.kind = kind
    }
}

/// Discovers support files and folders related to an installed application.
public protocol ApplicationUninstallDiscovering: Sendable {
    /// Returns related items for the given application (may be empty beyond the `.app`).
    func relatedItems(for application: InstalledApplication) async -> [ApplicationRelatedItem]
}

/// Presents Finder’s Get Info window for a path (may require Apple Events).
public protocol FinderInfoPresenting: Sendable {
    /// Opens the Get Info window for the item at `path`.
    func showGetInfo(atPath path: String) async throws
}

/// Snapshot of a running application for auto-quit and workspace introspection.
public struct RunningApplicationSnapshot: Sendable, Equatable, Hashable {
    public let bundleIdentifier: String
    public let isActive: Bool

    public init(bundleIdentifier: String, isActive: Bool) {
        self.bundleIdentifier = bundleIdentifier
        self.isActive = isActive
    }
}

/// Controls running applications (introspection + terminate).
public protocol RunningApplicationControlling: Sendable {
    /// Bundle identifier of the frontmost app, if any.
    func frontmostBundleIdentifier() async -> String?
    /// Currently running user applications with bundle identifiers.
    func runningApplications() async -> [RunningApplicationSnapshot]
    /// Requests a graceful terminate for the given bundle identifier.
    @discardableResult
    func terminate(bundleIdentifier: String) async -> Bool
}

/// Errors from workspace / Finder / URL adapters.
public enum WorkspaceServiceError: Error, Sendable, Equatable {
    case notFound(String)
    case failed(String)
}

/// No-op URL opener for tests.
public struct NoOpURLOpener: URLOpening {
    public init() {}

    public func openURL(_ url: URL) async throws {
        _ = url
    }
}

/// In-memory file revealer for tests.
public final class InMemoryFileRevealer: FileRevealing, @unchecked Sendable {
    private let lock = NSLock()
    public private(set) var revealedURLs: [URL] = []
    public var shouldFail = false

    public init() {}

    public func revealInFinder(urls: [URL]) async throws {
        try lock.withLock {
            if shouldFail {
                throw WorkspaceServiceError.failed("reveal")
            }
            revealedURLs.append(contentsOf: urls)
        }
    }
}

/// In-memory application bundle manager for tests.
public final class InMemoryApplicationBundleManager: ApplicationBundleManaging, @unchecked Sendable {
    private let lock = NSLock()
    public private(set) var packageContentPaths: [String] = []
    public private(set) var trashedPaths: [String] = []
    public var shouldFailTrash = false
    public var shouldFailPackageContents = false

    public init() {}

    public func showPackageContents(atApplicationPath path: String) async throws {
        try lock.withLock {
            if shouldFailPackageContents {
                throw WorkspaceServiceError.failed("package")
            }
            packageContentPaths.append(path)
        }
    }

    public func moveItemToTrash(atPath path: String) async throws {
        try lock.withLock {
            if shouldFailTrash {
                throw WorkspaceServiceError.failed("trash")
            }
            trashedPaths.append(path)
        }
    }
}

/// In-memory uninstall discoverer for tests.
public final class InMemoryApplicationUninstallDiscoverer: ApplicationUninstallDiscovering, @unchecked Sendable {
    private let lock = NSLock()
    public var itemsByBundleID: [String: [ApplicationRelatedItem]] = [:]

    public init(itemsByBundleID: [String: [ApplicationRelatedItem]] = [:]) {
        self.itemsByBundleID = itemsByBundleID
    }

    public func relatedItems(for application: InstalledApplication) async -> [ApplicationRelatedItem] {
        lock.withLock {
            if let items = itemsByBundleID[application.bundleIdentifier] {
                return items
            }
            return [
                ApplicationRelatedItem(
                    name: URL(fileURLWithPath: application.path).lastPathComponent,
                    containerPath: URL(fileURLWithPath: application.path).deletingLastPathComponent().path,
                    path: application.path,
                    byteCount: 0,
                    kind: .application
                )
            ]
        }
    }
}

/// In-memory Finder Get Info presenter for tests.
public final class InMemoryFinderInfoPresenter: FinderInfoPresenting, @unchecked Sendable {
    private let lock = NSLock()
    public private(set) var infoPaths: [String] = []
    public var shouldFail = false

    public init() {}

    public func showGetInfo(atPath path: String) async throws {
        try lock.withLock {
            if shouldFail {
                throw WorkspaceServiceError.failed("getInfo")
            }
            infoPaths.append(path)
        }
    }
}

/// Controllable running-application source for tests.
public final class InMemoryRunningApplicationController: RunningApplicationControlling, @unchecked Sendable {
    private let lock = NSLock()
    public var frontmost: String?
    public var running: [RunningApplicationSnapshot] = []
    public private(set) var terminated: [String] = []

    public init(frontmost: String? = nil, running: [RunningApplicationSnapshot] = []) {
        self.frontmost = frontmost
        self.running = running
    }

    public func frontmostBundleIdentifier() async -> String? {
        lock.withLock { frontmost }
    }

    public func runningApplications() async -> [RunningApplicationSnapshot] {
        lock.withLock { running }
    }

    public func terminate(bundleIdentifier: String) async -> Bool {
        lock.withLock {
            terminated.append(bundleIdentifier)
            running.removeAll { $0.bundleIdentifier == bundleIdentifier }
            if frontmost == bundleIdentifier {
                frontmost = nil
            }
            return true
        }
    }
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
    /// Reads file URLs from the pasteboard in pasteboard order.
    func readFileURLs() async -> [URL]
    /// Writes a string to the pasteboard.
    func writeString(_ string: String) async
    /// Writes file URLs so Finder and other apps can paste the files themselves.
    func writeFileURLs(_ urls: [URL]) async
}

extension PasteboardAccessing {
    /// Default for pasteboards that do not expose file URL reads.
    public func readFileURLs() async -> [URL] {
        []
    }

    public func writeFileURLs(_ urls: [URL]) async {
        if let first = urls.first {
            await writeString(first.path)
        }
    }
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
