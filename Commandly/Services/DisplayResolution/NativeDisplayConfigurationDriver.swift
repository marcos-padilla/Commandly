import AppCore
import AppKit
import ColorSync
import CoreGraphics
import Foundation
import Infrastructure

/// Public CG configuration calls and all non-Sendable mode objects stay on this actor's executor.
/// Construction is inert. No display capture, global restore, shell, or permanent configuration API is used.
actor NativeDisplayConfigurationDriver {
    private let clock: any AppCore.Clock
    private var names: [UInt32: String] = [:]
    init(clock: any AppCore.Clock = ContinuousSystemClock()) { self.clock = clock }

    func snapshot() async throws -> DisplayHardwareSnapshot {
        try Task.checkCancellation()
        names = await MainActor.run {
            var result: [UInt32: String] = [:]
            for screen in NSScreen.screens {
                if let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
                    result[number.uint32Value] = screen.localizedName
                }
            }
            return result
        }
        try Task.checkCancellation()
        return try capture().snapshot
    }

    func configure(_ change: DisplayConfigurationChange) throws -> DisplayHardwareSnapshot {
        try Task.checkCancellation()
        if let deadline = change.deadline, clock.monotonicTime() >= deadline { throw DisplayResolutionError.expired }
        let current = try capture()
        guard current.snapshot.hasSameConfiguration(as: change.expected) else { throw DisplayResolutionError.configurationChanged }
        guard let display = current.snapshot.display(change.display), display.isActive, display.isMirrored == false else {
            throw DisplayResolutionError.unsupportedDisplay
        }
        guard let mode = current.modes[change.display]?[change.mode] else { throw DisplayResolutionError.modeUnavailable }
        var configuration: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&configuration) == .success, let configuration else { throw DisplayResolutionError.applyFailed }
        let configured = CGConfigureDisplayWithDisplayMode(configuration, change.display.displayID, mode, nil)
        guard configured == .success else {
            guard CGCancelDisplayConfiguration(configuration) == .success else { throw DisplayResolutionError.revertFailed }
            throw DisplayResolutionError.applyFailed
        }
        if let deadline = change.deadline, clock.monotonicTime() >= deadline {
            guard CGCancelDisplayConfiguration(configuration) == .success else { throw DisplayResolutionError.revertFailed }
            throw DisplayResolutionError.expired
        }
        // Complete consumes the configuration even if it fails. Cancel is valid only before this call.
        let scope: CGConfigureOption = change.scope == .appLifetime ? .forAppOnly : .forSession
        guard CGCompleteDisplayConfiguration(configuration, scope) == .success else { throw DisplayResolutionError.applyFailed }
        return try capture().snapshot
    }

    private struct Capture {
        let snapshot: DisplayHardwareSnapshot
        let modes: [DisplayHardwareIdentity: [DisplayModeFingerprint: CGDisplayMode]]
    }

    private func capture() throws -> Capture {
        var ids = [CGDirectDisplayID](repeating: 0, count: 64)
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(UInt32(ids.count), &ids, &count) == .success else { throw DisplayResolutionError.unavailable }
        guard count < ids.count else { throw DisplayResolutionError.tooManyDisplays }
        var records: [DisplayHardwareRecord] = []
        var handles: [DisplayHardwareIdentity: [DisplayModeFingerprint: CGDisplayMode]] = [:]
        for (index, id) in ids.prefix(Int(count)).sorted().enumerated() {
            guard let currentMode = CGDisplayCopyDisplayMode(id),
                  let modes = CGDisplayCopyAllDisplayModes(id,
                    [kCGDisplayShowDuplicateLowResolutionModes: true] as CFDictionary) as? [CGDisplayMode] else {
                throw DisplayResolutionError.unavailable
            }
            let uuid = CGDisplayCreateUUIDFromDisplayID(id).takeRetainedValue()
            let identity = DisplayHardwareIdentity(displayID: id, uuid: CFUUIDCreateString(nil, uuid) as String,
                vendor: CGDisplayVendorNumber(id), model: CGDisplayModelNumber(id), serial: CGDisplaySerialNumber(id))
            let current = try fingerprint(currentMode)
            var values: [DisplayModeFingerprint: CGDisplayMode] = [:]
            for mode in modes where mode.isUsableForDesktopGUI() {
                let key = try fingerprint(mode)
                if values.count < 512 || values[key] != nil { values[key] = mode }
            }
            values[current] = currentMode
            let bounds = CGDisplayBounds(id)
            guard bounds.origin.x.isFinite, bounds.origin.y.isFinite,
                  abs(bounds.origin.x) <= CGFloat(Int32.max), abs(bounds.origin.y) <= CGFloat(Int32.max) else {
                throw DisplayResolutionError.unavailable
            }
            let name = names[id] ?? (CGDisplayIsBuiltin(id) != 0 ? "Built-in Display" : "External Display \(index + 1)")
            records.append(.init(identity: identity, name: name, isActive: CGDisplayIsActive(id) != 0,
                isMirrored: CGDisplayIsInMirrorSet(id) != 0, originX: Int(bounds.origin.x), originY: Int(bounds.origin.y),
                current: current, modes: values.keys.sorted(by: Self.modeOrder), modesAreTruncated: modes.count > 512))
            handles[identity] = values
        }
        return Capture(snapshot: .init(displays: records), modes: handles)
    }

    private func fingerprint(_ mode: CGDisplayMode) throws -> DisplayModeFingerprint {
        let refresh = mode.refreshRate
        guard refresh.isFinite, refresh >= 0, refresh < 10_000,
              mode.width > 0, mode.height > 0, mode.pixelWidth > 0, mode.pixelHeight > 0,
              max(mode.width, mode.height, mode.pixelWidth, mode.pixelHeight) <= 65_536 else {
            throw DisplayResolutionError.unavailable
        }
        return .init(ioID: mode.ioDisplayModeID, width: mode.width, height: mode.height,
            pixelWidth: mode.pixelWidth, pixelHeight: mode.pixelHeight, refreshRate: refresh,
            flags: mode.ioFlags, isUsable: mode.isUsableForDesktopGUI())
    }

    private static func modeOrder(_ left: DisplayModeFingerprint, _ right: DisplayModeFingerprint) -> Bool {
        if left.width != right.width { return left.width < right.width }
        if left.height != right.height { return left.height < right.height }
        if left.pixelWidth != right.pixelWidth { return left.pixelWidth < right.pixelWidth }
        if left.pixelHeight != right.pixelHeight { return left.pixelHeight < right.pixelHeight }
        if left.refreshRate != right.refreshRate { return left.refreshRate < right.refreshRate }
        return left.ioID < right.ioID
    }
}

extension NativeDisplayConfigurationDriver: DisplayConfigurationDriving {}
