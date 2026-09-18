import AppCore
import Foundation
import Infrastructure

/// Serializes one reversible preview. The UI gets scoped tokens, never CG handles or hardware IDs.
actor DisplayResolutionService {
    private struct CatalogRecord {
        let value: DisplayResolutionCatalog
        let hardware: DisplayHardwareSnapshot
        let displayIDs: [UUID: DisplayHardwareIdentity]
        let modeIDs: [UUID: DisplayModeFingerprint]
    }
    private struct Pending {
        let preview: DisplayResolutionPreview
        let display: DisplayHardwareIdentity
        let original: DisplayModeFingerprint
        let requested: DisplayModeFingerprint
        var expected: DisplayHardwareSnapshot
        var expectedMode: DisplayModeFingerprint
        var revertScope: DisplayConfigurationScope
    }
    private let driver: any DisplayConfigurationDriving
    private let clock: any AppCore.Clock
    private var cached: CatalogRecord?
    private var pending: Pending?
    private var isMutating = false
    init(driver: any DisplayConfigurationDriving, clock: any AppCore.Clock = ContinuousSystemClock()) {
        self.driver = driver; self.clock = clock
    }

    func catalog() async throws -> DisplayResolutionCatalog {
        guard isMutating == false, pending == nil else { throw DisplayResolutionError.busy }
        isMutating = true
        defer { isMutating = false }
        let hardware = try await driver.snapshot()
        try Task.checkCancellation()
        var displayIDs: [UUID: DisplayHardwareIdentity] = [:]
        var modeIDs: [UUID: DisplayModeFingerprint] = [:]
        let displays = hardware.displays.map { display in
            let id = UUID(); displayIDs[id] = display.identity
            var currentID = UUID()
            let modes = display.modes.map { mode in
                let value = Self.mode(mode)
                modeIDs[value.id] = mode
                if mode == display.current { currentID = value.id }
                return value
            }
            return ResolutionDisplay(id: id, name: display.name, currentModeID: currentID, modes: modes,
                unavailableReason: display.isMirrored ? "Mirrored displays must be configured in Displays Settings."
                    : display.isActive == false ? "This display is connected but is not active." : nil,
                modesAreTruncated: display.modesAreTruncated)
        }
        let value = DisplayResolutionCatalog(displays: displays)
        cached = CatalogRecord(value: value, hardware: hardware, displayIDs: displayIDs, modeIDs: modeIDs)
        return value
    }

    func preview(_ selection: DisplayResolutionSelection, id: UUID, deadline: ContinuousClock.Instant) async throws -> DisplayResolutionPreview {
        guard isMutating == false, pending == nil else { throw DisplayResolutionError.busy }
        guard let cached, cached.value.id == selection.catalogID,
              let identity = cached.displayIDs[selection.displayID], let target = cached.modeIDs[selection.modeID],
              let display = cached.hardware.display(identity), display.modes.contains(target),
              let uiDisplay = cached.value.displays.first(where: { $0.id == selection.displayID }),
              let uiMode = uiDisplay.modes.first(where: { $0.id == selection.modeID }) else { throw DisplayResolutionError.staleSelection }
        guard display.isActive, display.isMirrored == false else { throw DisplayResolutionError.unsupportedDisplay }
        guard target.canPreview else { throw DisplayResolutionError.unsafeMode }
        guard target != display.current else { throw DisplayResolutionError.staleSelection }
        guard clock.monotonicTime() < deadline else { throw DisplayResolutionError.expired }
        isMutating = true
        defer { isMutating = false; self.cached = nil }
        let current = try await driver.snapshot()
        try Task.checkCancellation()
        guard cached.hardware.hasSameConfiguration(as: current) else { throw DisplayResolutionError.staleSelection }
        let preview = DisplayResolutionPreview(id: id, displayName: display.name, original: Self.mode(display.current),
            proposed: uiMode, deadline: deadline)
        pending = Pending(preview: preview, display: identity, original: display.current, requested: target,
            expected: current, expectedMode: target, revertScope: .appLifetime)
        // Retain recovery authority before the write. Cancellation of its caller cannot discard it.
        let changed = try await driver.configure(.init(display: identity, expected: current, mode: target,
            scope: .appLifetime, deadline: deadline))
        if let actual = changed.display(identity)?.current {
            pending?.expected = changed; pending?.expectedMode = actual
        }
        guard changed.display(identity)?.current == target else { throw DisplayResolutionError.modeSubstituted }
        guard Self.sameDisplayConnections(current, changed), Self.otherModesUnchanged(before: current, after: changed, excluding: identity) else {
            throw DisplayResolutionError.configurationChanged
        }
        return preview
    }

    func validatePreview(id: UUID) async throws {
        guard let expected = pending, expected.preview.id == id, isMutating == false else { throw DisplayResolutionError.busy }
        let current = try await driver.snapshot()
        guard pending?.preview.id == id, current.hasSameConfiguration(as: expected.expected) else { throw DisplayResolutionError.configurationChanged }
    }

    func keepPreview(id: UUID) async throws {
        guard isMutating == false, let expected = pending, expected.preview.id == id else { throw DisplayResolutionError.busy }
        guard clock.monotonicTime() < expected.preview.deadline else { throw DisplayResolutionError.expired }
        isMutating = true
        defer { isMutating = false }
        let current = try await driver.snapshot()
        guard current.hasSameConfiguration(as: expected.expected), current.display(expected.display)?.current == expected.requested else {
            throw DisplayResolutionError.configurationChanged
        }
        // Once a session promotion is attempted, recovery must undo that possible promotion too.
        // An app-only rollback could otherwise expose the failed session choice again at quit.
        pending?.revertScope = .loginSession
        let kept = try await driver.configure(.init(display: expected.display, expected: current, mode: expected.requested,
            scope: .loginSession, deadline: expected.preview.deadline))
        if let actual = kept.display(expected.display)?.current { pending?.expected = kept; pending?.expectedMode = actual }
        guard kept.display(expected.display)?.current == expected.requested,
              Self.sameDisplayConnections(current, kept),
              Self.otherModesUnchanged(before: current, after: kept, excluding: expected.display) else {
            throw DisplayResolutionError.keepFailed
        }
        pending = nil
    }

    func revertPreview(id: UUID) async throws -> DisplayResolutionRevertOutcome {
        guard isMutating == false else { throw DisplayResolutionError.busy }
        guard let expected = pending else { return .noPendingChange }
        guard expected.preview.id == id else { throw DisplayResolutionError.staleSelection }
        isMutating = true
        defer { isMutating = false; cached = nil }
        let current = try await driver.snapshot()
        guard let display = current.display(expected.display) else { throw DisplayResolutionError.disconnected }
        if display.current == expected.original { pending = nil; return .alreadyOriginal }
        guard display.current == expected.expectedMode else {
            pending = nil
            return .superseded
        }
        guard display.isActive, display.isMirrored == false else { throw DisplayResolutionError.unsupportedDisplay }
        guard display.modes.contains(expected.original) else { throw DisplayResolutionError.modeUnavailable }
        // Revalidate against fresh topology, preserving any newly connected display and its mode.
        let restored = try await driver.configure(.init(display: expected.display, expected: current, mode: expected.original,
            scope: expected.revertScope, deadline: nil))
        if let actual = restored.display(expected.display)?.current { pending?.expected = restored; pending?.expectedMode = actual }
        guard restored.display(expected.display)?.current == expected.original else { throw DisplayResolutionError.revertFailed }
        pending = nil
        return .restored
    }

    private static func mode(_ value: DisplayModeFingerprint) -> DisplayResolutionMode {
        .init(logicalWidth: value.width, logicalHeight: value.height, pixelWidth: value.pixelWidth,
            pixelHeight: value.pixelHeight, refreshRate: value.refreshRate > 0 ? value.refreshRate : nil,
            canPreview: value.canPreview)
    }
    private static func sameDisplayConnections(_ a: DisplayHardwareSnapshot, _ b: DisplayHardwareSnapshot) -> Bool {
        Set(a.displays.map(\.identity)) == Set(b.displays.map(\.identity))
    }
    private static func otherModesUnchanged(before: DisplayHardwareSnapshot, after: DisplayHardwareSnapshot,
                                            excluding identity: DisplayHardwareIdentity) -> Bool {
        before.displays.filter { $0.identity != identity }.allSatisfy { display in
            guard let current = after.display(display.identity) else { return false }
            return display.current == current.current && display.isMirrored == current.isMirrored && display.isActive == current.isActive
        }
    }
}

extension DisplayResolutionService: DisplayResolutionControlling {}
