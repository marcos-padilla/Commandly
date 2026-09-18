import Foundation

/// Hard wire and session limits shared by both peers; future features may not silently relax them.
public enum CompanionLimits {
    public static let protocolVersion = 1
    public static let requestBytes = 256 * 1024
    public static let replyBytes = 512 * 1024
    public static let textBytes = 64 * 1024
    public static let inFlightRequests = 8
    public static let windows = 200
    public static let menuEntries = 500
    public static let timeoutMilliseconds = 5_000
    public static let sessionSeconds = 300
}
/// Every operation is explicit. Future action cases are schema only and currently return unsupportedOperation.
public enum CompanionOperation: String, Codable, Sendable {
    case handshake, status, openSession, closeSession, cancel
    case keyboardTriggerAction
    case appMenuAction, windowLayoutAction, windowAction, menuAction, selectionAction, triggerAction, lifecycleAction
}
/// A canonical, bounded request. Session handles and sequence values are connection-scoped, never OS identifiers.
public struct CompanionRequest: Codable, Equatable, Sendable {
    public let version: Int
    public let id: UUID
    public let sequence: UInt64
    public let build: String
    public let session: UUID?
    public let operation: CompanionOperation
    public let timeoutMilliseconds: Int
    public let cancelRequestID: UUID?
    public let action: CompanionAction?
    public init(version: Int = CompanionLimits.protocolVersion, id: UUID = UUID(), sequence: UInt64,
                build: String, session: UUID? = nil, operation: CompanionOperation,
                timeoutMilliseconds: Int = CompanionLimits.timeoutMilliseconds,
                cancelRequestID: UUID? = nil, action: CompanionAction? = nil) {
        self.version = version; self.id = id; self.sequence = sequence; self.build = build; self.session = session
        self.operation = operation; self.timeoutMilliseconds = timeoutMilliseconds; self.cancelRequestID = cancelRequestID; self.action = action
    }
}
/// Only this result enum crosses the channel. Native object references and arbitrary error strings never do.
public enum CompanionReplyValue: Codable, Equatable, Sendable {
    case status(CompanionStatus)
    case session(UUID)
    case keyboardTrigger(CompanionKeyboardTriggerReply)
    case appMenu(CompanionAppMenuReply)
    case windowLayout(CompanionWindowLayoutReply)
    case acknowledged
    case failure(CompanionError)
}
/// Replies bind to the request identity and negotiated protocol.
public struct CompanionReply: Codable, Equatable, Sendable {
    public let version: Int
    public let requestID: UUID
    public let value: CompanionReplyValue
    public init(version: Int = CompanionLimits.protocolVersion, requestID: UUID, value: CompanionReplyValue) {
        self.version = version; self.requestID = requestID; self.value = value
    }
}
