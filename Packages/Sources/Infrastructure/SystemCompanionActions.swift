import Foundation

/// An expiring native target handle created by the companion, never a caller-supplied PID or AX path.
public struct CompanionTargetHandle: Codable, Hashable, Sendable {
    public let session: UUID
    public let target: UUID
    public init(session: UUID, target: UUID) { self.session = session; self.target = target }
}
/// Reviewed window layouts are finite presets, not arbitrary AX attributes or code.
public enum CompanionWindowAction: String, Codable, Sendable { case activate, minimize, close, leftHalf, rightHalf, maximize, center }
/// A future window operation. The current helper rejects it before accessing any other application.
public struct CompanionWindowRequest: Codable, Equatable, Sendable {
    public let handle: CompanionTargetHandle
    public let action: CompanionWindowAction
    public init(handle: CompanionTargetHandle, action: CompanionWindowAction) { self.handle = handle; self.action = action }
}
/// A reviewed enabled menu entry will be represented by one opaque, session-bound handle.
public struct CompanionMenuRequest: Codable, Equatable, Sendable {
    public let handle: CompanionTargetHandle
    public init(handle: CompanionTargetHandle) { self.handle = handle }
}
/// A future selected-text request must bind reviewed output to an unchanged native selection revision.
public enum CompanionSelectionRequest: Codable, Equatable, Sendable {
    case readCurrent
    case replace(handle: CompanionTargetHandle, revision: UUID, reviewedText: String)
}
/// Configured trigger patterns exclude raw key-event streams and arbitrary executable paths.
public enum CompanionTriggerPattern: String, Codable, Sendable { case hyper, singleTap, doubleTap, snippet }
/// A future trigger binding refers to an already-reviewed command by a bounded opaque identifier.
public enum CompanionTriggerRequest: Codable, Equatable, Sendable {
    case stopAll
    case configure(bindingID: UUID, pattern: CompanionTriggerPattern, commandID: String)
}
/// Graceful versus force quit are separate reviewed actions; no implicit escalation is represented.
public enum CompanionLifecycleAction: String, Codable, Sendable { case gracefulQuit, forceQuit }
/// A future application lifecycle operation requires a session-scoped target.
public struct CompanionLifecycleRequest: Codable, Equatable, Sendable {
    public let handle: CompanionTargetHandle
    public let action: CompanionLifecycleAction
    public init(handle: CompanionTargetHandle, action: CompanionLifecycleAction) { self.handle = handle; self.action = action }
}
/// Explicit schema for later slices. This enum grants no native authority in the foundation.
public enum CompanionAction: Codable, Equatable, Sendable {
    case window(CompanionWindowRequest)
    case keyboardTrigger(CompanionKeyboardTriggerRequest)
    case appMenu(CompanionAppMenuRequest)
    case windowLayout(CompanionWindowLayoutRequest)
    case menu(CompanionMenuRequest)
    case selection(CompanionSelectionRequest)
    case trigger(CompanionTriggerRequest)
    case lifecycle(CompanionLifecycleRequest)
}
