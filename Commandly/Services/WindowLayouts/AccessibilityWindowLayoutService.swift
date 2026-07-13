import AppKit
import ApplicationServices
import Foundation
import SecurityKit

enum WindowLayoutServiceError: Error, Equatable {
    case permissionDenied
    case noFrontmostApplication
    case noFocusedWindow
    case unsupportedWindow
    case operationFailed

    var message: String {
        switch self {
        case .permissionDenied:
            return "Accessibility access is required. You can grant it in Commandly Settings."
        case .noFrontmostApplication:
            return "No regular application is active."
        case .noFocusedWindow:
            return "The active application has no focused window."
        case .unsupportedWindow:
            return "That window does not support resizing."
        case .operationFailed:
            return "macOS could not apply that layout."
        }
    }
}

@MainActor
protocol WindowLayoutApplying: AnyObject {
    func apply(rect: NormalizedWindowRect) async throws
}

/// Remembers the application that was active before Commandly raised its launcher.
///
/// Opening Commandly makes it the frontmost process. Window actions must still target the external
/// application the user was working in, while allowing a newly activated external app to replace
/// that captured target.
@MainActor
final class WindowLayoutTargetTracker {
    typealias ProcessIdentifierProvider = @MainActor () -> pid_t?

    private let commandlyProcessIdentifier: pid_t
    private let frontmostProcessIdentifier: ProcessIdentifierProvider
    private(set) var lastExternalProcessIdentifier: pid_t?

    init(
        commandlyProcessIdentifier: pid_t = ProcessInfo.processInfo.processIdentifier,
        frontmostProcessIdentifier: @escaping ProcessIdentifierProvider = {
            NSWorkspace.shared.frontmostApplication?.processIdentifier
        }
    ) {
        self.commandlyProcessIdentifier = commandlyProcessIdentifier
        self.frontmostProcessIdentifier = frontmostProcessIdentifier
        captureFrontmostApplication()
    }

    func captureFrontmostApplication() {
        guard let processIdentifier = frontmostProcessIdentifier(),
              processIdentifier != commandlyProcessIdentifier else {
            return
        }
        lastExternalProcessIdentifier = processIdentifier
    }

    func targetProcessIdentifier() -> pid_t? {
        captureFrontmostApplication()
        return lastExternalProcessIdentifier
    }
}

@MainActor
final class InMemoryWindowLayoutService: WindowLayoutApplying {
    private(set) var applied: [NormalizedWindowRect] = []
    var error: WindowLayoutServiceError?

    func apply(rect: NormalizedWindowRect) async throws {
        if let error { throw error }
        applied.append(rect)
    }
}

@MainActor
final class AccessibilityWindowLayoutService: WindowLayoutApplying {
    private let permissionService: any PermissionServicing
    private let targetTracker: WindowLayoutTargetTracker

    init(
        permissionService: any PermissionServicing,
        targetTracker: WindowLayoutTargetTracker = WindowLayoutTargetTracker()
    ) {
        self.permissionService = permissionService
        self.targetTracker = targetTracker
    }

    func captureTargetApplication() {
        targetTracker.captureFrontmostApplication()
    }

    func apply(rect: NormalizedWindowRect) async throws {
        guard rect.isValid else { throw WindowLayoutServiceError.operationFailed }
        var state = await permissionService.state(for: .accessibility)
        if state != .authorized {
            state = await permissionService.request(.accessibility)
        }
        guard state == .authorized else { throw WindowLayoutServiceError.permissionDenied }
        guard let processIdentifier = targetTracker.targetProcessIdentifier(),
              let application = NSRunningApplication(processIdentifier: processIdentifier),
              application.isTerminated == false else {
            throw WindowLayoutServiceError.noFrontmostApplication
        }

        let applicationElement = AXUIElementCreateApplication(application.processIdentifier)
        var windowValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            applicationElement,
            kAXFocusedWindowAttribute as CFString,
            &windowValue
        ) == .success,
        let windowValue,
        CFGetTypeID(windowValue) == AXUIElementGetTypeID() else {
            throw WindowLayoutServiceError.noFocusedWindow
        }
        let window = unsafeDowncast(windowValue, to: AXUIElement.self)
        guard isSettable(kAXPositionAttribute, on: window),
              isSettable(kAXSizeAttribute, on: window) else {
            throw WindowLayoutServiceError.unsupportedWindow
        }

        let screen = screenContaining(window: window) ?? NSScreen.main ?? NSScreen.screens.first
        guard let screen else { throw WindowLayoutServiceError.operationFailed }
        let target = Self.appKitFrame(for: rect, visibleFrame: screen.visibleFrame)
        var position = CGPoint(x: target.minX, y: axY(for: target))
        var size = CGSize(width: target.width, height: target.height)
        guard let positionValue = AXValueCreate(.cgPoint, &position),
              let sizeValue = AXValueCreate(.cgSize, &size),
              AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue) == .success,
              AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, positionValue) == .success else {
            throw WindowLayoutServiceError.operationFailed
        }
    }

    nonisolated static func appKitFrame(
        for rect: NormalizedWindowRect,
        visibleFrame: CGRect
    ) -> CGRect {
        CGRect(
            x: visibleFrame.minX + rect.x * visibleFrame.width,
            y: visibleFrame.maxY - (rect.y + rect.height) * visibleFrame.height,
            width: rect.width * visibleFrame.width,
            height: rect.height * visibleFrame.height
        ).integral
    }

    private func isSettable(_ attribute: String, on element: AXUIElement) -> Bool {
        var settable = DarwinBoolean(false)
        return AXUIElementIsAttributeSettable(element, attribute as CFString, &settable) == .success
            && settable.boolValue
    }

    private func screenContaining(window: AXUIElement) -> NSScreen? {
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            window,
            kAXPositionAttribute as CFString,
            &positionValue
        ) == .success,
        AXUIElementCopyAttributeValue(
            window,
            kAXSizeAttribute as CFString,
            &sizeValue
        ) == .success,
        let positionValue,
        let sizeValue,
        CFGetTypeID(positionValue) == AXValueGetTypeID(),
        CFGetTypeID(sizeValue) == AXValueGetTypeID() else {
            return nil
        }
        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(unsafeDowncast(positionValue, to: AXValue.self), .cgPoint, &position),
              AXValueGetValue(unsafeDowncast(sizeValue, to: AXValue.self), .cgSize, &size) else {
            return nil
        }
        let mainHeight = NSScreen.screens.first(where: { $0.frame.origin == .zero })?.frame.height
            ?? NSScreen.main?.frame.height ?? 0
        let appKitFrame = CGRect(
            x: position.x,
            y: mainHeight - position.y - size.height,
            width: size.width,
            height: size.height
        )
        return NSScreen.screens.max { left, right in
            left.frame.intersection(appKitFrame).area < right.frame.intersection(appKitFrame).area
        }
    }

    private func axY(for appKitFrame: CGRect) -> CGFloat {
        let mainHeight = NSScreen.screens.first(where: { $0.frame.origin == .zero })?.frame.height
            ?? NSScreen.main?.frame.height ?? 0
        return mainHeight - appKitFrame.maxY
    }
}

private extension CGRect {
    var area: CGFloat { isNull ? 0 : width * height }
}
