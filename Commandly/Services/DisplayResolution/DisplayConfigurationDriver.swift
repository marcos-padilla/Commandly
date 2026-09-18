import Foundation

/// Complete mode identity: equal logical sizes are not interchangeable modes.
nonisolated struct DisplayModeFingerprint: Equatable, Hashable, Sendable {
    let ioID: Int32
    let width: Int
    let height: Int
    let pixelWidth: Int
    let pixelHeight: Int
    let refreshRate: Double
    let flags: UInt32
    let isUsable: Bool
    var canPreview: Bool { isUsable && width >= 640 && height >= 480 }
}

/// These identifiers never escape the adapter/service boundary or enter persistence and logs.
nonisolated struct DisplayHardwareIdentity: Equatable, Hashable, Sendable {
    let displayID: UInt32
    let uuid: String
    let vendor: UInt32
    let model: UInt32
    let serial: UInt32
}

nonisolated struct DisplayHardwareRecord: Equatable, Sendable {
    let identity: DisplayHardwareIdentity
    let name: String
    let isActive: Bool
    let isMirrored: Bool
    let originX: Int
    let originY: Int
    let current: DisplayModeFingerprint
    let modes: [DisplayModeFingerprint]
    let modesAreTruncated: Bool
}

nonisolated struct DisplayHardwareSnapshot: Equatable, Sendable {
    let displays: [DisplayHardwareRecord]
    func display(_ identity: DisplayHardwareIdentity) -> DisplayHardwareRecord? {
        displays.first { $0.identity == identity }
    }
    /// Display names are UI labels and are not mutation authority.
    func hasSameConfiguration(as other: Self) -> Bool {
        guard displays.count == other.displays.count else { return false }
        return displays.allSatisfy { display in
            guard let current = other.display(display.identity) else { return false }
            return display.isActive == current.isActive && display.isMirrored == current.isMirrored
                && display.originX == current.originX && display.originY == current.originY
                && display.current == current.current && Set(display.modes) == Set(current.modes)
        }
    }
}

nonisolated enum DisplayConfigurationScope: Equatable, Sendable { case appLifetime, loginSession }

nonisolated struct DisplayConfigurationChange: Sendable {
    let display: DisplayHardwareIdentity
    let expected: DisplayHardwareSnapshot
    let mode: DisplayModeFingerprint
    let scope: DisplayConfigurationScope
    let deadline: ContinuousClock.Instant?
}

/// Native CG objects remain inside the driver actor; tests use value-only generated hardware.
nonisolated protocol DisplayConfigurationDriving: Sendable {
    func snapshot() async throws -> DisplayHardwareSnapshot
    func configure(_ change: DisplayConfigurationChange) async throws -> DisplayHardwareSnapshot
}
