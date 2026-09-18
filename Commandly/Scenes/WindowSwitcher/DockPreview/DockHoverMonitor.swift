import AppKit
import ApplicationServices
import Foundation

struct DockHoveredApplication: Equatable, Sendable {
    let processIdentifier: Int32
    let bundleIdentifier: String
    let anchorFrame: CGRect

    static func == (lhs: DockHoveredApplication, rhs: DockHoveredApplication) -> Bool {
        lhs.processIdentifier == rhs.processIdentifier
            && lhs.bundleIdentifier == rhs.bundleIdentifier
            && CGRectEqualToRect(lhs.anchorFrame, rhs.anchorFrame)
    }
}

@MainActor
protocol DockHoverMonitoring: AnyObject {
    func start(
        delay: TimeInterval,
        protectedFrame: @escaping () -> CGRect?,
        onHover: @escaping (DockHoveredApplication) -> Void,
        onLeave: @escaping () -> Void
    )
    func stop()
}

struct DockHoverRunningApplication: Equatable, Sendable {
    let processIdentifier: Int32
    let bundleIdentifier: String
}

struct DockHoverProcessSnapshot: Equatable, Sendable {
    let dockProcessIdentifier: Int32
    let runningApplications: [DockHoverRunningApplication]
    let primaryDisplayHeight: CGFloat
}

struct DockHoverResolutionRequest: Equatable, Sendable {
    let pointer: CGPoint
    let processes: DockHoverProcessSnapshot
}

nonisolated protocol DockHoverResolving: Sendable {
    func hoveredApplication(
        for request: DockHoverResolutionRequest
    ) async -> DockHoveredApplication?
}

/// Owns the cross-process Accessibility traversal on an executor independent of the main actor.
/// AX elements never leave this actor; only content-free, Sendable snapshots cross the boundary.
actor AccessibilityDockHoverResolver: DockHoverResolving {
    private struct Candidate {
        let element: AXUIElement
        let frame: CGRect
    }

    func hoveredApplication(
        for request: DockHoverResolutionRequest
    ) async -> DockHoveredApplication? {
        guard Task.isCancelled == false else { return nil }
        let root = AXUIElementCreateApplication(request.processes.dockProcessIdentifier)
        guard let candidate = smallestCandidate(
            containing: request.pointer,
            root: root,
            primaryDisplayHeight: request.processes.primaryDisplayHeight
        ), Task.isCancelled == false,
        let url = Self.url(attribute: kAXURLAttribute, from: candidate.element),
        url.pathExtension.caseInsensitiveCompare("app") == .orderedSame,
        let bundleIdentifier = Bundle(url: url)?.bundleIdentifier,
        let application = request.processes.runningApplications.first(where: {
            $0.bundleIdentifier == bundleIdentifier
        }) else {
            return nil
        }
        return DockHoveredApplication(
            processIdentifier: application.processIdentifier,
            bundleIdentifier: bundleIdentifier,
            anchorFrame: candidate.frame
        )
    }

    private func smallestCandidate(
        containing pointer: CGPoint,
        root: AXUIElement,
        primaryDisplayHeight: CGFloat
    ) -> Candidate? {
        var queue: [(element: AXUIElement, depth: Int)] = [(root, 0)]
        var candidates: [Candidate] = []
        var visited = 0
        while queue.isEmpty == false, visited < 240 {
            guard Task.isCancelled == false else { return nil }
            let current = queue.removeFirst()
            visited += 1
            guard current.depth <= 7 else { continue }
            let role = Self.string(attribute: kAXRoleAttribute, from: current.element) ?? ""
            if role.localizedCaseInsensitiveContains("dockitem"),
               let frame = Self.appKitFrame(
                   of: current.element,
                   primaryDisplayHeight: primaryDisplayHeight
               ), frame.contains(pointer) {
                candidates.append(Candidate(element: current.element, frame: frame))
            }
            for child in Self.elements(
                attribute: kAXChildrenAttribute,
                from: current.element
            ) {
                queue.append((child, current.depth + 1))
            }
        }
        return candidates.min { left, right in
            left.frame.width * left.frame.height < right.frame.width * right.frame.height
        }
    }

    private static func appKitFrame(
        of element: AXUIElement,
        primaryDisplayHeight: CGFloat
    ) -> CGRect? {
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
        ) else {
            return nil
        }
        return CGRect(
            x: position.x,
            y: primaryDisplayHeight - position.y - size.height,
            width: size.width,
            height: size.height
        )
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

    private static func url(
        attribute: String,
        from element: AXUIElement
    ) -> URL? {
        value(attribute: attribute, from: element) as? URL
    }

    private static func elements(
        attribute: String,
        from element: AXUIElement
    ) -> [AXUIElement] {
        value(attribute: attribute, from: element) as? [AXUIElement] ?? []
    }
}

struct DockHoverEnvironment {
    let isProcessTrusted: @MainActor () -> Bool
    let pointerLocation: @MainActor () -> CGPoint
    let processSnapshot: @MainActor () -> DockHoverProcessSnapshot?
    let now: @MainActor () -> Date

