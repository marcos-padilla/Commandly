import Foundation

/// Injectable bytes boundary. Implementations must bound messages and cancel pending work on invalidation.
public protocol CompanionTransport: Sendable {
    func exchange(_ request: Data) async throws -> Data
    func isConnected() async -> Bool
    func invalidate() async
}
/// Objective-C XPC exposes one bounded-data method; decoded values never select arbitrary selectors.
@objc public protocol CompanionXPCProtocol {
    func exchange(_ request: Data, withReply reply: @escaping @Sendable (Data) -> Void)
}
