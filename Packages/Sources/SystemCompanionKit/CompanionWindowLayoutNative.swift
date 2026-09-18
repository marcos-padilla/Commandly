import AppKit
import ApplicationServices
import Foundation
import Dispatch
import Infrastructure

/// Native worker contract; test implementations never touch AX or user windows.
public protocol CompanionWindowLayoutWorking: Sendable {
    func capture(context: CompanionWindowLayoutContext, handle: CompanionTargetHandle, expires: ContinuousClock.Instant) async throws
    func apply(context: CompanionWindowLayoutContext, handle: CompanionTargetHandle, rect: CompanionNormalizedWindowRect, deadline: ContinuousClock.Instant) async throws -> CompanionWindowLayoutReceipt
    func clear() async
}

/// Main-actor process/display inspection returns value snapshots only. No AX API belongs here.
@MainActor public protocol CompanionWindowLayoutEnvironment: AnyObject, Sendable {
    func validate(_ context: CompanionWindowLayoutContext) async throws -> [CompanionLayoutDisplay]
}

/// Serial worker owns every AX reference. Synchronous AX calls run on this actor, never the main actor,
/// and each native messaging timeout is at most 200 ms. No observer, title read, or background AX capture exists.
public actor NativeCompanionWindowLayoutWorker: CompanionWindowLayoutWorking, CompanionWindowLayoutMutationPort {
    nonisolated private let queue = DispatchSerialQueue(label: "com.commandly.companion.window-layouts", qos: .userInitiated)
    nonisolated public var unownedExecutor: UnownedSerialExecutor { queue.asUnownedSerialExecutor() }
    private struct Target {
        let handle: CompanionTargetHandle
        let context: CompanionWindowLayoutContext
        let application: AXUIElement
        let window: AXUIElement
        let displays: [CompanionLayoutDisplay]
        let display: CompanionLayoutDisplay
        let expires: ContinuousClock.Instant
    }
    private struct Mutation {
        let id: UUID
        let target: Target
        let frame: CGRect
        let deadline: ContinuousClock.Instant
    }
    private var mutation: Mutation?
    private let lease: CompanionWindowLayoutLease
    private let environment: any CompanionWindowLayoutEnvironment
    private var target: Target?
    public init(lease: CompanionWindowLayoutLease, environment: any CompanionWindowLayoutEnvironment) {
        self.lease = lease; self.environment = environment
    }
    public func clear() { target = nil }
    public func capture(context: CompanionWindowLayoutContext, handle: CompanionTargetHandle, expires: ContinuousClock.Instant) async throws {
        target = nil
        let displays = try await environment.validate(context)
        try validate(context, deadline: expires)
        guard handle.session == context.session else { throw CompanionWindowLayoutError.staleTarget }
        let application = AXUIElementCreateApplication(context.application.processIdentifier)
        try messagingTimeout(application, deadline: expires)
        let window = try focusedWindow(application)
        try messagingTimeout(window, deadline: expires)
        try validateWindow(window, context: context)
        let frame = try readFrame(window)
        let display = try CompanionWindowLayoutGeometry.display(for: frame, among: displays)
        try validate(context, deadline: expires)
        target = Target(handle: handle, context: context, application: application, window: window, displays: displays, display: display, expires: expires)
    }
    public func apply(context: CompanionWindowLayoutContext, handle: CompanionTargetHandle, rect: CompanionNormalizedWindowRect, deadline: ContinuousClock.Instant) async throws -> CompanionWindowLayoutReceipt {
        guard rect.isValid else { throw CompanionWindowLayoutError.invalidGeometry }
        guard let captured = target, captured.handle == handle, captured.context == context else { throw CompanionWindowLayoutError.staleTarget }
        // Consume before the first suspension. Concurrent/replayed Apply cannot reuse a native target.
        target = nil
        let expires = min(deadline, captured.expires)
        try await revalidate(captured, deadline: expires)
        let frame = try CompanionWindowLayoutGeometry.target(rect, in: captured.display)
        let id = UUID()
        mutation = Mutation(id: id, target: captured, frame: frame, deadline: expires)
        defer { if mutation?.id == id { mutation = nil } }
        return try await CompanionWindowLayoutMutation.run(id: id, port: self)
    }
    public func validateMutation(_ id: UUID) async throws {
        let value = try requireMutation(id)
        try await revalidate(value.target, deadline: value.deadline)
    }
    public func resizeMutation(_ id: UUID) throws -> CompanionWindowMutationState {
        let value = try requireMutation(id)
        try messagingTimeout(value.target.window, deadline: value.deadline)
        try validate(value.target.context, deadline: value.deadline)
        var size = value.frame.size
        guard let native = AXValueCreate(.cgSize, &size) else { throw CompanionWindowLayoutError.unavailable }
        return Self.writeState(AXUIElementSetAttributeValue(value.target.window, kAXSizeAttribute as CFString, native))
    }
    public func positionMutation(_ id: UUID) throws -> CompanionWindowMutationState {
        let value = try requireMutation(id)
        try messagingTimeout(value.target.window, deadline: value.deadline)
        try validate(value.target.context, deadline: value.deadline)
        var origin = value.frame.origin
        guard let native = AXValueCreate(.cgPoint, &origin) else { throw CompanionWindowLayoutError.unavailable }
        return Self.writeState(AXUIElementSetAttributeValue(value.target.window, kAXPositionAttribute as CFString, native))
    }
    public func readbackMutation(_ id: UUID) async throws -> Bool {
        let value = try requireMutation(id)
        try await revalidate(value.target, deadline: value.deadline)
        return try CompanionWindowLayoutGeometry.matches(readFrame(value.target.window), value.frame)
    }
    private func requireMutation(_ id: UUID) throws -> Mutation {
        guard let mutation, mutation.id == id else { throw CompanionWindowLayoutError.staleTarget }
        return mutation
    }
    nonisolated static func writeState(_ result: AXError) -> CompanionWindowMutationState {
        switch result {
        case .success: return .accepted
        case .attributeUnsupported, .illegalArgument, .notImplemented: return .refused
        default: return .unknown
        }
    }
    private func revalidate(_ value: Target, deadline: ContinuousClock.Instant) async throws {
        let displays = try await environment.validate(value.context)
        guard displays == value.displays else { throw CompanionWindowLayoutError.displayChanged }
        try validate(value.context, deadline: deadline)
        try messagingTimeout(value.application, deadline: deadline)
        try messagingTimeout(value.window, deadline: deadline)
        guard CFEqual(try focusedWindow(value.application), value.window) else { throw CompanionWindowLayoutError.staleTarget }
        try validateWindow(value.window, context: value.context)
        _ = try readFrame(value.window)
        try validate(value.context, deadline: deadline)
    }
    private func validate(_ context: CompanionWindowLayoutContext, deadline: ContinuousClock.Instant) throws {
        guard Task.isCancelled == false else { throw CompanionWindowLayoutError.canceled }
        guard ContinuousClock().now < deadline else { throw CompanionWindowLayoutError.expiredTarget }
        try lease.validate(context)
        // Read-only trust check. AXIsProcessTrustedWithOptions (prompting) is deliberately absent.
        guard AXIsProcessTrusted() else { lease.disconnect(); throw CompanionWindowLayoutError.permissionDenied }
    }
    private func messagingTimeout(_ element: AXUIElement, deadline: ContinuousClock.Instant) throws {
        let remaining = ContinuousClock().now.duration(to: deadline).components
        let seconds = Double(remaining.seconds) + Double(remaining.attoseconds) / 1e18
        guard seconds > 0 else { throw CompanionWindowLayoutError.expiredTarget }
        guard AXUIElementSetMessagingTimeout(element, Float(min(seconds, 0.2))) == .success else { throw CompanionWindowLayoutError.unavailable }
    }
    private func focusedWindow(_ application: AXUIElement) throws -> AXUIElement {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(application, kAXFocusedWindowAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { throw CompanionWindowLayoutError.noFocusedWindow }
        return unsafeDowncast(value, to: AXUIElement.self)
    }
    private func validateWindow(_ window: AXUIElement, context: CompanionWindowLayoutContext) throws {
        var pid: pid_t = 0
        guard AXUIElementGetPid(window, &pid) == .success, pid == context.application.processIdentifier else { throw CompanionWindowLayoutError.staleTarget }
        var role: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXRoleAttribute as CFString, &role) == .success,
              let role, CFEqual(role, kAXWindowRole as CFString) else { throw CompanionWindowLayoutError.unsupportedWindow }
        for name in [kAXPositionAttribute, kAXSizeAttribute] {
            var settable = DarwinBoolean(false)
            guard AXUIElementIsAttributeSettable(window, name as CFString, &settable) == .success, settable.boolValue else {
                throw CompanionWindowLayoutError.unsupportedWindow
            }
        }
        var minimized: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &minimized)
        guard result == .success, let minimized, CFGetTypeID(minimized) == CFBooleanGetTypeID(),
              CFEqual(minimized, kCFBooleanFalse) else { throw CompanionWindowLayoutError.unsupportedWindow }
    }
    private func readFrame(_ window: AXUIElement) throws -> CGRect {
        var originValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &originValue) == .success,
              AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeValue) == .success,
              let originValue, let sizeValue,
              CFGetTypeID(originValue) == AXValueGetTypeID(), CFGetTypeID(sizeValue) == AXValueGetTypeID() else {
            throw CompanionWindowLayoutError.unsupportedWindow
        }
        var origin = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(unsafeDowncast(originValue, to: AXValue.self), .cgPoint, &origin),
              AXValueGetValue(unsafeDowncast(sizeValue, to: AXValue.self), .cgSize, &size) else { throw CompanionWindowLayoutError.unsupportedWindow }
        let frame = CGRect(origin: origin, size: size)
        guard CompanionWindowLayoutGeometry.validFrame(frame) else { throw CompanionWindowLayoutError.unsupportedWindow }
        return frame
    }
}
