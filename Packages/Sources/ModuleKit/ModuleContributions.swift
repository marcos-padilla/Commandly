import CommandKit
import Foundation

// MARK: - Settings

/// A non-secret value stored for a module configuration field.
///
/// Secrets and credentials are never represented here; they belong to the secure storage boundary.
public enum ModuleConfigurationValue: Codable, Equatable, Sendable {
    case text(String)
    case boolean(Bool)
    case integer(Int)
    case decimal(Double)

    /// Text payload, when this value is text.
    public var textValue: String? {
        guard case .text(let value) = self else { return nil }
        return value
    }

    /// Boolean payload, when this value is a toggle.
    public var booleanValue: Bool? {
        guard case .boolean(let value) = self else { return nil }
        return value
    }

    /// Integer payload, when this value is a whole number.
    public var integerValue: Int? {
        guard case .integer(let value) = self else { return nil }
        return value
    }

    /// Decimal payload, when this value is a floating-point number.
    public var decimalValue: Double? {
        guard case .decimal(let value) = self else { return nil }
        return value
    }
}

/// Control type rendered for a module configuration field.
public enum ModuleConfigurationFieldKind: String, Codable, Sendable, CaseIterable {
    case text
    case toggle
    case integer
    case decimal
    case selection

    /// Whether a value matches this field's type.
    public func accepts(_ value: ModuleConfigurationValue) -> Bool {
        switch (self, value) {
        case (.text, .text), (.toggle, .boolean), (.integer, .integer),
             (.decimal, .decimal), (.selection, .text):
            return true
        default:
            return false
        }
    }
}

/// One choice offered by a selection field.
public struct ModuleConfigurationOption: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let description: String?

    /// Creates a selection option.
    public init(id: String, title: String, description: String? = nil) {
        self.id = id
        self.title = title
        self.description = description
    }
}

/// Typed schema for one module-owned preference.
///
/// The shared Settings shell generates an ordinary control from this schema. Modules only author a
/// custom settings page when a control genuinely cannot be generated, such as an account
/// connection or a folder grant.
public struct ModuleConfigurationField: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    /// Stable storage key. Changing it requires a configuration migration.
    public let variable: String
    public let title: String
    public let description: String?
    public let placeholder: String?
    /// Optional heading used to group related fields.
    public let section: String?
    public let kind: ModuleConfigurationFieldKind
    public let defaultValue: ModuleConfigurationValue
    public let options: [ModuleConfigurationOption]
    /// Inclusive lower bound for numeric controls.
    public let minimumValue: Double?
    /// Inclusive upper bound for numeric controls.
    public let maximumValue: Double?
    /// Increment used by bounded numeric controls.
    public let step: Double?

    /// Creates a configuration field schema.
    public init(
        id: String,
        variable: String,
        title: String,
        description: String? = nil,
        placeholder: String? = nil,
        section: String? = nil,
        kind: ModuleConfigurationFieldKind,
        defaultValue: ModuleConfigurationValue,
        options: [ModuleConfigurationOption] = [],
        minimumValue: Double? = nil,
        maximumValue: Double? = nil,
        step: Double? = nil
    ) {
        self.id = id
        self.variable = variable
        self.title = title
        self.description = description
        self.placeholder = placeholder
        self.section = section
        self.kind = kind
        self.defaultValue = defaultValue
        self.options = options
        self.minimumValue = minimumValue
        self.maximumValue = maximumValue
        self.step = step
    }
}

/// A module's typed configuration contribution.
public struct ModuleSettingsContribution: Sendable, Equatable {
    /// Version of the persisted configuration shape.
    public let schemaVersion: Int
    /// Fields rendered by the shared Settings shell.
    public let fields: [ModuleConfigurationField]

    /// Creates a settings contribution.
    public init(schemaVersion: Int = 1, fields: [ModuleConfigurationField]) {
        self.schemaVersion = schemaVersion
        self.fields = fields
    }
}

// MARK: - Documentation

/// A reference from authored documentation to something the module declares.
public enum ModuleDocumentationReference: Sendable, Hashable, Codable {
    /// A command the module owns.
    case command(CommandID)
    /// A configuration field variable the module owns.
    case setting(variable: String)
    /// A capability the module requires.
    case capability(identifier: String)
}

/// One authored documentation article owned by a module.
public struct ModuleDocumentationArticle: Sendable, Equatable, Identifiable {
    public let id: String
    public let title: String
    public let summary: String
    /// Declared things this article documents. Validated by the host against the module's manifest.
    public let references: [ModuleDocumentationReference]

    /// Creates a documentation article descriptor.
    public init(
        id: String,
        title: String,
        summary: String,
        references: [ModuleDocumentationReference] = []
    ) {
        self.id = id
        self.title = title
        self.summary = summary
        self.references = references
    }
}

