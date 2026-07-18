import Foundation

/// A non-sensitive snapshot of the application that was frontmost at invocation time.
public struct FrontmostApplicationContext: Codable, Equatable, Hashable, Sendable {
    public let processIdentifier: Int32
    public let bundleIdentifier: String?
    public let localizedName: String?

    public init(
        processIdentifier: Int32,
        bundleIdentifier: String?,
        localizedName: String?
    ) {
        self.processIdentifier = processIdentifier
        self.bundleIdentifier = bundleIdentifier
        self.localizedName = localizedName
    }
}

/// Captures frontmost-application context once before an overlay changes focus.
@MainActor
public protocol FrontmostApplicationContextProviding: Sendable {
    func snapshot() -> FrontmostApplicationContext?
}

/// Deterministic context provider for tests and previews.
@MainActor
public final class InMemoryFrontmostApplicationContextProvider:
    FrontmostApplicationContextProviding
{
    public var context: FrontmostApplicationContext?

    public init(context: FrontmostApplicationContext? = nil) {
        self.context = context
    }

    public func snapshot() -> FrontmostApplicationContext? {
        context
    }
}
