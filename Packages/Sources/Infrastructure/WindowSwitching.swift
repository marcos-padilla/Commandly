import CoreGraphics
import Foundation

/// Stable identity for one user-facing window during its owning application's lifetime.
///
/// The opaque `rawValue` is supplied by the system adapter. Consumers must use the complete value,
/// including `processIdentifier`, instead of treating a platform window number as globally stable.
public struct WindowID: Sendable, Equatable, Hashable, Codable {
    /// Adapter-defined identity for the window.
    public let rawValue: String
    /// Process that owned the window when the identity was created.
    public let processIdentifier: Int32

    /// Creates an opaque window identity scoped to an owning process.
    public init(rawValue: String, processIdentifier: Int32) {
        self.rawValue = rawValue
        self.processIdentifier = processIdentifier
    }
}

/// Content-free metadata for a window that may be displayed by a switching interface.
///
/// The snapshot intentionally excludes pixels, document URLs, and accessibility element objects.
/// Window titles may still contain private document names and must never be logged or persisted.
public struct WindowSnapshot: Sendable, Equatable, Identifiable {
    /// Stable identity used for subsequent control requests.
    public let id: WindowID
    /// Process that owns the window.
    public let processIdentifier: Int32
    /// Bundle identifier reported for the owning application, when available.
    public let bundleIdentifier: String?
    /// Localized user-visible name of the owning application.
    public let applicationName: String
    /// Current window title. This value is private user activity and must remain ephemeral.
    public let title: String
    /// Window frame in global display coordinates.
    public let frame: CGRect
    /// Whether the window is currently minimized.
    public let isMinimized: Bool
    /// Whether the owning application currently hides the window.
    public let isHidden: Bool
    /// Whether the adapter determined that the window belongs to the active desktop.
    public let isOnCurrentDesktop: Bool
    /// Whether the window is the currently focused window.
    public let isFocused: Bool
    /// Whether this is an application placeholder with no concrete window.
    public let isWindowless: Bool
    /// Public Core Graphics window number that may be used for an explicitly authorized preview.
    ///
    /// `nil` means no capturable window could be correlated. Consumers must not infer that Screen
    /// Recording permission is granted from the presence or absence of this value.
    public let captureWindowID: UInt32?

    /// Creates an immutable window metadata snapshot.
    public init(
        id: WindowID,
        processIdentifier: Int32,
        bundleIdentifier: String?,
        applicationName: String,
        title: String,
        frame: CGRect,
        isMinimized: Bool,
        isHidden: Bool,
        isOnCurrentDesktop: Bool,
        isFocused: Bool,
        captureWindowID: UInt32?,
        isWindowless: Bool = false
    ) {
        self.id = id
        self.processIdentifier = processIdentifier
        self.bundleIdentifier = bundleIdentifier
        self.applicationName = applicationName
        self.title = title
        self.frame = frame
        self.isMinimized = isMinimized
        self.isHidden = isHidden
        self.isOnCurrentDesktop = isOnCurrentDesktop
        self.isFocused = isFocused
        self.captureWindowID = captureWindowID
        self.isWindowless = isWindowless
    }

    public static func == (lhs: WindowSnapshot, rhs: WindowSnapshot) -> Bool {
        lhs.id == rhs.id
            && lhs.processIdentifier == rhs.processIdentifier
            && lhs.bundleIdentifier == rhs.bundleIdentifier
            && lhs.applicationName == rhs.applicationName
            && lhs.title == rhs.title
            && CGRectEqualToRect(lhs.frame, rhs.frame)
            && lhs.isMinimized == rhs.isMinimized
            && lhs.isHidden == rhs.isHidden
            && lhs.isOnCurrentDesktop == rhs.isOnCurrentDesktop
            && lhs.isFocused == rhs.isFocused
            && lhs.captureWindowID == rhs.captureWindowID
            && lhs.isWindowless == rhs.isWindowless
    }
}

/// Filters applied while discovering windows for one switcher presentation.
public struct WindowQueryOptions: Sendable, Equatable {
    /// Includes minimized windows when `true`.
    public let includeMinimized: Bool
    /// Includes windows belonging to hidden applications when `true`.
    public let includeHidden: Bool
    /// Includes application placeholders that have no concrete window when `true`.
    public let includeWindowless: Bool
    /// Limits results to the active desktop when `true`.
    public let currentDesktopOnly: Bool
    /// Limits concrete windows to those intersecting this global display frame when non-`nil`.
    public let currentDisplayFrame: CGRect?
    /// Bundle identifiers omitted from results, such as Commandly itself.
    public let excludedBundleIdentifiers: Set<String>
    /// Case- and diacritic-insensitive title fragments omitted from results.
    public let excludedTitleTerms: [String]