/// A module's documentation contribution.
///
/// Documentation stays discoverable for disabled and unavailable modules, so gathering it must not
/// activate services.
public struct ModuleDocumentationContribution: Sendable, Equatable {
    public let articles: [ModuleDocumentationArticle]

    /// Creates a documentation contribution.
    public init(articles: [ModuleDocumentationArticle]) {
        self.articles = articles
    }
}

// MARK: - Lifecycle

/// Whether a module will allow itself to be deactivated.
public enum ModuleDeactivationDecision: Sendable, Equatable {
    /// The module may be deactivated now.
    case allow
    /// Deactivation must not proceed; the module keeps its previous enabled state.
    case block(reason: String)
}

/// Retained behavior owned by an activated module.
///
/// Implementations own their tasks, observers, timers, monitors, leases, windows, and temporary
/// files, and release all of them in ``deactivate()``. Repeated activate/deactivate cycles must not
/// duplicate monitors or leak resources.
@MainActor
public protocol ModuleLifecycle: AnyObject, Sendable {
    /// Starts retained behavior. Called at most once per activation.
    func activate() async throws
    /// Asks whether deactivation may proceed, for example when unsaved work exists.
    func prepareForDeactivation() async -> ModuleDeactivationDecision
    /// Releases everything the module owns. Must be safe to call after a blocked attempt.
    func deactivate() async
}

public extension ModuleLifecycle {
    /// Modules without unsaved work allow deactivation by default.
    func prepareForDeactivation() async -> ModuleDeactivationDecision { .allow }
}

// MARK: - Availability

/// Observable availability of a module, beyond simple enablement.
public enum ModuleAvailability: Sendable, Equatable {
    /// Enabled and ready.
    case available
    /// Turned off by the user or by an inherited group setting.
    case disabled
    /// A declared permission has not been granted.
    case permissionRequired(identifier: String)
    /// A declared account connection is not connected.
    case disconnected(identifier: String)
    /// Not supported on this system.
    case unsupported(reason: String)
    /// Temporarily busy with exclusive work, such as an active recording.
    case busy(reason: String)
    /// Present but only usable through native interaction.
    case interactiveOnly
    /// Activation failed. The shell stays usable; only this module is affected.
    case failed(reason: String)

    /// Whether the module's commands may currently be dispatched.
    public var isAvailable: Bool {
        if case .available = self { return true }
        return false
    }

    /// Projection onto the shared command-availability reason, for the existing executor gate.
    public var unavailableReason: CommandUnavailableReason? {
        switch self {
        case .available:
            return nil
        case .disabled:
            return .disabled
        case .permissionRequired(let identifier):
            return .missingPermission(identifier: identifier)
        case .disconnected(let identifier):
            return .missingDependency(identifier: identifier)
        case .unsupported:
            return .unsupported
        case .busy:
            return .temporarilyUnavailable
        case .interactiveOnly:
            return .invalidContext
        case .failed:
            return .temporarilyUnavailable
        }
    }
}

// MARK: - Assembly

/// Services and handlers produced when a module is activated.
@MainActor
public struct ModuleActivation: Sendable {
    /// Operation handlers keyed by the commands they implement.
    public let handlers: [CommandID: any ModuleCommandHandling]
    /// Retained behavior, when the module has any.
    public let lifecycle: (any ModuleLifecycle)?

    /// Creates an activation result.
    public init(
        handlers: [CommandID: any ModuleCommandHandling],
        lifecycle: (any ModuleLifecycle)? = nil
    ) {
        self.handlers = handlers
        self.lifecycle = lifecycle
    }
}

/// A module's narrow assembly interface.
///
/// An assembly receives only the interfaces its module needs, through its own initializer. It is
/// never handed a general-purpose service container.
///
/// Everything outside ``activate()`` is metadata and must be free of side effects: no service
/// construction, no permission prompts, no account connections, no indexing, no private data.
@MainActor
public protocol ModuleAssembly: Sendable {
    /// Static module metadata.
    var manifest: ModuleManifest { get }
    /// Canonical definitions for every command the module owns.
    var commandDefinitions: [ModuleCommandDefinition] { get }
    /// Typed configuration schema, when the module has preferences.
    var settings: ModuleSettingsContribution? { get }
    /// Authored documentation, when the module has any.
    var documentation: ModuleDocumentationContribution? { get }

    /// Constructs the module's services and operation handlers.
    ///
    /// Called at most once per module lifetime by the host, including under concurrent requests.
    func activate() async throws -> ModuleActivation
}

public extension ModuleAssembly {
    var settings: ModuleSettingsContribution? { nil }
    var documentation: ModuleDocumentationContribution? { nil }
}
