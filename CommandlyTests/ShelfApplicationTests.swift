import CommandKit
import Foundation
import Testing
@testable import Commandly

struct ShelfApplicationTests {
    @Test @MainActor func registersManifestDocumentationAndConfigurationFields() {
        let registry = LauncherApplicationRegistry.makeBuiltIn()
        let definition = registry.definition(for: ShelfApplication.applicationID)

        #expect(definition != nil)
        #expect(definition?.kind == .application)
        #expect(definition?.commandManifest?.title == "Shelf")
        #expect(definition?.commandManifest?.mode == .action)
        #expect(definition?.documentation != nil)
        #expect(definition?.configurationFields.map(\.variable) == [
            "keepVisibleWhenInactive",
            "clearWhenEmpty",
            "preferredCorner",
            "playDropSound"
        ])
        #expect(registry.application(for: ShelfApplication.applicationID) != nil)
        #expect(
            registry.allManifests().contains { $0.id == ShelfApplication.applicationID }
        )
    }

    @Test @MainActor func launchRequestsFloatingShelfAndDismissesLauncher() {
        let controller = ShelfLaunchController()
        var presentedModes: [ShelfEntryMode] = []
        controller.onPresent = { presentedModes.append($0) }
        let application = ShelfApplication(launchController: controller)
        let context = LauncherApplicationContext(
            navigation: LauncherApplicationNavigation(
                dismissLauncher: {},
                openSettings: {},
                goBack: {}
            ),
            settings: LauncherApplicationResolvedSettings(
                alias: "",
                hotKey: nil,
                isEnabled: true,
                configuration: [:]
            )
        )

        let launch = application.launch(in: context)
        guard case .dismiss = launch else {
            Issue.record("Expected ShelfApplication to dismiss the launcher after opening Shelf")
            return
        }
        #expect(presentedModes == [.empty])
    }

    @Test @MainActor func boardModelReportsAccessibilityLabelsPerEntryMode() {
        let empty = ShelfBoardModel(entryMode: .empty, onClose: {})
        let clipboard = ShelfBoardModel(entryMode: .fromClipboard, onClose: {})
        #expect(empty.accessibilityLabel == "Shelf")
        #expect(clipboard.accessibilityLabel == "Shelf from Clipboard")
    }

    @Test @MainActor func preferredCornerResolvesConfiguredAndDefaultValues() {
        #expect(ShelfPreferredCorner.resolve("topLeft") == .topLeft)
        #expect(ShelfPreferredCorner.resolve("unknown") == .bottomRight)
        #expect(ShelfPreferredCorner.resolve(nil) == .bottomRight)
    }

    @Test @MainActor func documentationCoversOpenSettingsAndCurrentLimits() throws {
        let documentation = RegisteredApplicationDocumentation.shelf
        #expect(documentation.category == .productivity)
        #expect(documentation.sections.map(\.id) == [
            "shelf.open",
            "shelf.settings",
            "shelf.limits"
        ])

        let limits = try #require(documentation.sections.first { $0.id == "shelf.limits" })
        #expect(limits.blocks.contains { block in
            if case .callout(let callout) = block.content {
                return callout.kind == .limitation
            }
            return false
        })
    }
}
