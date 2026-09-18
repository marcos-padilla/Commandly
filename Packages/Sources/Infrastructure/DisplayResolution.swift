import Foundation

/// One mode from a particular catalog, not a persistent or globally reusable display-mode identifier.
public struct DisplayResolutionMode: Equatable, Identifiable, Sendable {
    public let id: UUID
    public let logicalWidth: Int
    public let logicalHeight: Int
    public let pixelWidth: Int
    public let pixelHeight: Int
    public let refreshRate: Double?
    public let canPreview: Bool
    public init(id: UUID = UUID(), logicalWidth: Int, logicalHeight: Int, pixelWidth: Int, pixelHeight: Int,
                refreshRate: Double?, canPreview: Bool = true) {
        self.id = id; self.logicalWidth = logicalWidth; self.logicalHeight = logicalHeight
        self.pixelWidth = pixelWidth; self.pixelHeight = pixelHeight
        self.refreshRate = refreshRate; self.canPreview = canPreview
    }
    public var isHighDensity: Bool { pixelWidth > logicalWidth || pixelHeight > logicalHeight }
}

/// A connected display and its desktop modes. Tokens expire when the catalog or topology changes.
public struct ResolutionDisplay: Equatable, Identifiable, Sendable {
    public let id: UUID
    public let name: String
    public let currentModeID: UUID
    public let modes: [DisplayResolutionMode]
    public let unavailableReason: String?
    public let modesAreTruncated: Bool
    public init(id: UUID = UUID(), name: String, currentModeID: UUID, modes: [DisplayResolutionMode],
                unavailableReason: String? = nil, modesAreTruncated: Bool = false) {
        self.id = id; self.name = name; self.currentModeID = currentModeID; self.modes = modes
        self.unavailableReason = unavailableReason; self.modesAreTruncated = modesAreTruncated
    }
}

/// Fresh, bounded discovery produced only after the chooser is opened or explicitly refreshed.
public struct DisplayResolutionCatalog: Equatable, Sendable {
    public let id: UUID
    public let displays: [ResolutionDisplay]
    public init(id: UUID = UUID(), displays: [ResolutionDisplay]) { self.id = id; self.displays = displays }
}

/// Explicit selection bound to one discovery result.
public struct DisplayResolutionSelection: Equatable, Sendable {
    public let catalogID: UUID
    public let displayID: UUID
    public let modeID: UUID
    public init(catalogID: UUID, displayID: UUID, modeID: UUID) {
        self.catalogID = catalogID; self.displayID = displayID; self.modeID = modeID
    }
}

/// An app-lifetime preview with an exact original mode retained by its controller for recovery.
public struct DisplayResolutionPreview: Equatable, Identifiable, Sendable {
    public let id: UUID
    public let displayName: String
    public let original: DisplayResolutionMode
    public let proposed: DisplayResolutionMode
    public let deadline: ContinuousClock.Instant
    public init(id: UUID, displayName: String, original: DisplayResolutionMode,
                proposed: DisplayResolutionMode, deadline: ContinuousClock.Instant) {
        self.id = id; self.displayName = displayName; self.original = original; self.proposed = proposed; self.deadline = deadline
    }
}

/// Reversion never silently overwrites a newer mode selected outside this preview.
public enum DisplayResolutionRevertOutcome: Equatable, Sendable {
    case restored
    case alreadyOriginal
    case noPendingChange
    case superseded
}

/// Content-free failures suitable for explicit recovery UI; raw OS diagnostics are not logged.
public enum DisplayResolutionError: Error, Equatable, Sendable {
    case unavailable, tooManyDisplays, staleSelection, unsupportedDisplay, unsafeMode, busy
    case disconnected, configurationChanged, modeUnavailable, applyFailed, modeSubstituted
    case keepFailed, revertFailed, expired
}

/// A single-preview native controller. Initialization performs no discovery or configuration changes.
public protocol DisplayResolutionControlling: Sendable {
    func catalog() async throws -> DisplayResolutionCatalog
    func preview(_ selection: DisplayResolutionSelection, id: UUID, deadline: ContinuousClock.Instant) async throws -> DisplayResolutionPreview
    func validatePreview(id: UUID) async throws
    func keepPreview(id: UUID) async throws
    func revertPreview(id: UUID) async throws -> DisplayResolutionRevertOutcome
}
