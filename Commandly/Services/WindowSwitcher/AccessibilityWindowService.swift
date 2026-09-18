import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
import Infrastructure

/// Public-API window discovery and control for the Window Switcher.
///
/// Accessibility calls are isolated to this actor because they can cross process boundaries. The
/// service retains AX elements only for the current in-memory discovery snapshot; titles, frames,
/// and element references are never persisted or logged.
actor AccessibilityWindowService: WindowQuerying, WindowControlling, WindowSessionReleasing {
    private enum NativeActionError: Error {
        case unavailable
        case unsupported
        case failed
    }

    struct ApplicationIdentity: Sendable, Equatable {
        let processIdentifier: Int32
        let bundleIdentifier: String?
        let launchDate: Date?

        var canVerifyProcessLifetime: Bool { launchDate != nil }
    }

    private struct RunningApplicationRecord: Sendable {
        let processIdentifier: Int32
        let bundleIdentifier: String?
        let localizedName: String
        let isHidden: Bool
        let launchDate: Date?

        var identity: ApplicationIdentity {
            ApplicationIdentity(
                processIdentifier: processIdentifier,
                bundleIdentifier: bundleIdentifier,
                launchDate: launchDate
            )
        }
    }

    private struct DisplayRecord: Sendable {
        let frame: CGRect
        let visibleFrame: CGRect
        let primaryHeight: CGFloat

        func appKitFrame(fromAccessibilityFrame frame: CGRect) -> CGRect {
            CGRect(
                x: frame.minX,
                y: primaryHeight - frame.maxY,
                width: frame.width,
                height: frame.height
            )
        }

        func accessibilityOrigin(fromAppKitFrame frame: CGRect) -> CGPoint {
            CGPoint(x: frame.minX, y: primaryHeight - frame.maxY)
        }
    }

    private struct OnScreenWindowRecord: Sendable {
        let windowID: UInt32
        let processIdentifier: Int32
        let title: String?
        let frame: CGRect
    }

    private var elementsByID: [WindowID: AXUIElement] = [:]
    private var windowlessIDs: Set<WindowID> = []
    private var applicationIdentityByID: [WindowID: ApplicationIdentity] = [:]
    private var discoveryGeneration: UInt64 = 0

    func windows(options: WindowQueryOptions) async throws -> [WindowSnapshot] {
        try Task.checkCancellation()
        guard AXIsProcessTrusted() else {
            clearCachedSnapshot()
            throw WindowServiceError.queryUnavailable
        }

        clearCachedSnapshot()
        discoveryGeneration &+= 1
        let sessionGeneration = discoveryGeneration

        let applications = await runningApplications()
        let displays = await displayRecords()
        let primaryHeight = displays.first?.primaryHeight ?? 0
        let onScreenWindows = Self.onScreenWindowRecords(primaryHeight: primaryHeight)
        var nextElementsByID: [WindowID: AXUIElement] = [:]
        var nextWindowlessIDs: Set<WindowID> = []
        var nextApplicationIdentityByID: [WindowID: ApplicationIdentity] = [:]
        var snapshots: [WindowSnapshot] = []

        for application in applications {
            try Task.checkCancellation()
            if let bundleIdentifier = application.bundleIdentifier,
               options.excludedBundleIdentifiers.contains(bundleIdentifier) {
                continue
            }
            if application.isHidden, options.includeHidden == false {
                continue
            }

            let applicationElement = AXUIElementCreateApplication(application.processIdentifier)
            let windows = Self.elements(
                attribute: kAXWindowsAttribute,
                from: applicationElement
            )
            let hasConcreteWindows = windows.contains(where: Self.isStandardWindow)

            for (index, element) in windows.enumerated() {
                try Task.checkCancellation()
                guard Self.isStandardWindow(element) else { continue }
                let isMinimized = Self.bool(
                    attribute: kAXMinimizedAttribute,
                    from: element
                ) ?? false
                if isMinimized, options.includeMinimized == false { continue }

                let title = Self.string(attribute: kAXTitleAttribute, from: element) ?? "Untitled"
                if options.excludedTitleTerms.contains(where: {
                    title.localizedCaseInsensitiveContains($0)
                }) {
                    continue
                }
                guard let accessibilityFrame = Self.accessibilityFrame(of: element) else {
                    continue
                }
                let appKitFrame = displays.first?.appKitFrame(
                    fromAccessibilityFrame: accessibilityFrame
                ) ?? accessibilityFrame
                let onScreenRecord = Self.bestOnScreenMatch(
                    processIdentifier: application.processIdentifier,
                    title: title,
                    accessibilityFrame: accessibilityFrame,
                    records: onScreenWindows
                )
                // Public APIs do not expose Space membership for a minimized or app-hidden
                // window. Keep those explicitly requested states available and reserve a
                // definitive `false` for visible windows that are absent from the active desktop.
                let isOnCurrentDesktop = onScreenRecord != nil
                    || isMinimized
                    || application.isHidden
                if options.currentDesktopOnly, isOnCurrentDesktop == false { continue }
                if let currentDisplayFrame = options.currentDisplayFrame,
                   currentDisplayFrame.intersection(appKitFrame).area <= 0 {
                    continue
                }

                let identifier = Self.identifier(
                    sessionGeneration: sessionGeneration,
                    processIdentifier: application.processIdentifier,
                    index: index,
                    frame: accessibilityFrame
                )
                nextElementsByID[identifier] = element
                nextApplicationIdentityByID[identifier] = application.identity
                snapshots.append(
                    WindowSnapshot(
                        id: identifier,
                        processIdentifier: application.processIdentifier,
                        bundleIdentifier: application.bundleIdentifier,
                        applicationName: application.localizedName,
                        title: title,
                        frame: appKitFrame,
                        isMinimized: isMinimized,
                        isHidden: application.isHidden,
                        isOnCurrentDesktop: isOnCurrentDesktop,
                        isFocused: Self.bool(
                            attribute: kAXFocusedAttribute,
                            from: element
                        ) ?? false,
                        captureWindowID: onScreenRecord?.windowID,
                        isWindowless: false
                    )
                )
            }

            if Self.shouldIncludeWindowlessPlaceholder(
                hasConcreteWindows: hasConcreteWindows,
                options: options
            ) {
                let identifier = WindowID(
                    rawValue: "\(sessionGeneration):\(application.processIdentifier):windowless",
                    processIdentifier: application.processIdentifier
                )
                snapshots.append(
                    WindowSnapshot(
                        id: identifier,
                        processIdentifier: application.processIdentifier,
                        bundleIdentifier: application.bundleIdentifier,
                        applicationName: application.localizedName,
                        title: "No open windows",
                        frame: .zero,
                        isMinimized: false,
                        isHidden: application.isHidden,
                        isOnCurrentDesktop: false,
                        isFocused: false,
                        captureWindowID: nil,
                        isWindowless: true
                    )
                )
                nextWindowlessIDs.insert(identifier)
                nextApplicationIdentityByID[identifier] = application.identity
            }
        }

        elementsByID = nextElementsByID
        windowlessIDs = nextWindowlessIDs
        applicationIdentityByID = nextApplicationIdentityByID
        return snapshots
    }

    func releaseWindowSession(windowIDs: Set<WindowID>) async {
        for windowID in windowIDs {
            removeCachedTarget(windowID)
        }
    }

    func perform(_ action: WindowAction, on window: WindowID) async throws {
        try Task.checkCancellation()
        guard AXIsProcessTrusted() else {
            clearCachedSnapshot()
            throw WindowServiceError.actionFailed(action: action, windowID: window)
        }
        guard let expectedApplicationIdentity = applicationIdentityByID[window],
              expectedApplicationIdentity.canVerifyProcessLifetime else {
            throw WindowServiceError.windowNotFound(window)
        }
        let target = await resolveTarget(
            window,
            expectedApplicationIdentity: expectedApplicationIdentity
        )
        try Task.checkCancellation()
        guard AXIsProcessTrusted() else {
            clearCachedSnapshot()
            throw WindowServiceError.actionFailed(action: action, windowID: window)
        }
        guard let target else {
            removeCachedTarget(window)
            throw WindowServiceError.windowNotFound(window)
        }

        if action == .quit {
            let didTerminate = await MainActor.run {
                guard AXIsProcessTrusted(),
                      let application = NSRunningApplication(
                          processIdentifier: window.processIdentifier
                      ),
                      application.isTerminated == false,
                      Self.identity(of: application) == expectedApplicationIdentity else {
                    return false
                }
                return application.terminate()
            }
            guard didTerminate else {
                throw WindowServiceError.actionFailed(action: action, windowID: window)
            }
            return
        }

        if action == .activate, case .windowless = target {
            let didActivate = await MainActor.run {
                guard AXIsProcessTrusted(),
                      let application = NSRunningApplication(
                          processIdentifier: window.processIdentifier
                      ),
                      application.isTerminated == false,
                      Self.identity(of: application) == expectedApplicationIdentity else {
                    return false
                }
                if application.isHidden { application.unhide() }
                return application.activate(options: [])
            }
            guard didActivate else {
                throw WindowServiceError.actionFailed(action: action, windowID: window)
            }
            return
        }

        guard case let .window(element) = target else {
            throw WindowServiceError.actionUnavailable(action: action, windowID: window)
        }

        do {
            switch action {
            case .activate:
                try await activate(
                    element,
                    expectedApplicationIdentity: expectedApplicationIdentity
                )
            case .close:
                try pressButton(attribute: kAXCloseButtonAttribute, on: element)
            case .toggleMinimized:
                try setBoolean(
                    !(Self.bool(attribute: kAXMinimizedAttribute, from: element) ?? false),
                    attribute: kAXMinimizedAttribute,
                    on: element
                )
            case .toggleFullScreen:
                try pressButton(attribute: kAXFullScreenButtonAttribute, on: element)
            case .zoom:
                try pressButton(attribute: kAXZoomButtonAttribute, on: element)
            case .center:
                try await apply(.center, to: element)
            case .leftHalf:
                try await apply(.leftHalf, to: element)
            case .rightHalf:
                try await apply(.rightHalf, to: element)
            case .topHalf:
                try await apply(.topHalf, to: element)
            case .bottomHalf:
                try await apply(.bottomHalf, to: element)
            case .quit:
                break
            }
        } catch NativeActionError.unavailable {
            throw WindowServiceError.windowNotFound(window)
        } catch NativeActionError.unsupported {
            throw WindowServiceError.actionUnavailable(action: action, windowID: window)
        } catch {
            throw WindowServiceError.actionFailed(action: action, windowID: window)
        }
    }

    private enum ResolvedTarget {
        case window(AXUIElement)
        case windowless
    }

    private func resolveTarget(
        _ window: WindowID,
        expectedApplicationIdentity: ApplicationIdentity
    ) async -> ResolvedTarget? {
        guard let currentApplication = await runningApplication(
            processIdentifier: window.processIdentifier
        ), currentApplication.identity == expectedApplicationIdentity,
        AXIsProcessTrusted() else {
            return nil
        }

        let applicationElement = AXUIElementCreateApplication(window.processIdentifier)
        let currentWindows = Self.elements(
            attribute: kAXWindowsAttribute,
            from: applicationElement
        )

        if windowlessIDs.contains(window) {
            guard currentWindows.contains(where: Self.isStandardWindow) == false else {
                return nil
            }
            return .windowless
        }

        guard let cachedElement = elementsByID[window],
              let currentElement = currentWindows.first(where: {
                  CFEqual($0, cachedElement)
              }) else {
            return nil
        }
        return .window(currentElement)
    }

    private func clearCachedSnapshot() {
        elementsByID.removeAll(keepingCapacity: false)
        windowlessIDs.removeAll(keepingCapacity: false)
        applicationIdentityByID.removeAll(keepingCapacity: false)
    }

    private func removeCachedTarget(_ window: WindowID) {
        elementsByID[window] = nil
        windowlessIDs.remove(window)
        applicationIdentityByID[window] = nil
    }

    private func activate(
        _ element: AXUIElement,
        expectedApplicationIdentity: ApplicationIdentity
    ) async throws {
        if Self.bool(attribute: kAXMinimizedAttribute, from: element) == true {
            try setBoolean(false, attribute: kAXMinimizedAttribute, on: element)
        }
        let didActivate = await MainActor.run {
            guard AXIsProcessTrusted(),
                  let application = NSRunningApplication(
                      processIdentifier: expectedApplicationIdentity.processIdentifier
                  ),
                  application.isTerminated == false,
                  Self.identity(of: application) == expectedApplicationIdentity else {
                return false
            }
            if application.isHidden { application.unhide() }
            return application.activate(options: [])
        }
        let raiseStatus = AXUIElementPerformAction(element, kAXRaiseAction as CFString)
        _ = AXUIElementSetAttributeValue(
            element,
            kAXMainAttribute as CFString,
            kCFBooleanTrue
        )
        _ = AXUIElementSetAttributeValue(
            element,
            kAXFocusedAttribute as CFString,
            kCFBooleanTrue
        )
        guard didActivate, raiseStatus == .success else {
            throw NativeActionError.failed
        }
    }

    private enum LayoutTarget {
        case center
        case leftHalf
        case rightHalf
        case topHalf
        case bottomHalf

        func frame(in visibleFrame: CGRect, currentSize: CGSize) -> CGRect {
            switch self {
            case .center:
                let width = min(currentSize.width, visibleFrame.width * 0.8)
                let height = min(currentSize.height, visibleFrame.height * 0.8)
                return CGRect(
                    x: visibleFrame.midX - width / 2,
                    y: visibleFrame.midY - height / 2,
                    width: width,
                    height: height
                )
            case .leftHalf:
                return CGRect(
                    x: visibleFrame.minX,
                    y: visibleFrame.minY,
                    width: visibleFrame.width / 2,
                    height: visibleFrame.height
                )
            case .rightHalf:
                return CGRect(
                    x: visibleFrame.midX,
                    y: visibleFrame.minY,
                    width: visibleFrame.width / 2,
                    height: visibleFrame.height
                )
            case .topHalf:
                return CGRect(
                    x: visibleFrame.minX,
                    y: visibleFrame.midY,
                    width: visibleFrame.width,
                    height: visibleFrame.height / 2
                )
            case .bottomHalf:
                return CGRect(
                    x: visibleFrame.minX,
                    y: visibleFrame.minY,
                    width: visibleFrame.width,
                    height: visibleFrame.height / 2
                )
            }
        }
    }

    private func apply(_ target: LayoutTarget, to element: AXUIElement) async throws {
        guard let accessibilityFrame = Self.accessibilityFrame(of: element) else {
            throw NativeActionError.unavailable
        }
        let displays = await displayRecords()
        guard let display = displays.max(by: { left, right in
            left.frame.intersection(
                left.appKitFrame(fromAccessibilityFrame: accessibilityFrame)
            ).area < right.frame.intersection(
                right.appKitFrame(fromAccessibilityFrame: accessibilityFrame)
            ).area
        }) else {
            throw NativeActionError.failed
        }
        let currentAppKitFrame = display.appKitFrame(
            fromAccessibilityFrame: accessibilityFrame
        )
        let targetFrame = target.frame(
            in: display.visibleFrame,
            currentSize: currentAppKitFrame.size
        ).integral
        var targetPosition = display.accessibilityOrigin(fromAppKitFrame: targetFrame)
        var targetSize = targetFrame.size
        guard let positionValue = AXValueCreate(.cgPoint, &targetPosition),
              let sizeValue = AXValueCreate(.cgSize, &targetSize),
              AXUIElementSetAttributeValue(
                  element,
                  kAXSizeAttribute as CFString,
                  sizeValue
              ) == .success,
              AXUIElementSetAttributeValue(
                  element,
                  kAXPositionAttribute as CFString,
                  positionValue
              ) == .success else {
            throw NativeActionError.failed
        }
    }

    private func pressButton(attribute: String, on element: AXUIElement) throws {
        guard tryPressButton(attribute: attribute, on: element) else {
            throw NativeActionError.unsupported
        }
    }

    private func tryPressButton(attribute: String, on element: AXUIElement) -> Bool {
        guard let button = Self.element(attribute: attribute, from: element) else {
            return false
        }
        return AXUIElementPerformAction(button, kAXPressAction as CFString) == .success
    }

    private func setBoolean(
        _ value: Bool,
        attribute: String,
        on element: AXUIElement
    ) throws {
        var isSettable = DarwinBoolean(false)
        guard AXUIElementIsAttributeSettable(
            element,
            attribute as CFString,
            &isSettable
        ) == .success,
        isSettable.boolValue,
        AXUIElementSetAttributeValue(
            element,
            attribute as CFString,
            value ? kCFBooleanTrue : kCFBooleanFalse
        ) == .success else {
            throw NativeActionError.unsupported
        }
    }

    static func shouldIncludeWindowlessPlaceholder(
        hasConcreteWindows: Bool,
        options: WindowQueryOptions
    ) -> Bool {
        options.includeWindowless
            && options.currentDesktopOnly == false
            && hasConcreteWindows == false
    }

    private func runningApplications() async -> [RunningApplicationRecord] {
        await MainActor.run {
            NSWorkspace.shared.runningApplications.compactMap { application in
                guard application.activationPolicy == .regular,
                      application.isTerminated == false,
                      application.processIdentifier != ProcessInfo.processInfo.processIdentifier
                else {
                    return nil
                }
                return RunningApplicationRecord(
                    processIdentifier: application.processIdentifier,
                    bundleIdentifier: application.bundleIdentifier,
                    localizedName: application.localizedName ?? "Application",
                    isHidden: application.isHidden,
                    launchDate: application.launchDate
                )
            }
        }
    }

    private func runningApplication(
        processIdentifier: Int32
    ) async -> RunningApplicationRecord? {
        await MainActor.run {
            guard let application = NSRunningApplication(
                processIdentifier: processIdentifier
            ), application.activationPolicy == .regular,
            application.isTerminated == false,
            application.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
                return nil
            }
            return RunningApplicationRecord(
                processIdentifier: application.processIdentifier,
                bundleIdentifier: application.bundleIdentifier,
                localizedName: application.localizedName ?? "Application",
                isHidden: application.isHidden,
                launchDate: application.launchDate
            )
        }
    }

    @MainActor
    private static func identity(of application: NSRunningApplication) -> ApplicationIdentity {
        ApplicationIdentity(
            processIdentifier: application.processIdentifier,
            bundleIdentifier: application.bundleIdentifier,
            launchDate: application.launchDate
        )
    }

    private func displayRecords() async -> [DisplayRecord] {
        await MainActor.run {
            let primaryHeight = NSScreen.screens.first(where: { $0.frame.origin == .zero })?
                .frame.height ?? NSScreen.main?.frame.height ?? 0
            return NSScreen.screens.map {
                DisplayRecord(
                    frame: $0.frame,
                    visibleFrame: $0.visibleFrame,
                    primaryHeight: primaryHeight
                )
            }
        }
    }

    private static func identifier(
        sessionGeneration: UInt64,
        processIdentifier: Int32,
        index: Int,
        frame: CGRect
    ) -> WindowID {
        let components = [
            String(sessionGeneration),
            String(processIdentifier),
            String(index),
            String(Int(frame.minX.rounded())),
            String(Int(frame.minY.rounded())),
            String(Int(frame.width.rounded())),
            String(Int(frame.height.rounded())),
        ]
        return WindowID(
            rawValue: components.joined(separator: ":"),
            processIdentifier: processIdentifier
        )
    }

    private static func isStandardWindow(_ element: AXUIElement) -> Bool {
        guard string(attribute: kAXRoleAttribute, from: element) == kAXWindowRole else {
            return false
        }
        let subrole = string(attribute: kAXSubroleAttribute, from: element)
        return subrole == nil
            || subrole == kAXStandardWindowSubrole
            || subrole == kAXDialogSubrole
    }

    private static func accessibilityFrame(of element: AXUIElement) -> CGRect? {
        guard let positionValue = value(attribute: kAXPositionAttribute, from: element),
              let sizeValue = value(attribute: kAXSizeAttribute, from: element),
              CFGetTypeID(positionValue) == AXValueGetTypeID(),
              CFGetTypeID(sizeValue) == AXValueGetTypeID() else {
            return nil
        }
        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(
            unsafeDowncast(positionValue, to: AXValue.self),
            .cgPoint,
            &position
        ), AXValueGetValue(
            unsafeDowncast(sizeValue, to: AXValue.self),
            .cgSize,
            &size
        ), size.width > 1, size.height > 1 else {
            return nil
        }
        return CGRect(origin: position, size: size)
    }

    private static func bestOnScreenMatch(
        processIdentifier: Int32,
        title: String,
        accessibilityFrame: CGRect,
        records: [OnScreenWindowRecord]
    ) -> OnScreenWindowRecord? {
        records
            .filter { $0.processIdentifier == processIdentifier }
            .filter { record in
                guard let candidateTitle = record.title,
                      candidateTitle.isEmpty == false,
                      title != "Untitled" else {
                    return true
                }
                return candidateTitle == title
            }
            .min { left, right in
                frameDistance(left.frame, accessibilityFrame)
                    < frameDistance(right.frame, accessibilityFrame)
            }
            .flatMap { record in
                frameDistance(record.frame, accessibilityFrame) <= 20 ? record : nil
            }
    }

    private static func frameDistance(_ left: CGRect, _ right: CGRect) -> CGFloat {
        abs(left.minX - right.minX)
            + abs(left.minY - right.minY)
            + abs(left.width - right.width)
            + abs(left.height - right.height)
    }

    private static func onScreenWindowRecords(
        primaryHeight: CGFloat
    ) -> [OnScreenWindowRecord] {
        guard let rawList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            .zero
        ) as? [[String: Any]] else {
            return []
        }
        return rawList.compactMap { dictionary in
            guard (dictionary[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                  let identifier = (dictionary[kCGWindowNumber as String] as? NSNumber)?.uint32Value,
                  let processIdentifier = (dictionary[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
                  let bounds = dictionary[kCGWindowBounds as String] as? [String: Any],
                  let x = (bounds["X"] as? NSNumber)?.doubleValue,
                  let y = (bounds["Y"] as? NSNumber)?.doubleValue,
                  let width = (bounds["Width"] as? NSNumber)?.doubleValue,
                  let height = (bounds["Height"] as? NSNumber)?.doubleValue else {
                return nil
            }
            let frame = CGRect(x: x, y: y, width: width, height: height)
            return OnScreenWindowRecord(
                windowID: identifier,
                processIdentifier: processIdentifier,
                title: dictionary[kCGWindowName as String] as? String,
                frame: CGRect(
                    x: frame.minX,
                    y: frame.minY,
                    width: frame.width,
                    height: frame.height
                )
            )
        }
    }

    private static func value(
        attribute: String,
        from element: AXUIElement
    ) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            attribute as CFString,
            &value
        ) == .success else {
            return nil
        }
        return value
    }

    private static func string(
        attribute: String,
        from element: AXUIElement
    ) -> String? {
        value(attribute: attribute, from: element) as? String
    }

    private static func bool(
        attribute: String,
        from element: AXUIElement
    ) -> Bool? {
        value(attribute: attribute, from: element) as? Bool
    }

    private static func element(
        attribute: String,
        from element: AXUIElement
    ) -> AXUIElement? {
        guard let value = value(attribute: attribute, from: element),
              CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return nil
        }
        return unsafeDowncast(value, to: AXUIElement.self)
    }

    private static func elements(
        attribute: String,
        from element: AXUIElement
    ) -> [AXUIElement] {
        value(attribute: attribute, from: element) as? [AXUIElement] ?? []
    }
}

private extension CGRect {
    nonisolated var area: CGFloat { isNull ? 0 : width * height }
}
