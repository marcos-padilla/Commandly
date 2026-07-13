import CoreGraphics
import CommandKit
import Foundation
import Testing
@testable import Commandly

struct WindowLayoutsApplicationTests {
    @Test @MainActor func catalogContainsExactlyFiftyEightUniqueValidPresets() {
        let presets = WindowLayoutCatalog.presets

        #expect(presets.count == 58)
        #expect(Set(presets.map(\.id)).count == presets.count)
        #expect(presets.allSatisfy { $0.rect.isValid })
        #expect(presets.contains { $0.id == "left-half" })
        #expect(presets.contains { $0.id == "maximize" })
    }

    @Test @MainActor func normalizedLayoutUsesTheDisplaysVisibleFrame() {
        let frame = AccessibilityWindowLayoutService.appKitFrame(
            for: NormalizedWindowRect(x: 0, y: 0, width: 0.5, height: 1),
            visibleFrame: CGRect(x: 100, y: 40, width: 1_200, height: 800)
        )

        #expect(frame == CGRect(x: 100, y: 40, width: 600, height: 800))
    }

    @Test @MainActor func targetTrackerPreservesTheAppActiveBeforeCommandly() {
        let frontmostProcessIdentifier = WindowLayoutProcessIdentifierBox(value: 101)
        let tracker = WindowLayoutTargetTracker(
            commandlyProcessIdentifier: 999,
            frontmostProcessIdentifier: { frontmostProcessIdentifier.value }
        )

        #expect(tracker.targetProcessIdentifier() == 101)

        frontmostProcessIdentifier.value = 999
        #expect(tracker.targetProcessIdentifier() == 101)

        frontmostProcessIdentifier.value = 202
        #expect(tracker.targetProcessIdentifier() == 202)
    }

    @Test @MainActor func modelAppliesPresetsAndPersistsCustomLayouts() async throws {
        let service = InMemoryWindowLayoutService()
        let store = InMemoryCustomWindowLayoutStore()
        let id = try #require(UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"))
        let model = WindowLayoutsViewModel(
            service: service,
            customStore: store,
            uuidProvider: { id },
            onGoBack: {}
        )

        model.select("left-half")
        model.applySelected()
        await model.flushApplyForTesting()

        #expect(service.applied == [
            NormalizedWindowRect(x: 0, y: 0, width: 0.5, height: 1)
        ])
        #expect(model.statusMessage == "Applied Left Half.")

        model.beginCustomEditor()
        model.customTitle = "Writing"
        model.customX = 0.1
        model.customY = 0.2
        model.customWidth = 0.6
        model.customHeight = 0.7
        model.saveCustom()

        #expect(try store.load().count == 1)
        #expect(try store.load().first?.id == id)
        #expect(model.source == .custom)
        #expect(model.selectedPreset?.title == "Writing")

        model.perform(BuiltInCommandActionID.delete)
        #expect(try store.load().isEmpty)
    }

    @Test @MainActor func modelDoesNotReportSuccessWhenCustomLayoutPersistenceFails() {
        let store = FailingCustomWindowLayoutStore()
        let model = WindowLayoutsViewModel(
            service: InMemoryWindowLayoutService(),
            customStore: store,
            onGoBack: {}
        )

        model.beginCustomEditor()
        model.customTitle = "Writing"
        model.saveCustom()

        #expect(model.statusMessage == CustomWindowLayoutStoreError.saveFailed.errorDescription)
        #expect(model.isEditingCustom)
    }

    @Test @MainActor func userDefaultsStoreReportsCorruptSavedLayouts() throws {
        let suiteName = "CommandlyTests.WindowLayouts.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let key = "custom-layouts"
        defaults.set(Data([0xFF, 0x00]), forKey: key)
        let store = UserDefaultsCustomWindowLayoutStore(defaults: defaults, key: key)

        do {
            _ = try store.load()
            Issue.record("Expected corrupt custom-layout data to be reported")
        } catch let error as CustomWindowLayoutStoreError {
            #expect(error == .unreadable)
        }
    }
}

@MainActor
private final class WindowLayoutProcessIdentifierBox {
    var value: pid_t?

    init(value: pid_t?) {
        self.value = value
    }
}

@MainActor
private final class FailingCustomWindowLayoutStore: CustomWindowLayoutStoring {
    func load() throws -> [CustomWindowLayout] { [] }

    func save(_ layout: CustomWindowLayout) throws {
        throw CustomWindowLayoutStoreError.saveFailed
    }

    func delete(id: UUID) throws {
        throw CustomWindowLayoutStoreError.saveFailed
    }
}