    @MainActor
    static var live: Self {
        Self(
            isProcessTrusted: { AXIsProcessTrusted() },
            pointerLocation: { NSEvent.mouseLocation },
            processSnapshot: {
                let applications = NSWorkspace.shared.runningApplications.compactMap {
                    application -> DockHoverRunningApplication? in
                    guard let bundleIdentifier = application.bundleIdentifier else { return nil }
                    return DockHoverRunningApplication(
                        processIdentifier: application.processIdentifier,
                        bundleIdentifier: bundleIdentifier
                    )
                }
                guard let dock = applications.first(where: {
                    $0.bundleIdentifier == "com.apple.dock"
                }) else {
                    return nil
                }
                let primaryDisplayHeight = NSScreen.screens.first(where: {
                    $0.frame.origin == .zero
                })?.frame.height ?? NSScreen.main?.frame.height ?? 0
                return DockHoverProcessSnapshot(
                    dockProcessIdentifier: dock.processIdentifier,
                    runningApplications: applications,
                    primaryDisplayHeight: primaryDisplayHeight
                )
            },
            now: Date.init
        )
    }
}

/// Best-effort public Accessibility observer for application icons in the macOS Dock.
///
/// The Dock's accessibility hierarchy is not a documented compatibility contract, so failure to
/// resolve an icon simply disables the preview for that hover. No private CoreDock or SkyLight API
/// is used. Cross-process AX traversal runs in `AccessibilityDockHoverResolver`; this main-actor
/// coordinator retains only Sendable results and presentation callbacks.
@MainActor
final class DockHoverMonitor: DockHoverMonitoring {
    private let resolver: any DockHoverResolving
    private let environment: DockHoverEnvironment
    private let pollInterval: TimeInterval
    private var timer: Timer?
    private var resolutionTask: Task<Void, Never>?
    private var generation = 0
    private var pendingApplication: DockHoveredApplication?
    private var pendingSince: Date?
    private var deliveredApplication: DockHoveredApplication?
    private var delay: TimeInterval = 0.35
    private var protectedFrame: (() -> CGRect?)?
    private var onHover: ((DockHoveredApplication) -> Void)?
    private var onLeave: (() -> Void)?

    init(
        resolver: any DockHoverResolving = AccessibilityDockHoverResolver(),
        environment: DockHoverEnvironment? = nil,
        pollInterval: TimeInterval = 0.12
    ) {
        self.resolver = resolver
        self.environment = environment ?? .live
        self.pollInterval = max(0.01, pollInterval)
    }

    func start(
        delay: TimeInterval,
        protectedFrame: @escaping () -> CGRect?,
        onHover: @escaping (DockHoveredApplication) -> Void,
        onLeave: @escaping () -> Void
    ) {
        stop()
        self.delay = max(0, delay)
        self.protectedFrame = protectedFrame
        self.onHover = onHover
        self.onLeave = onLeave
        let timer = Timer(timeInterval: pollInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.poll()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        poll()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        invalidateResolution()
        pendingApplication = nil
        pendingSince = nil
        deliveredApplication = nil
        protectedFrame = nil
        onHover = nil
        onLeave = nil
    }

    private func poll() {
        guard environment.isProcessTrusted() else {
            invalidateResolution()
            clearHoverIfNeeded()
            return
        }

        let pointer = environment.pointerLocation()
        if let protectedFrame = protectedFrame?(), protectedFrame.contains(pointer) {
            invalidateResolution()
            pendingApplication = nil
            pendingSince = nil
            return
        }

        guard resolutionTask == nil else { return }
        guard let processes = environment.processSnapshot() else {
            clearHoverIfNeeded()
            return
        }

        let request = DockHoverResolutionRequest(pointer: pointer, processes: processes)
        let requestGeneration = generation
        let resolver = resolver
        resolutionTask = Task { @MainActor [weak self] in
            let hovered = await resolver.hoveredApplication(for: request)
            guard let self else { return }
            self.finishResolution(
                hovered,
                generation: requestGeneration,
                wasCancelled: Task.isCancelled
            )
        }
    }

    private func finishResolution(
        _ hovered: DockHoveredApplication?,
        generation requestGeneration: Int,
        wasCancelled: Bool
    ) {
        guard requestGeneration == generation else { return }
        resolutionTask = nil
        guard wasCancelled == false, environment.isProcessTrusted() else {
            clearHoverIfNeeded()
            return
        }

        let pointer = environment.pointerLocation()
        if let protectedFrame = protectedFrame?(), protectedFrame.contains(pointer) {
            pendingApplication = nil
            pendingSince = nil
            return
        }
        guard let hovered, hovered.anchorFrame.contains(pointer) else {
            clearHoverIfNeeded()
            return
        }

        if pendingApplication?.processIdentifier != hovered.processIdentifier {
            pendingApplication = hovered
            pendingSince = environment.now()
            if delay > 0 { return }
        }
        guard deliveredApplication?.processIdentifier != hovered.processIdentifier,
              environment.now().timeIntervalSince(pendingSince ?? environment.now()) >= delay else {
            return
        }
        deliveredApplication = hovered
        onHover?(hovered)
    }

    private func invalidateResolution() {
        generation &+= 1
        resolutionTask?.cancel()
        resolutionTask = nil
    }

    private func clearHoverIfNeeded() {
        pendingApplication = nil
        pendingSince = nil
        guard deliveredApplication != nil else { return }
        deliveredApplication = nil
        onLeave?()
    }
}

@MainActor
final class InMemoryDockHoverMonitor: DockHoverMonitoring {
    private var onHover: ((DockHoveredApplication) -> Void)?
    private var onLeave: (() -> Void)?

    func start(
        delay: TimeInterval,
        protectedFrame: @escaping () -> CGRect?,
        onHover: @escaping (DockHoveredApplication) -> Void,
        onLeave: @escaping () -> Void
    ) {
        self.onHover = onHover
        self.onLeave = onLeave
    }

    func stop() {
        onHover = nil
        onLeave = nil
    }

    func sendHover(_ value: DockHoveredApplication) { onHover?(value) }
    func sendLeave() { onLeave?() }
}