    /// Creates query options. Defaults include minimized windows on the active desktop while
    /// excluding hidden and windowless applications.
    public init(
        includeMinimized: Bool = true,
        includeHidden: Bool = false,
        includeWindowless: Bool = false,
        currentDesktopOnly: Bool = true,
        currentDisplayFrame: CGRect? = nil,
        excludedBundleIdentifiers: Set<String> = [],
        excludedTitleTerms: [String] = []
    ) {
        self.includeMinimized = includeMinimized
        self.includeHidden = includeHidden
        self.includeWindowless = includeWindowless
        self.currentDesktopOnly = currentDesktopOnly
        self.currentDisplayFrame = currentDisplayFrame
        self.excludedBundleIdentifiers = excludedBundleIdentifiers
        self.excludedTitleTerms = excludedTitleTerms
    }

    /// Default switcher query policy.
    public static let `default` = WindowQueryOptions()

    public static func == (lhs: WindowQueryOptions, rhs: WindowQueryOptions) -> Bool {
        lhs.includeMinimized == rhs.includeMinimized
            && lhs.includeHidden == rhs.includeHidden
            && lhs.includeWindowless == rhs.includeWindowless
            && lhs.currentDesktopOnly == rhs.currentDesktopOnly
            && equalFrames(lhs.currentDisplayFrame, rhs.currentDisplayFrame)
            && lhs.excludedBundleIdentifiers == rhs.excludedBundleIdentifiers
            && lhs.excludedTitleTerms == rhs.excludedTitleTerms
    }

    private static func equalFrames(_ lhs: CGRect?, _ rhs: CGRect?) -> Bool {
        switch (lhs, rhs) {
        case (.none, .none):
            return true
        case let (.some(lhs), .some(rhs)):
            return CGRectEqualToRect(lhs, rhs)
        case (.some, .none), (.none, .some):
            return false
        }
    }
}

/// User-initiated operation that may be applied to a discovered window.
public enum WindowAction: String, CaseIterable, Codable, Sendable, Equatable, Hashable {
    /// Restores and focuses the selected window.
    case activate
    /// Requests that the selected window close.
    case close
    /// Alternates the selected window between minimized and restored states.
    case toggleMinimized
    /// Alternates native full-screen state when supported by the target window.
    case toggleFullScreen
    /// Performs the target window's native zoom operation.
    case zoom
    /// Centers the target window on its current display without resizing it.
    case center
    /// Places the target window in the left half of its current display.
    case leftHalf
    /// Places the target window in the right half of its current display.
    case rightHalf
    /// Places the target window in the top half of its current display.
    case topHalf
    /// Places the target window in the bottom half of its current display.
    case bottomHalf
    /// Requests that the owning application quit gracefully.
    case quit
}

/// Typed failures from window discovery and control adapters.
public enum WindowServiceError: Error, Sendable, Equatable {
    /// The system could not produce a window catalog.
    case queryUnavailable
    /// The requested window no longer exists or belongs to a replaced process.
    case windowNotFound(WindowID)
    /// The target window does not support the requested action.
    case actionUnavailable(action: WindowAction, windowID: WindowID)
    /// The system rejected or failed a supported action.
    case actionFailed(action: WindowAction, windowID: WindowID)
}

/// Discovers ephemeral window metadata without prompting for a system permission.
///
/// Implementations must respect cancellation, keep titles in memory only, and return a typed error
/// when required authorization is absent. Permission prompts belong to an explicit user action
/// through the app's permission service, never to this query.
public protocol WindowQuerying: Sendable {
    /// Returns windows matching the supplied policy in adapter-defined presentation order.
    func windows(options: WindowQueryOptions) async throws -> [WindowSnapshot]
}

public extension WindowQuerying {
    /// Returns windows using the default query policy.
    func windows() async throws -> [WindowSnapshot] {
        try await windows(options: .default)
    }
}

/// Performs explicit user-selected actions on previously discovered windows.
///
/// Implementations must resolve the complete `WindowID` again before acting, must fail closed when
/// the window disappeared or changed ownership, and must not prompt for Accessibility implicitly.
public protocol WindowControlling: Sendable {
    /// Performs an action against one window identity.
    func perform(_ action: WindowAction, on windowID: WindowID) async throws
}

/// Releases adapter-private references associated with a dismissed presentation.
///
/// Session-scoped IDs let an adapter remove an older presentation without racing a newer query
/// that may describe the same process and geometry.
public protocol WindowSessionReleasing: Sendable {
    /// Discards private adapter state for exactly the supplied ephemeral window identities.
    func releaseWindowSession(windowIDs: Set<WindowID>) async
}

