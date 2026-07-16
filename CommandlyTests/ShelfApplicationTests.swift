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
            "clearWhenEmpty",
            "preferredCorner",
            "playDropSound"
        ])
        #expect(
            definition?.configurationFields
                .first { $0.variable == "preferredCorner" }?
                .defaultValue == .text(ShelfPreferredCorner.topRight.rawValue)
        )
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
        #expect(ShelfPreferredCorner.resolve("bottomRight") == .bottomRight)
        #expect(ShelfPreferredCorner.resolve("unknown") == .topRight)
        #expect(ShelfPreferredCorner.resolve(nil) == .topRight)
        #expect(ShelfConfiguration.default.preferredCorner == .topRight)
    }

    @Test @MainActor func shelfWindowDefaultsToTopRightOfCapturedScreen() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 40, height: 40),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        let visibleFrame = NSRect(x: -1_800, y: 40, width: 1_800, height: 1_000)
        let target = WindowPresentationTarget(visibleFrame: visibleFrame)

        ShelfWindowConfigurator.place(
            window,
            in: ShelfPreferredCorner.defaultValue,
            screenTarget: target
        )

        let expectedOrigin = NSPoint(
            x: visibleFrame.maxX
                - LayoutConstants.shelfBoardSize
                - LayoutConstants.shelfScreenMargin,
            y: visibleFrame.maxY
                - LayoutConstants.shelfBoardSize
                - LayoutConstants.shelfScreenMargin
        )
        #expect(window.frame.origin == expectedOrigin)
        #expect(window.frame.maxX == visibleFrame.maxX - LayoutConstants.shelfScreenMargin)
        #expect(window.frame.maxY == visibleFrame.maxY - LayoutConstants.shelfScreenMargin)
    }

    @Test @MainActor func presentationRequestsAdvanceForRepeatedOpensAndCaptureTheirScreen() {
        let firstTarget = WindowPresentationTarget(
            visibleFrame: CGRect(x: -1_728, y: 25, width: 1_728, height: 1_080)
        )
        let secondTarget = WindowPresentationTarget(
            visibleFrame: CGRect(x: 0, y: 25, width: 1_512, height: 982)
        )

        let first = ShelfPresentationRequest.initial.next(
            entryMode: .empty,
            screenTarget: firstTarget
        )
        let repeated = first.next(
            entryMode: .empty,
            screenTarget: secondTarget
        )
        let clipboard = repeated.next(
            entryMode: .fromClipboard,
            screenTarget: firstTarget
        )

        #expect(first.generation == 1)
        #expect(first.entryMode == .empty)
        #expect(first.screenTarget == firstTarget)
        #expect(repeated.generation == 2)
        #expect(repeated.entryMode == .empty)
        #expect(repeated.screenTarget == secondTarget)
        #expect(clipboard.generation == 3)
        #expect(clipboard.entryMode == .fromClipboard)
        #expect(clipboard.screenTarget == firstTarget)
    }

    @Test @MainActor func globalShelfShortcutsMapToTheirCommandsHotKeysAndEntryModes() {
        let newShelf = ShelfGlobalShortcut.newShelf
        let fromClipboard = ShelfGlobalShortcut.newShelfFromClipboard

        #expect(newShelf.commandID == CommandID(rawValue: "shelf.shortcut.new"))
        #expect(
            newShelf.hotKey
                == LauncherHotKey(keyCode: 49, modifiers: [.option, .shift])
        )
        #expect(newShelf.entryMode == .empty)
        #expect(ShelfGlobalShortcut.resolve(newShelf.commandID)?.entryMode == .empty)

        #expect(
            fromClipboard.commandID
                == CommandID(rawValue: "shelf.shortcut.clipboard")
        )
        #expect(
            fromClipboard.hotKey
                == LauncherHotKey(keyCode: 0, modifiers: [.option, .shift])
        )
        #expect(fromClipboard.entryMode == .fromClipboard)
        #expect(
            ShelfGlobalShortcut.resolve(fromClipboard.commandID)?.entryMode
                == .fromClipboard
        )
        #expect(
            ShelfGlobalShortcut.resolve(CommandID(rawValue: "unrelated.command")) == nil
        )
    }

    @Test @MainActor func shelfWindowPlacesOnCapturedNegativeOriginScreen() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 40, height: 40),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        let visibleFrame = NSRect(x: -1_800, y: 40, width: 1_800, height: 1_000)
        let target = WindowPresentationTarget(visibleFrame: visibleFrame)

        ShelfWindowConfigurator.place(
            window,
            in: .topLeft,
            screenTarget: target
        )

        let expectedOrigin = NSPoint(
            x: visibleFrame.minX + LayoutConstants.shelfScreenMargin,
            y: visibleFrame.maxY
                - LayoutConstants.shelfBoardSize
                - LayoutConstants.shelfScreenMargin
        )
        #expect(window.frame.origin == expectedOrigin)
        #expect(
            window.frame.size
                == NSSize(
                    width: LayoutConstants.shelfBoardSize,
                    height: LayoutConstants.shelfBoardSize
                )
        )
        #expect(window.frame.maxX <= visibleFrame.maxX)
    }

    @Test @MainActor func shelfWindowKeepsBackgroundDragDisabledAndMasksCorners() {
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
            screenTarget: nil,
            placeIfNeeded: &placeIfNeeded
        )

        #expect(window.isMovable)
        #expect(window.isMovableByWindowBackground == false)
        #expect(window.hidesOnDeactivate == false)
        #expect(window.hasShadow == false)
        #expect(window.contentView?.wantsLayer == true)
        #expect(
            window.contentView?.layer?.cornerRadius
                == LayoutConstants.shelfCornerRadius
        )
        #expect(window.contentView?.layer?.cornerCurve == .continuous)
        #expect(window.contentView?.layer?.masksToBounds == true)
        #expect(
            window.collectionBehavior
                == ActiveSpaceWindowPresenter.overlayCollectionBehavior
        )
        #expect(window.collectionBehavior.contains(.moveToActiveSpace) == false)
        #expect(window.collectionBehavior.contains(.canJoinAllApplications))
        #expect(window.collectionBehavior.contains(.canJoinAllSpaces))
        #expect(window.collectionBehavior.contains(.fullScreenPrimary) == false)
        #expect(window.collectionBehavior.contains(.primary) == false)

        let dragRegion = ShelfWindowDragRegionView(frame: .zero)
        #expect(dragRegion.acceptsFirstMouse(for: nil))
        #expect(dragRegion.mouseDownCanMoveWindow == false)
    }

    @Test @MainActor func shelfCoordinatorSurvivesReentrantStyleMaskAttachment() throws {
        let target = WindowPresentationTarget(
            visibleFrame: CGRect(x: 0, y: 25, width: 1_512, height: 982)
        )
        let request = ShelfPresentationRequest.initial.next(
            entryMode: .empty,
            screenTarget: target
        )
        let newerTarget = WindowPresentationTarget(
            visibleFrame: CGRect(x: -1_900, y: 30, width: 1_900, height: 1_050)
        )
        let newerRequest = request.next(
            entryMode: .fromClipboard,
            screenTarget: newerTarget
        )
        let coordinator = ShelfWindowConfigurator.Coordinator(
            preferredCorner: .topLeft,
            presentationRequest: request,
            interaction: ShelfBoardInteractionState(),
            onEscape: { false },
            onKeyDown: { _ in false }
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 188, height: 188),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        let contentView = try #require(window.contentView)
        let probe = WindowAttachmentProbeView(frame: .zero)
        var attachmentCount = 0
        var attachmentDepth = 0
        var maximumAttachmentDepth = 0
        probe.onWindowAttached = { attachedWindow in
            attachmentCount += 1
            attachmentDepth += 1
            maximumAttachmentDepth = max(maximumAttachmentDepth, attachmentDepth)
            if attachmentCount == 2 {
                coordinator.updatePresentationRequest(newerRequest)
            }
            coordinator.attach(to: attachedWindow)
            attachmentDepth -= 1
        }
        defer {
            probe.onWindowAttached = nil
            coordinator.tearDown()
            probe.removeFromSuperview()
            window.orderOut(nil)
        }

        contentView.addSubview(probe)

        #expect(attachmentCount >= 2)
        #expect(maximumAttachmentDepth >= 2)
        #expect(coordinator.presentationRequest == newerRequest)
        #expect(window.identifier == CommandlyWindowIdentifier.shelf)
        #expect(window.styleMask.contains(.borderless))
        #expect(window.styleMask.contains(.fullSizeContentView))
        #expect(window.styleMask.contains(.titled) == false)
        #expect(window.collectionBehavior == ActiveSpaceWindowPresenter.overlayCollectionBehavior)
        #expect(
            window.frame.size
                == NSSize(
                    width: LayoutConstants.shelfBoardSize,
                    height: LayoutConstants.shelfBoardSize
                )
        )
        #expect(window.frame.minX == newerTarget.visibleFrame.minX + LayoutConstants.shelfScreenMargin)
        #expect(
            window.frame.maxY
                == newerTarget.visibleFrame.maxY - LayoutConstants.shelfScreenMargin
        )
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
        dropFeedback: NoOpShelfDropFeedbackPlayer(),
        makeTemporaryContentStore: {
            InMemoryShelfTemporaryContentStore()
        }
    )
}
