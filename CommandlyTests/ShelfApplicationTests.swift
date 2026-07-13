import AppKit
import CommandKit
import DesignSystem
import Foundation
import Infrastructure
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
        let empty = ShelfBoardModel(
            entryMode: .empty,
            services: makeShelfTestServices(),
            onClose: {}
        )
        let clipboard = ShelfBoardModel(
            entryMode: .fromClipboard,
            services: makeShelfTestServices(),
            onClose: {}
        )
        #expect(empty.accessibilityLabel == "Shelf")
        #expect(clipboard.accessibilityLabel == "Shelf from Clipboard")
    }

    @Test @MainActor func preferredCornerResolvesConfiguredAndDefaultValues() {
        #expect(ShelfPreferredCorner.resolve("topLeft") == .topLeft)
        #expect(ShelfPreferredCorner.resolve("unknown") == .bottomRight)
        #expect(ShelfPreferredCorner.resolve(nil) == .bottomRight)
    }

    @Test @MainActor func shelfWindowUsesOnlyItsExplicitDragHandleAndCustomShadow() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 188, height: 188),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        var placeIfNeeded = false

        ShelfWindowConfigurator.applyChrome(
            to: window,
            preferredCorner: .bottomRight,
            keepVisibleWhenInactive: true,
            placeIfNeeded: &placeIfNeeded
        )

        #expect(window.isMovable)
        #expect(window.isMovableByWindowBackground == false)
        #expect(window.hasShadow == false)
        #expect(window.contentView?.wantsLayer == true)
        #expect(
            window.contentView?.layer?.cornerRadius
                == LayoutConstants.shelfCornerRadius
        )
        #expect(window.contentView?.layer?.cornerCurve == .continuous)
        #expect(window.contentView?.layer?.masksToBounds == true)

        let dragRegion = ShelfWindowDragRegionView(frame: .zero)
        #expect(dragRegion.acceptsFirstMouse(for: nil))
        #expect(dragRegion.mouseDownCanMoveWindow == false)
    }

    @Test @MainActor func shelfDragHandleDelegatesMovementToItsWindow() throws {
        let window = RecordingShelfDragWindow(
            contentRect: NSRect(x: 0, y: 0, width: 188, height: 188),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        let dragRegion = ShelfWindowDragRegionView(frame: window.contentLayoutRect)
        window.contentView = dragRegion
        let event = try #require(NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: NSPoint(x: 36, y: 13),
            modifierFlags: [],
            timestamp: 0,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 1,
            clickCount: 1,
            pressure: 1
        ))

        dragRegion.mouseDown(with: event)

        #expect(window.didPerformDrag)
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

@MainActor
private final class RecordingShelfDragWindow: NSWindow {
    private(set) var didPerformDrag = false

    override func performDrag(with event: NSEvent) {
        didPerformDrag = true
    }
}

@MainActor
private func makeShelfTestServices() -> ShelfApplicationServices {
    ShelfApplicationServices(
        metadataReader: InMemoryFileResourceMetadataReader(),
        fileActions: InMemoryFileCollectionActionService(),
        fileRevealer: InMemoryFileRevealer(),
        urlOpener: NoOpURLOpener(),
        pasteboard: InMemoryPasteboard(),
        previewPresenter: InMemoryFilePreviewPresenter(),
        dropFeedback: NoOpShelfDropFeedbackPlayer()
    )
}