/// One successful action recorded by the deterministic in-memory adapter.
public struct WindowActionInvocation: Sendable, Equatable, Hashable {
    public let action: WindowAction
    public let windowID: WindowID

    /// Creates a recorded window action.
    public init(action: WindowAction, windowID: WindowID) {
        self.action = action
        self.windowID = windowID
    }
}

/// Deterministic window query and control adapter for tests and previews.
///
/// It applies every query option, records successful actions, and mutates only state represented by
/// `WindowSnapshot`. Geometry/full-screen actions are recorded without inventing system behavior.
public actor InMemoryWindowService: WindowQuerying, WindowControlling {
    private var snapshots: [WindowSnapshot]
    private let queryError: WindowServiceError?
    private let actionError: WindowServiceError?

    /// Successful control requests in invocation order.
    public private(set) var performedActions: [WindowActionInvocation] = []

    /// Creates an in-memory adapter with optional deterministic failures.
    public init(
        windows: [WindowSnapshot] = [],
        queryError: WindowServiceError? = nil,
        actionError: WindowServiceError? = nil
    ) {
        snapshots = windows
        self.queryError = queryError
        self.actionError = actionError
    }

    public func windows(options: WindowQueryOptions) async throws -> [WindowSnapshot] {
        try Task.checkCancellation()
        if let queryError {
            throw queryError
        }

        return snapshots.filter { snapshot in
            Self.includes(snapshot, options: options)
        }
    }

    public func perform(_ action: WindowAction, on windowID: WindowID) async throws {
        try Task.checkCancellation()
        if let actionError {
            throw actionError
        }
        guard let target = snapshots.first(where: { $0.id == windowID }) else {
            throw WindowServiceError.windowNotFound(windowID)
        }

        performedActions.append(WindowActionInvocation(action: action, windowID: windowID))
        switch action {
        case .activate:
            snapshots = snapshots.map { snapshot in
                snapshot.replacing(
                    isMinimized: snapshot.id == windowID ? false : snapshot.isMinimized,
                    isHidden: snapshot.id == windowID ? false : snapshot.isHidden,
                    isFocused: snapshot.id == windowID
                )
            }
        case .close:
            snapshots.removeAll { $0.id == windowID }
        case .toggleMinimized:
            snapshots = snapshots.map { snapshot in
                guard snapshot.id == windowID else { return snapshot }
                return snapshot.replacing(
                    isMinimized: !snapshot.isMinimized,
                    isFocused: false
                )
            }
        case .quit:
            snapshots.removeAll { $0.processIdentifier == target.processIdentifier }
        case .toggleFullScreen, .zoom, .center, .leftHalf, .rightHalf, .topHalf, .bottomHalf:
            break
        }
    }

    /// Replaces the complete deterministic catalog while retaining action history.
    public func replaceWindows(_ windows: [WindowSnapshot]) {
        snapshots = windows
    }

    private static func includes(
        _ snapshot: WindowSnapshot,
        options: WindowQueryOptions
    ) -> Bool {
        if options.includeMinimized == false && snapshot.isMinimized {
            return false
        }
        if options.includeHidden == false && snapshot.isHidden {
            return false
        }
        if options.includeWindowless == false && snapshot.isWindowless {
            return false
        }
        if options.currentDesktopOnly && snapshot.isOnCurrentDesktop == false {
            return false
        }
        if let bundleIdentifier = snapshot.bundleIdentifier,
           options.excludedBundleIdentifiers.contains(bundleIdentifier) {
            return false
        }
        if snapshot.isWindowless == false,
           let displayFrame = options.currentDisplayFrame,
           CGRectIntersectsRect(snapshot.frame, displayFrame) == false {
            return false
        }

        return options.excludedTitleTerms.contains { term in
            term.isEmpty == false
                && snapshot.title.range(
                    of: term,
                    options: [.caseInsensitive, .diacriticInsensitive]
                ) != nil
        } == false
    }
}

private extension WindowSnapshot {
    func replacing(
        isMinimized: Bool? = nil,
        isHidden: Bool? = nil,
        isFocused: Bool? = nil
    ) -> WindowSnapshot {
        WindowSnapshot(
            id: id,
            processIdentifier: processIdentifier,
            bundleIdentifier: bundleIdentifier,
            applicationName: applicationName,
            title: title,
            frame: frame,
            isMinimized: isMinimized ?? self.isMinimized,
            isHidden: isHidden ?? self.isHidden,
            isOnCurrentDesktop: isOnCurrentDesktop,
            isFocused: isFocused ?? self.isFocused,
            captureWindowID: captureWindowID,
            isWindowless: isWindowless
        )
    }
}
