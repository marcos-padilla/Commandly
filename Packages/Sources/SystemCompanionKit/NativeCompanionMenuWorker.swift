import ApplicationServices
import Dispatch
import Foundation
import Infrastructure

/// Native access is injected into the controller; generated tests never invoke AX.
public protocol CompanionMenuWorking: Sendable {
    func snapshot(context: CompanionMenuContext, deadline: ContinuousClock.Instant) async throws -> [CompanionMenuCandidate]
    func invoke(id: UUID, context: CompanionMenuContext, deadline: ContinuousClock.Instant) async throws -> CompanionMenuInvocationOutcome
    func clear() async
}
/// Serial actor owns every AX reference. Reads only a menu bar and its bounded children on explicit capture.
/// Every message has a <=100 ms timeout and checks the shared five-second request deadline.
public actor NativeCompanionMenuWorker: CompanionMenuWorking {
    nonisolated private let queue = DispatchSerialQueue(label: "com.commandly.companion.menu-ax", qos: .userInitiated)
    nonisolated public var unownedExecutor: UnownedSerialExecutor { queue.asUnownedSerialExecutor() }
    private struct Target { let context: CompanionMenuContext; let candidate: CompanionMenuCandidate }
    private let lease: CompanionMenuLease
    private let environment: any CompanionMenuEnvironment
    private var targets: [UUID: Target] = [:]
    public init(lease: CompanionMenuLease, environment: any CompanionMenuEnvironment) { self.lease = lease; self.environment = environment }
    public func clear() { targets.removeAll() }
    public func snapshot(context: CompanionMenuContext, deadline: ContinuousClock.Instant) async throws -> [CompanionMenuCandidate] {
        targets.removeAll()
        try await environment.validate(context)
        try check(context, deadline)
        let app = AXUIElementCreateApplication(context.application.processIdentifier)
        let bar = try menuBar(app, context, deadline)
        var entries: [CompanionMenuCandidate] = []
        var visited = 0
        try walk(bar, path: [], ancestorsEnabled: true, context: context, deadline: deadline, visited: &visited, entries: &entries)
        try await environment.validate(context)
        try check(context, deadline)
        targets = Dictionary(uniqueKeysWithValues: entries.map { ($0.id, Target(context: context, candidate: $0)) })
        return entries
    }
    public func invoke(id: UUID, context: CompanionMenuContext, deadline: ContinuousClock.Instant) async throws -> CompanionMenuInvocationOutcome {
        guard let target = targets[id], target.context == context else { throw CompanionAppMenuError.stale }
        targets.removeAll() // Consume all handles before any suspension, including ambiguous native outcomes.
        try await environment.validate(context)
        try check(context, deadline)
        let app = AXUIElementCreateApplication(context.application.processIdentifier)
        _ = try resolve(target.candidate, app: app, context: context, deadline: deadline)
        // Revalidate the OS context after path traversal, then resolve the exact path again without suspension.
        try await environment.validate(context)
        let element = try resolve(target.candidate, app: app, context: context, deadline: deadline)
        try prepare(element, context, deadline)
        try check(context, deadline)
        let result = AXUIElementPerformAction(element, kAXPressAction as CFString)
        // A timeout may have followed dispatch; never present this as a safe-to-retry rejection.
        return result == .success ? .accepted : .outcomeUnknown
    }
    private func resolve(_ candidate: CompanionMenuCandidate, app: AXUIElement,
                         context: CompanionMenuContext, deadline: ContinuousClock.Instant) throws -> AXUIElement {
        var element = try menuBar(app, context, deadline)
        var current: [CompanionMenuPathComponent] = []
        for expected in candidate.path {
            let children = try children(element, context, deadline)
            guard children.indices.contains(expected.index) else { throw CompanionAppMenuError.stale }
            element = children[expected.index]
            let part = try fingerprint(element, index: expected.index, context, deadline)
            guard part == expected else { throw CompanionAppMenuError.stale }
            if part.role != kAXMenuRole as String, try !enabled(element, context, deadline) { throw CompanionAppMenuError.stale }
            current.append(part)
        }
        try candidate.requireUnchanged(path: current, enabled: enabled(element, context, deadline))
        guard try children(element, context, deadline).isEmpty,
              current.last?.role == kAXMenuItemRole as String else { throw CompanionAppMenuError.stale }
        return element
    }
    private func walk(_ element: AXUIElement, path: [CompanionMenuPathComponent], ancestorsEnabled: Bool, context: CompanionMenuContext,
                      deadline: ContinuousClock.Instant, visited: inout Int, entries: inout [CompanionMenuCandidate]) throws {
        guard path.count < 12 else { throw CompanionAppMenuError.tooLarge }
        for (index, child) in try children(element, context, deadline).enumerated() {
            visited += 1
            guard visited <= 500 else { throw CompanionAppMenuError.tooLarge }
            let part = try fingerprint(child, index: index, context, deadline)
            guard [kAXMenuBarItemRole as String, kAXMenuRole as String, kAXMenuItemRole as String].contains(part.role) else { continue }
            let next = path + [part]
            let available = try part.role == kAXMenuRole as String ? ancestorsEnabled : ancestorsEnabled && enabled(child, context, deadline)
            let nested = try children(child, context, deadline)
            if !nested.isEmpty {
                try walk(child, path: next, ancestorsEnabled: available, context: context, deadline: deadline, visited: &visited, entries: &entries)
            } else if part.role == kAXMenuItemRole as String, !part.title.isEmpty {
                entries.append(.init(path: next, enabled: available))
            }
        }
    }
    private func check(_ context: CompanionMenuContext, _ deadline: ContinuousClock.Instant) throws {
        try Task.checkCancellation()
        guard ContinuousClock.now < deadline else { throw CompanionAppMenuError.timedOut }
        try lease.validate(context)
        guard AXIsProcessTrusted() else { throw CompanionAppMenuError.permissionDenied } // Never prompts.
    }
    private func prepare(_ element: AXUIElement, _ context: CompanionMenuContext, _ deadline: ContinuousClock.Instant) throws {
        try check(context, deadline)
        let duration = ContinuousClock.now.duration(to: deadline).components
        let seconds = Double(duration.seconds) + Double(duration.attoseconds) / 1e18
        guard seconds > 0 else { throw CompanionAppMenuError.timedOut }
        guard AXUIElementSetMessagingTimeout(element, Float(min(seconds, 0.1))) == .success else { throw CompanionAppMenuError.unavailable }
        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success, pid == context.application.processIdentifier else { throw CompanionAppMenuError.stale }
    }
    private func value(_ element: AXUIElement, _ attribute: CFString, _ context: CompanionMenuContext,
                       _ deadline: ContinuousClock.Instant, optional: Bool = false) throws -> CFTypeRef? {
        try prepare(element, context, deadline)
        var result: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, attribute, &result)
        if optional && (error == .attributeUnsupported || error == .noValue) { return nil }
        guard error == .success else { throw error == .cannotComplete ? CompanionAppMenuError.timedOut : .unsupported }
        return result
    }
    private func text(_ element: AXUIElement, _ attribute: CFString, _ context: CompanionMenuContext,
                      _ deadline: ContinuousClock.Instant, optional: Bool = false) throws -> String {
        guard let value = try value(element, attribute, context, deadline, optional: optional) else { return "" }
        guard let string = value as? String, string.utf8.count <= 512,
              !string.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { throw CompanionAppMenuError.tooLarge }
        return string
    }
    private func fingerprint(_ element: AXUIElement, index: Int, _ context: CompanionMenuContext,
                             _ deadline: ContinuousClock.Instant) throws -> CompanionMenuPathComponent {
        .init(index: index, role: try text(element, kAXRoleAttribute as CFString, context, deadline),
              title: try text(element, kAXTitleAttribute as CFString, context, deadline, optional: true),
              identifier: try text(element, kAXIdentifierAttribute as CFString, context, deadline, optional: true),
              shortcut: try shortcut(element, context, deadline))
    }
    private func shortcut(_ element: AXUIElement, _ context: CompanionMenuContext, _ deadline: ContinuousClock.Instant) throws -> String {
        let character = try text(element, kAXMenuItemCmdCharAttribute as CFString, context, deadline, optional: true)
        let codes = try [kAXMenuItemCmdModifiersAttribute, kAXMenuItemCmdVirtualKeyAttribute, kAXMenuItemCmdGlyphAttribute].map { name in
            guard let value = try value(element, name as CFString, context, deadline, optional: true) else { return "-" }
            guard CFGetTypeID(value) == CFNumberGetTypeID(), let number = value as? NSNumber,
                  (0...65535).contains(number.intValue) else { throw CompanionAppMenuError.unsupported }
            return String(number.intValue)
        }
        return ([character] + codes).joined(separator: ":")
    }
    private func enabled(_ element: AXUIElement, _ context: CompanionMenuContext, _ deadline: ContinuousClock.Instant) throws -> Bool {
        guard let value = try value(element, kAXEnabledAttribute as CFString, context, deadline),
              CFGetTypeID(value) == CFBooleanGetTypeID() else { throw CompanionAppMenuError.unsupported }
        return CFEqual(value, kCFBooleanTrue)
    }
    private func menuBar(_ app: AXUIElement, _ context: CompanionMenuContext, _ deadline: ContinuousClock.Instant) throws -> AXUIElement {
        guard let value = try value(app, kAXMenuBarAttribute as CFString, context, deadline),
              CFGetTypeID(value) == AXUIElementGetTypeID() else { throw CompanionAppMenuError.unsupported }
        // CF runtime type was checked; this Foundation bridging cast never accepts an arbitrary value.
        return unsafeDowncast(value, to: AXUIElement.self)
    }
    private func children(_ element: AXUIElement, _ context: CompanionMenuContext, _ deadline: ContinuousClock.Instant) throws -> [AXUIElement] {
        try prepare(element, context, deadline)
        var count = 0
        let error = AXUIElementGetAttributeValueCount(element, kAXChildrenAttribute as CFString, &count)
        if error == .attributeUnsupported || error == .noValue { return [] }
        guard error == .success else { throw error == .cannotComplete ? CompanionAppMenuError.timedOut : .unsupported }
        guard (0...500).contains(count) else { throw CompanionAppMenuError.tooLarge }
        if count == 0 { return [] }
        try prepare(element, context, deadline)
        var values: CFArray?
        let copied = AXUIElementCopyAttributeValues(element, kAXChildrenAttribute as CFString, 0, count, &values)
        guard copied == .success, let values else { throw copied == .cannotComplete ? CompanionAppMenuError.timedOut : .unsupported }
        let objects = values as [AnyObject]
        guard objects.count == count else { throw CompanionAppMenuError.stale }
        return try objects.map {
            guard CFGetTypeID($0) == AXUIElementGetTypeID() else { throw CompanionAppMenuError.unsupported }
            return unsafeDowncast($0, to: AXUIElement.self)
        }
    }
}
