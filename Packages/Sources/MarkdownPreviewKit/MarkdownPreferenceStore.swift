import Foundation

/// Errors produced while saving shared Markdown Preview preferences.
public enum MarkdownPreferenceStoreError: Error, Equatable, Sendable {
    /// The requested shared defaults suite could not be opened.
    case unavailableSuite(String)
    /// A sanitized configuration could not be encoded.
    case encodingFailed
}

/// Persists one version-tolerant, non-secret configuration in a shared defaults suite.
///
/// The type stores only identifiers, so it can safely cross concurrency domains. Each operation
/// obtains its own `UserDefaults` handle; Foundation provides synchronization between processes.
public struct MarkdownPreferenceStore: Sendable {
    /// App group shared by the Commandly host and extensions.
    public static let defaultAppGroupIdentifier = "group.com.businessmate360.Commandly"
    /// Versioned configuration key within the shared defaults suite.
    public static let defaultKey = "markdownPreview.configuration.v1"

    /// Defaults suite used by this store.
    public let suiteName: String
    /// Key used by this store.
    public let key: String

    /// Creates a preference store identified entirely by Sendable strings.
    public init(
        suiteName: String = Self.defaultAppGroupIdentifier,
        key: String = Self.defaultKey
    ) {
        self.suiteName = suiteName
        self.key = key
    }

    /// Loads a sanitized configuration, returning defaults for missing or corrupt data.
    public func load() -> MarkdownPreviewConfiguration {
        guard let defaults = UserDefaults(suiteName: suiteName),
              let data = defaults.data(forKey: key),
              let configuration = try? JSONDecoder().decode(MarkdownPreviewConfiguration.self, from: data) else {
            return .default
        }
        return configuration.sanitized()
    }

    /// Saves a sanitized configuration to the shared suite.
    public func save(_ configuration: MarkdownPreviewConfiguration) throws {
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            throw MarkdownPreferenceStoreError.unavailableSuite(suiteName)
        }
        guard let data = try? JSONEncoder().encode(configuration.sanitized()) else {
            throw MarkdownPreferenceStoreError.encodingFailed
        }
        defaults.set(data, forKey: key)
    }

    /// Removes the stored override so future loads use defaults.
    public func reset() {
        UserDefaults(suiteName: suiteName)?.removeObject(forKey: key)
    }
}
