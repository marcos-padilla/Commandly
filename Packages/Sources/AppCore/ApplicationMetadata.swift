/// Immutable metadata describing the running application build.
public struct ApplicationMetadata: Sendable, Equatable {
    /// Display name shown to users.
    public let name: String
    /// Marketing version string (for example, `1.0.0`).
    public let version: String
    /// Build number string.
    public let build: String
    /// Bundle identifier.
    public let bundleIdentifier: String
    /// Runtime environment.
    public let environment: ApplicationEnvironment

    /// Creates application metadata.
    public init(
        name: String,
        version: String,
        build: String,
        bundleIdentifier: String,
        environment: ApplicationEnvironment
    ) {
        self.name = name
        self.version = version
        self.build = build
        self.bundleIdentifier = bundleIdentifier
        self.environment = environment
    }
}
