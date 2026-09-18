import Foundation
import Infrastructure
import Testing
@testable import Commandly

struct DisplayResolutionServiceTests {
    @Test func constructionIsInertAndModeIdentityDistinguishesPixelsAndRefresh() async throws {
        let driver = ResolutionTestDriver()
        let clock = ResolutionTestClock()
        let service = DisplayResolutionService(driver: driver, clock: clock)
        #expect(await driver.snapshotCount == 0)
        let catalog = try await service.catalog()
        let selection = try #require(ResolutionTestData.selection(catalog, pixelWidth: 1280))
        let id = UUID()
        _ = try await service.preview(selection, id: id, deadline: clock.monotonicTime().advanced(by: .seconds(15)))
        let previewWrites = await driver.changes
        #expect(previewWrites.count == 1 && previewWrites.first?.mode == ResolutionTestData.lowDensity)
        #expect(previewWrites.first?.scope == .appLifetime)
        try await service.keepPreview(id: id)
        let writes = await driver.changes
        #expect(writes.count == 2 && writes.last?.scope == .loginSession)
        #expect(try await service.revertPreview(id: id) == .noPendingChange)
    }

    @Test func refreshedOrChangedTopologyRejectsTheOldSelectionWithoutAnyWrite() async throws {
        let driver = ResolutionTestDriver()
        let clock = ResolutionTestClock()
        let service = DisplayResolutionService(driver: driver, clock: clock)
        let old = try await service.catalog()
        let oldSelection = try #require(ResolutionTestData.selection(old))
        _ = try await service.catalog()
        await #expect(throws: DisplayResolutionError.staleSelection) {
            try await service.preview(oldSelection, id: UUID(), deadline: clock.monotonicTime().advanced(by: .seconds(15)))
        }
        let current = try await service.catalog()
        let currentSelection = try #require(ResolutionTestData.selection(current))
        await driver.setHardware(ResolutionTestData.hardware(current: ResolutionTestData.fastRefresh))
        await #expect(throws: DisplayResolutionError.staleSelection) {
            try await service.preview(currentSelection, id: UUID(), deadline: clock.monotonicTime().advanced(by: .seconds(15)))
        }
        #expect(await driver.changes.isEmpty)
    }

    @Test func expiredKeepFailsAndRestorationUsesTheExactOriginal() async throws {
        let driver = ResolutionTestDriver()
        let clock = ResolutionTestClock()
        let service = DisplayResolutionService(driver: driver, clock: clock)
        let catalog = try await service.catalog()
        let selection = try #require(ResolutionTestData.selection(catalog, refreshRate: 75))
        let id = UUID()
        _ = try await service.preview(selection, id: id, deadline: clock.monotonicTime().advanced(by: .seconds(15)))
        clock.advance(seconds: 15)
        await #expect(throws: DisplayResolutionError.expired) { try await service.keepPreview(id: id) }
        #expect(try await service.revertPreview(id: id) == .restored)
        let writes = await driver.changes
        #expect(writes.last?.mode == ResolutionTestData.original && writes.last?.scope == .appLifetime)
    }

    @Test func aNativeSubstitutionIsRecoverableWithoutAcceptingItAsTheRequestedMode() async throws {
        let driver = ResolutionTestDriver()
        let clock = ResolutionTestClock()
        let service = DisplayResolutionService(driver: driver, clock: clock)
        let catalog = try await service.catalog()
        let selection = try #require(ResolutionTestData.selection(catalog))
        await driver.substituteNext(ResolutionTestData.lowDensity)
        let id = UUID()
        await #expect(throws: DisplayResolutionError.modeSubstituted) {
            try await service.preview(selection, id: id, deadline: clock.monotonicTime().advanced(by: .seconds(15)))
        }
        #expect(try await service.revertPreview(id: id) == .restored)
        #expect(await driver.hardware.display(ResolutionTestData.identity)?.current == ResolutionTestData.original)
    }

    @Test func aNewerExternalChoiceIsNeverOverwrittenByKeepOrRollback() async throws {
        let driver = ResolutionTestDriver()
        let clock = ResolutionTestClock()
        let service = DisplayResolutionService(driver: driver, clock: clock)
        let catalog = try await service.catalog()
        let selection = try #require(ResolutionTestData.selection(catalog))
        let id = UUID()
        _ = try await service.preview(selection, id: id, deadline: clock.monotonicTime().advanced(by: .seconds(15)))
        await driver.setHardware(ResolutionTestData.hardware(current: ResolutionTestData.fastRefresh))
        await #expect(throws: DisplayResolutionError.configurationChanged) { try await service.keepPreview(id: id) }
        #expect(try await service.revertPreview(id: id) == .superseded)
        #expect(await driver.changes.count == 1)
    }

    @Test func aDisconnectedOrReplacedDisplayRetainsRecoveryAndCannotReuseItsNumericID() async throws {
        let driver = ResolutionTestDriver()
        let clock = ResolutionTestClock()
        let service = DisplayResolutionService(driver: driver, clock: clock)
        let catalog = try await service.catalog()
        let selection = try #require(ResolutionTestData.selection(catalog))
        let id = UUID()
        _ = try await service.preview(selection, id: id, deadline: clock.monotonicTime().advanced(by: .seconds(15)))
        await driver.setHardware(.init(displays: []))
        await #expect(throws: DisplayResolutionError.disconnected) { try await service.revertPreview(id: id) }
        let replacement = DisplayHardwareIdentity(displayID: 11, uuid: "different-physical-display", vendor: 1, model: 2, serial: 3)
        await driver.setHardware(ResolutionTestData.hardware(current: ResolutionTestData.highDensity, identity: replacement))
        await #expect(throws: DisplayResolutionError.disconnected) { try await service.revertPreview(id: id) }
        #expect(await driver.changes.count == 1)
        await driver.setHardware(ResolutionTestData.hardware(current: ResolutionTestData.highDensity))
        #expect(try await service.revertPreview(id: id) == .restored)
    }

    @Test func failedRevertRetainsAuthorityAndCanBeRetried() async throws {
        let driver = ResolutionTestDriver()
        let clock = ResolutionTestClock()
        let service = DisplayResolutionService(driver: driver, clock: clock)
        let catalog = try await service.catalog()
        let selection = try #require(ResolutionTestData.selection(catalog))
        let id = UUID()
        _ = try await service.preview(selection, id: id, deadline: clock.monotonicTime().advanced(by: .seconds(15)))
        await driver.failNext(.revertFailed)
        await #expect(throws: DisplayResolutionError.revertFailed) { try await service.revertPreview(id: id) }
        #expect(try await service.revertPreview(id: id) == .restored)
    }

    @Test func failedSessionPromotionIsRolledBackAtSessionScope() async throws {
        let driver = ResolutionTestDriver()
        let clock = ResolutionTestClock()
        let service = DisplayResolutionService(driver: driver, clock: clock)
        let catalog = try await service.catalog()
        let selection = try #require(ResolutionTestData.selection(catalog))
        let id = UUID()
        _ = try await service.preview(selection, id: id, deadline: clock.monotonicTime().advanced(by: .seconds(15)))
        await driver.failNext(.keepFailed, afterMutation: true)
        await #expect(throws: DisplayResolutionError.keepFailed) { try await service.keepPreview(id: id) }
        #expect(try await service.revertPreview(id: id) == .restored)
        let writes = await driver.changes
        #expect(writes.last?.scope == .loginSession && writes.last?.mode == ResolutionTestData.original)
    }

    @Test func mirroredDisplaysCannotApply() async throws {
        let driver = ResolutionTestDriver(hardware: ResolutionTestData.hardware(isMirrored: true))
        let clock = ResolutionTestClock()
        let service = DisplayResolutionService(driver: driver, clock: clock)
        let catalog = try await service.catalog()
        let selection = try #require(ResolutionTestData.selection(catalog))
        await #expect(throws: DisplayResolutionError.unsupportedDisplay) {
            try await service.preview(selection, id: UUID(), deadline: clock.monotonicTime().advanced(by: .seconds(15)))
        }
        #expect(await driver.changes.isEmpty)
    }
}
