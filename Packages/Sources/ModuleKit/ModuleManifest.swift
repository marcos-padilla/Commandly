import CommandKit
import Foundation

/// Stable identifier for a feature module.
///
/// Module identifiers are persisted in preferences and documentation references, so they must not
/// change once a module ships. They are deliberately distinct from ``CommandID``: one module can
/// own several commands and launcher applications.
public struct ModuleID: Hashable, Sendable, Codable, RawRepresentable {
    public let rawValue: String

    /// Creates a module identifier.
    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

/// Shipping state of a module's user-facing feature.
public enum ModuleFeatureStatus: String, Sendable, Codable, CaseIterable, Equatable {
    /// Available to all users.
    case shipping
    /// Available but explicitly marked experimental in settings and documentation.
    case experimental
    /// Present in the build but not registered for users. Used for gated features.
    case gated
}

/// When a module's retained services may start.
public enum ModuleActivationPolicy: String, Sendable, Codable, CaseIterable, Equatable {
    /// Services are constructed the first time one of the module's commands is dispatched.
    case onDemand
    /// Services start during application startup when the module is enabled.
    ///
    /// Reserved for features whose whole purpose is background behavior, such as clipboard
    /// monitoring. Metadata discovery never triggers this.
    case atLaunchWhenEnabled
}

/// A non-secret capability a module needs before its commands can run.
///
/// Requirements are declarative metadata. Evaluating them is the host application's job; declaring
/// one must never prompt the user or touch private data.
public enum ModuleCapabilityRequirement: Sendable, Hashable, Codable {
    /// A macOS permission identified by the platform permission service.
    case permission(identifier: String)
    /// A user-supplied account connection, such as a BYOK provider or workspace token.
    case accountConnection(identifier: String)
    /// A user-granted folder scope.
    case folderAccess(identifier: String)
    /// An optional helper process or app extension.
    case helper(identifier: String)
}

/// Static, service-free description of a feature module.
///
/// Reading a manifest must never construct services, request permissions, open connections, read
/// private data, or begin indexing. The host relies on that guarantee so Settings and Documentation
/// can list every module — including disabled and unavailable ones — without side effects.
public struct ModuleManifest: Sendable, Identifiable, Equatable {
    /// Stable module identity.
    public let id: ModuleID
    /// User-facing module name.
    public let title: String
    /// One-line description used by Settings and generated documentation.
    public let summary: String
    /// Shipping state shown in Settings and documentation.
    public let status: ModuleFeatureStatus
    /// Launcher application identifiers this module owns.
    public let ownedApplicationIDs: [CommandID]
    /// Command identifiers this module owns. Must match the declared command definitions.
    public let ownedCommandIDs: [CommandID]
    /// Capabilities required before the module's commands can execute.
    public let capabilities: [ModuleCapabilityRequirement]
    /// When the module's retained services may start.
    public let activationPolicy: ModuleActivationPolicy
    /// Version of the module's persisted configuration schema.
    ///
    /// Increment only when stored configuration requires a migration.
    public let configurationVersion: Int
    /// Documentation article identifiers authored by this module.
    public let documentationArticleIDs: [String]

    /// Creates a module manifest.
    public init(
        id: ModuleID,
        title: String,
        summary: String,
        status: ModuleFeatureStatus = .shipping,
        ownedApplicationIDs: [CommandID] = [],
        ownedCommandIDs: [CommandID] = [],
        capabilities: [ModuleCapabilityRequirement] = [],
        activationPolicy: ModuleActivationPolicy = .onDemand,
        configurationVersion: Int = 1,
        documentationArticleIDs: [String] = []
    ) {
        self.id = id
        self.title = title
        self.summary = summary
        self.status = status
        self.ownedApplicationIDs = ownedApplicationIDs
        self.ownedCommandIDs = ownedCommandIDs
        self.capabilities = capabilities
        self.activationPolicy = activationPolicy
        self.configurationVersion = configurationVersion
        self.documentationArticleIDs = documentationArticleIDs
    }
}
