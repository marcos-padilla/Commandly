import AppKit
import SwiftUI

/// Places minimal sidebar navigation controls in AppKit's native titlebar lane.
///
/// AppKit positions the leading accessory immediately after the traffic-light
/// controls and keeps it stable as a custom SwiftUI sidebar changes width.
struct CommandlySidebarTitlebarAccessory: NSViewRepresentable {
    struct SupplementaryAction {
        let title: String
        let systemImage: String
        let accessibilityIdentifier: String
        let accessibilityHelp: String
        let onPerform: () -> Void
    }

    var isSidebarVisible: Bool
    let accessibilityIdentifier: String
    let navigationName: String
    var supplementaryAction: SupplementaryAction?
    var onToggleSidebar: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            isSidebarVisible: isSidebarVisible,
            accessibilityIdentifier: accessibilityIdentifier,
            navigationName: navigationName,
            supplementaryAction: supplementaryAction,
            onToggleSidebar: onToggleSidebar
        )
    }

    func makeNSView(context: Context) -> WindowAttachmentProbeView {
        let view = WindowAttachmentProbeView(frame: .zero)
        view.isHidden = true
        update(context.coordinator)
        installAttachmentCallback(on: view, coordinator: context.coordinator)
        view.attachIfPossible()
        return view
    }

    func updateNSView(_ nsView: WindowAttachmentProbeView, context: Context) {
        update(context.coordinator)
        installAttachmentCallback(on: nsView, coordinator: context.coordinator)
        nsView.attachIfPossible()
    }

    static func dismantleNSView(
        _ nsView: WindowAttachmentProbeView,
        coordinator: Coordinator
    ) {
        nsView.onWindowAttached = nil
        coordinator.tearDown()
    }

    private func update(_ coordinator: Coordinator) {
        coordinator.update(
            isSidebarVisible: isSidebarVisible,
            accessibilityIdentifier: accessibilityIdentifier,
            navigationName: navigationName,
            supplementaryAction: supplementaryAction,
            onToggleSidebar: onToggleSidebar
        )
    }

    private func installAttachmentCallback(
        on view: WindowAttachmentProbeView,
        coordinator: Coordinator
    ) {
        view.onWindowAttached = { [weak coordinator] window in
            coordinator?.attach(to: window)
        }
    }

    @MainActor
    final class Coordinator: NSObject {
        private static let singleActionWidth: CGFloat = 34
        private static let additionalActionWidth: CGFloat = 30
        private static let buttonSize = NSSize(width: 24, height: 22)

        private var isSidebarVisible: Bool
        private var accessibilityIdentifier: String
        private var navigationName: String
        private var supplementaryAction: SupplementaryAction?
        private var onToggleSidebar: () -> Void
        private weak var window: NSWindow?
        private var accessoryController: NSTitlebarAccessoryViewController?
        private weak var container: NSView?
        private weak var sidebarButton: NSButton?
        private weak var supplementaryButton: NSButton?

        init(
            isSidebarVisible: Bool,
            accessibilityIdentifier: String,
            navigationName: String,
            supplementaryAction: SupplementaryAction? = nil,
            onToggleSidebar: @escaping () -> Void
        ) {
            self.isSidebarVisible = isSidebarVisible
            self.accessibilityIdentifier = accessibilityIdentifier
            self.navigationName = navigationName
            self.supplementaryAction = supplementaryAction
            self.onToggleSidebar = onToggleSidebar
        }

        func update(
            isSidebarVisible: Bool,
            accessibilityIdentifier: String,
            navigationName: String,
            supplementaryAction: SupplementaryAction? = nil,
            onToggleSidebar: @escaping () -> Void
        ) {
            self.isSidebarVisible = isSidebarVisible
            self.accessibilityIdentifier = accessibilityIdentifier
            self.navigationName = navigationName
            self.supplementaryAction = supplementaryAction
            self.onToggleSidebar = onToggleSidebar
            updateControls()
        }

        func attach(to window: NSWindow) {
            if self.window !== window {
                removeAccessoryFromAttachedWindow()
                self.window = window
            }

            let accessoryController = accessoryController ?? makeAccessoryController()
            if window.titlebarAccessoryViewControllers.contains(
                where: { $0 === accessoryController }
            ) == false {
                window.addTitlebarAccessoryViewController(accessoryController)
            }
            updateControls()
        }

        func tearDown() {
            removeAccessoryFromAttachedWindow()
            accessoryController = nil
            container = nil
            sidebarButton = nil
            supplementaryButton = nil
        }

        @objc private func toggleSidebar() {
            onToggleSidebar()
        }

        @objc private func performSupplementaryAction() {
            supplementaryAction?.onPerform()
        }

        private func makeAccessoryController() -> NSTitlebarAccessoryViewController {
            let container = NSView(
                frame: NSRect(x: 0, y: 0, width: Self.singleActionWidth, height: 28)
            )
            container.autoresizingMask = [.height]

            let sidebarButton = makeButton(
                x: 5,
                action: #selector(toggleSidebar)
            )
            container.addSubview(sidebarButton)

            let supplementaryButton = makeButton(
                x: Self.singleActionWidth,
                action: #selector(performSupplementaryAction)
            )
            container.addSubview(supplementaryButton)

            let controller = NSTitlebarAccessoryViewController()
            controller.layoutAttribute = .leading
            controller.view = container

            accessoryController = controller
            self.container = container
            self.sidebarButton = sidebarButton
            self.supplementaryButton = supplementaryButton
            return controller
        }

        private func makeButton(x: CGFloat, action: Selector) -> NSButton {
            let button = NSButton(
                frame: NSRect(
                    x: x,
                    y: 3,
                    width: Self.buttonSize.width,
                    height: Self.buttonSize.height
                )
            )
            button.autoresizingMask = [.minYMargin, .maxYMargin]
            button.target = self
            button.action = action
            button.isBordered = false
            button.imagePosition = .imageOnly
            button.imageScaling = .scaleProportionallyDown
            button.contentTintColor = .secondaryLabelColor
            button.setButtonType(.momentaryPushIn)
            button.setAccessibilityRole(.button)
            return button
        }

        private func updateControls() {
            updateSidebarButton()
            updateSupplementaryButton()
            container?.frame.size.width = supplementaryAction == nil
                ? Self.singleActionWidth
                : Self.singleActionWidth + Self.additionalActionWidth
        }

        private func updateSidebarButton() {
            guard let sidebarButton else { return }
            let label = isSidebarVisible ? "Hide Sidebar" : "Show Sidebar"
            sidebarButton.image = symbol(named: "sidebar.left", accessibilityLabel: label)
            sidebarButton.identifier = NSUserInterfaceItemIdentifier(accessibilityIdentifier)
            sidebarButton.setAccessibilityIdentifier(accessibilityIdentifier)
            sidebarButton.toolTip = label
            sidebarButton.setAccessibilityLabel(label)
            sidebarButton.setAccessibilityHelp(
                "Toggles the \(navigationName) navigation sidebar"
            )
        }

        private func updateSupplementaryButton() {
            guard let supplementaryButton else { return }
            guard let supplementaryAction else {
                supplementaryButton.isHidden = true
                supplementaryButton.identifier = nil
                return
            }
            supplementaryButton.isHidden = false
            supplementaryButton.image = symbol(
                named: supplementaryAction.systemImage,
                accessibilityLabel: supplementaryAction.title
            )
            supplementaryButton.identifier = NSUserInterfaceItemIdentifier(
                supplementaryAction.accessibilityIdentifier
            )
            supplementaryButton.setAccessibilityIdentifier(
                supplementaryAction.accessibilityIdentifier
            )
            supplementaryButton.toolTip = supplementaryAction.title
            supplementaryButton.setAccessibilityLabel(supplementaryAction.title)
            supplementaryButton.setAccessibilityHelp(supplementaryAction.accessibilityHelp)
        }

        private func symbol(named name: String, accessibilityLabel: String) -> NSImage? {
            let configuration = NSImage.SymbolConfiguration(
                pointSize: 11,
                weight: .regular
            )
            return NSImage(
                systemSymbolName: name,
                accessibilityDescription: accessibilityLabel
            )?.withSymbolConfiguration(configuration)
        }

        private func removeAccessoryFromAttachedWindow() {
            guard let window, let accessoryController else {
                self.window = nil
                return
            }
            if let index = window.titlebarAccessoryViewControllers.firstIndex(
                where: { $0 === accessoryController }
            ) {
                window.removeTitlebarAccessoryViewController(at: index)
            }
            self.window = nil
        }
    }
}
