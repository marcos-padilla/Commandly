import Foundation

/// Experimental: unique identifier for an extension.
///
/// - Warning: Extension APIs are experimental and must not load external code yet.
public struct ExtensionID: Hashable, Sendable, Codable, RawRepresentable {
    public let rawValue: String

    /// Creates an extension identifier.
    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

/// Experimental: semantic version for an extension manifest.
public struct ExtensionVersion: Sendable, Equatable, Codable, Comparable {
    public let major: Int
    public let minor: Int
    public let patch: Int

    /// Creates an extension version.
    public init(major: Int, minor: Int, patch: Int) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    public static func < (lhs: ExtensionVersion, rhs: ExtensionVersion) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        return lhs.patch < rhs.patch
    }
}

/// Experimental: permissions an extension may declare.
public enum ExtensionPermission: String, Sendable, Codable, CaseIterable {
    case network
    case filesystemRead
    case clipboardRead
    case notifications
}

/// Experimental: declarative extension metadata. Does not load or execute code.
public struct ExtensionManifest: Sendable, Equatable {
    public let id: ExtensionID
    public let name: String
    public let version: ExtensionVersion
    public let permissions: [ExtensionPermission]
    public let minimumAppVersion: String

    /// Creates an extension manifest.
    public init(
        id: ExtensionID,
        name: String,
        version: ExtensionVersion,
        permissions: [ExtensionPermission] = [],
        minimumAppVersion: String
    ) {
        self.id = id
        self.name = name
        self.version = version
        self.permissions = permissions
        self.minimumAppVersion = minimumAppVersion
    }
}

/// Experimental: result of validating an extension manifest.
public enum ExtensionValidationResult: Sendable, Equatable {
    case valid
    case invalid(reasons: [String])
}

/// Experimental: validates extension manifests without loading code.
public enum ExtensionManifestValidator {
    /// Validates structural requirements of a manifest.
    public static func validate(_ manifest: ExtensionManifest) -> ExtensionValidationResult {
        var reasons: [String] = []

        if manifest.id.rawValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            reasons.append("Extension ID must not be empty.")
        }
        if manifest.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            reasons.append("Extension name must not be empty.")
        }
        if manifest.version.major < 0 || manifest.version.minor < 0 || manifest.version.patch < 0 {
            reasons.append("Extension version components must be non-negative.")
        }
        if manifest.minimumAppVersion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            reasons.append("Minimum app version must not be empty.")
        }

        if reasons.isEmpty {
            return .valid
        }
        return .invalid(reasons: reasons)
    }
}
