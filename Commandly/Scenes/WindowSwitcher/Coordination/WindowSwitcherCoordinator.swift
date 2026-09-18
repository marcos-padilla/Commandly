import AppKit
import Foundation
import Infrastructure
import SecurityKit

/// App-lifetime orchestration for switcher input, discovery, Dock hover, and the transient panel.
@MainActor
final class WindowSwitcherCoordinator: WindowSwitcherPresenting {
    private let queryService: any WindowQuerying
    private let controlService: any WindowControlling
    private let thumbnailService: any WindowThumbnailProviding
    private let permissionService: any PermissionServicing
    private let inputMonitor: any WindowSwitcherInputMonitoring
    private let dockHoverMonitor: any DockHoverMonitoring
    private let mouseMonitor: any WindowSwitcherMouseMonitoring
    private let windowController: any WindowSwitcherWindowPresenting
    private let notificationCenter: NotificationCenter
    private let workspaceNotificationCenter: NotificationCenter

    private var configuration = WindowSwitcherConfiguration.default
    private var isEnabled = false
    private var activeModel: WindowSwitcherPresentationModel?
    private var activeScreenFrame: CGRect?
    private var activeDockAnchor: CGRect?
    private var observerTokens: [NSObjectProtocol] = []
    private var permissionConfigurationGeneration: UInt64 = 0
    private var lastExternalProcessIdentifier: Int32?
    private var activeSessionToken: UUID?
    private var didLeaveActiveDockPreview = false

    init(
        queryService: any WindowQuerying,
        controlService: any WindowControlling,
        thumbnailService: any WindowThumbnailProviding,
        permissionService: any PermissionServicing,
        inputMonitor: any WindowSwitcherInputMonitoring = WindowSwitcherEventMonitor(),
        dockHoverMonitor: any DockHoverMonitoring = DockHoverMonitor(),
        mouseMonitor: any WindowSwitcherMouseMonitoring = WindowSwitcherMouseMonitor(),
        windowController: any WindowSwitcherWindowPresenting = WindowSwitcherWindowController(),
        notificationCenter: NotificationCenter = .default,
        workspaceNotificationCenter: NotificationCenter = NSWorkspace.shared.notificationCenter
    ) {
        self.queryService = queryService
        self.controlService = controlService
        self.thumbnailService = thumbnailService
        self.permissionService = permissionService
        self.inputMonitor = inputMonitor
        self.dockHoverMonitor = dockHoverMonitor
        self.mouseMonitor = mouseMonitor
        self.windowController = windowController
        self.notificationCenter = notificationCenter
        self.workspaceNotificationCenter = workspaceNotificationCenter
        captureFrontmostApplication()
        installObservers()
    }

    func configure(
        _ configuration: WindowSwitcherConfiguration,
        isEnabled: Bool
    ) {
        self.configuration = configuration
        self.isEnabled = isEnabled
        if isEnabled == false {
            permissionConfigurationGeneration &+= 1
            dismissSession(committed: false)
            inputMonitor.stop()
            dockHoverMonitor.stop()
            return
        }

        synchronizePermissionBoundServices(restartWhenAuthorized: true)
    }

    private func synchronizePermissionBoundServices(restartWhenAuthorized: Bool) {
        permissionConfigurationGeneration &+= 1
        let expectedGeneration = permissionConfigurationGeneration

        Task { @MainActor [weak self] in
            guard let self else { return }
            let permissionState = await permissionService.state(for: .accessibility)
            guard expectedGeneration == permissionConfigurationGeneration,
                  self.isEnabled else {
                return
            }
            guard permissionState == .authorized else {
                dismissSession(committed: false)
                inputMonitor.stop()
                dockHoverMonitor.stop()
                return
            }
            if await permissionService.state(for: .screenRecording) != .authorized {
                activeModel?.clearThumbnails()
            }
            if restartWhenAuthorized || inputMonitor.isRunning == false {
                installInputMonitor()
                configureDockHover()
            }
        }
    }

    /// Launcher/application-hotkey presentation always uses toggle behavior so the invocation does
    /// not depend on the originating key's release phase.
    func present(configuration: WindowSwitcherConfiguration) {
        guard isEnabled else { return }
        if activeModel?.context.isDockPreview == false {
            dismissSession(committed: false)
            return
        }
        captureFrontmostApplication()
        var overlayConfiguration = configuration
        overlayConfiguration.shortcutMode = .toggleOverlay
        let context = presentationContext(
            for: overlayConfiguration,
            source: .toggle
        )
        inputMonitor.beginToggleSession()
        presentSession(
            configuration: overlayConfiguration,
            context: context,
            initialSelectionOffset: 0
        )
    }

    func presentCurrentConfiguration() {
        var overlayConfiguration = configuration
        overlayConfiguration.shortcutMode = .toggleOverlay
        present(configuration: overlayConfiguration)
    }

    func tearDown() {
        permissionConfigurationGeneration &+= 1
        dismissSession(committed: false)
        inputMonitor.stop()
        dockHoverMonitor.stop()
        windowController.tearDown()
        removeMouseMonitors()
        for token in observerTokens {
            notificationCenter.removeObserver(token)
            workspaceNotificationCenter.removeObserver(token)
        }
        observerTokens.removeAll()
    }

    private func installInputMonitor() {
        _ = inputMonitor.start(configuration: configuration) { [weak self] command in
            self?.handle(command)
        }
    }

    private func configureDockHover() {
        guard configuration.showsDockPreviews else {
            dockHoverMonitor.stop()
            if activeModel?.context.isDockPreview == true {
                dismissSession(committed: false)
            }
            return
        }
        dockHoverMonitor.start(
            delay: configuration.dockPreviewDelay,
            protectedFrame: { [weak self] in self?.windowController.panelFrame },
            onHover: { [weak self] hovered in
                self?.presentDockPreview(hovered)
            },
            onLeave: { [weak self] in
                guard let self, activeModel?.context.isDockPreview == true else { return }
                didLeaveActiveDockPreview = true
                guard activeModel?.isPinned == false else { return }
                dismissSession(committed: false)
            }
        )
    }

    private func presentDockPreview(_ hovered: DockHoveredApplication) {
        guard isEnabled, configuration.showsDockPreviews else { return }
        if let activeModel, activeModel.context.isDockPreview == false { return }
        if case .dock(let currentProcessIdentifier, _) = activeModel?.context,
           currentProcessIdentifier == hovered.processIdentifier {
            didLeaveActiveDockPreview = false
            activeDockAnchor = hovered.anchorFrame
            updatePanelFrame()
            return
        }
        let context = WindowSwitcherPresentationContext.dock(
            processIdentifier: hovered.processIdentifier,
            anchorFrame: hovered.anchorFrame
        )
        presentSession(
            configuration: configuration,
            context: context,
            initialSelectionOffset: 0
        )
    }

    private func handle(_ command: WindowSwitcherInputCommand) {
        switch command {
        case .begin(let source, let reverse):
            guard isEnabled else { return }
            captureFrontmostApplication()
            let context = presentationContext(for: configuration, source: source)
            presentSession(
                configuration: configuration,
                context: context,
                initialSelectionOffset: reverse ? -1 : 1
            )
        case .cycle(let reverse):
            activeModel?.moveSelection(offset: reverse ? -1 : 1)
        case .move(let offset):
            activeModel?.moveSelection(offset: offset)
        case .commit:
            guard activeModel?.activateSelectionOrDefer() == true else {
                dismissSession(committed: false)
                return
            }
        case .cancel:
            dismissSession(committed: false)
        case .deleteBackward:
            activeModel?.deleteSearchBackward()
        case .clearSearch:
            activeModel?.clearSearch()
        case .appendText(let text):
            activeModel?.appendSearchText(text)
        case .perform(let action):
            activeModel?.perform(action)
        }
    }

    private func presentSession(
        configuration: WindowSwitcherConfiguration,
        context: WindowSwitcherPresentationContext,
        initialSelectionOffset: Int
    ) {
        dismissVisibleSurfaceOnly()
        let sessionToken = UUID()
        activeSessionToken = sessionToken
        didLeaveActiveDockPreview = false
        let screen = resolveScreen(configuration: configuration, context: context)
        let screenFrame = screen?.visibleFrame
            ?? NSScreen.main?.visibleFrame
            ?? CGRect(x: 0, y: 0, width: 900, height: 650)
        activeScreenFrame = screenFrame
        if case .dock(_, let anchorFrame) = context {
            activeDockAnchor = anchorFrame
        } else {
            activeDockAnchor = nil
        }

        let model = WindowSwitcherPresentationModel(
            configuration: configuration,
            context: context,
            queryService: queryService,
            controlService: controlService,
            thumbnailService: thumbnailService,
            displayFrame: configuration.placement == .activeDisplay
                && context.isDockPreview == false ? nil : screenFrame,
            initialSelectionOffset: initialSelectionOffset,
            onRequestDismiss: { [weak self] committed in
                guard self?.activeSessionToken == sessionToken else { return }
                self?.dismissSession(committed: committed)
            },
            onContentChanged: { [weak self] in
                self?.updatePanelFrame()
            },
            onPinChanged: { [weak self] isPinned in
                guard let self,
                      self.activeSessionToken == sessionToken,
                      self.activeModel?.context.isDockPreview == true,
                      isPinned == false,
                      self.didLeaveActiveDockPreview else {
                    return
                }
                self.dismissSession(committed: false)
            }
        )
        activeModel = model
        let frame = WindowSwitcherGeometry.panelFrame(
            configuration: configuration,
            windowCount: 1,
            screenFrame: screenFrame,
            dockAnchor: activeDockAnchor
        )
        windowController.present(model: model, frame: frame)
        if context.isDockPreview == false {
            installMouseMonitors()
        }
        model.load()
    }

    private func updatePanelFrame() {
        guard let model = activeModel,
              var screenFrame = activeScreenFrame else {
            return
        }
        if model.configuration.placement == .activeDisplay,
           model.context.isDockPreview == false,
           let screen = activeScreen(for: model) {
            screenFrame = screen.visibleFrame
            activeScreenFrame = screenFrame
            model.updateDisplayFrame(
                screenFrame,
                refreshesWindowSet: model.configuration.limitsToCurrentDisplay
            )
        }
        let frame = WindowSwitcherGeometry.panelFrame(
            configuration: model.configuration,
            windowCount: model.visibleWindows.count,
            screenFrame: screenFrame,
            dockAnchor: activeDockAnchor
        )
        windowController.updateFrame(frame)
    }

    private func dismissSession(committed: Bool) {
        let model = activeModel
        activeModel = nil
        activeSessionToken = nil
        activeScreenFrame = nil
        activeDockAnchor = nil
        didLeaveActiveDockPreview = false
        removeMouseMonitors()
        windowController.dismiss()
        inputMonitor.endSession()
        model?.stop()
        if committed { captureFrontmostApplication() }
    }

    private func dismissVisibleSurfaceOnly() {
        let model = activeModel
        activeModel = nil
        activeSessionToken = nil
        activeScreenFrame = nil
        activeDockAnchor = nil
        didLeaveActiveDockPreview = false
        removeMouseMonitors()
        windowController.dismiss()
        model?.stop()
    }

    private func presentationContext(
        for configuration: WindowSwitcherConfiguration,
        source: WindowSwitcherShortcutSource
    ) -> WindowSwitcherPresentationContext {
        let processIdentifier = lastExternalProcessIdentifier
        if configuration.filterMode == .activeApplication,
           let processIdentifier {
            return .activeApplication(processIdentifier: processIdentifier)
        }
        switch source {
        case .commandTab:
            return .commandTab(frontmostProcessIdentifier: processIdentifier)
        case .optionTab, .toggle:
            return .allWindows(frontmostProcessIdentifier: processIdentifier)
        }
    }

    private func resolveScreen(
        configuration: WindowSwitcherConfiguration,
        context: WindowSwitcherPresentationContext
    ) -> NSScreen? {
        if case .dock(_, let anchorFrame) = context {
            return NSScreen.screens.max { left, right in
                left.frame.intersection(anchorFrame).area
                    < right.frame.intersection(anchorFrame).area
            }
        }
        switch configuration.placement {
        case .pointerDisplay:
            let pointer = NSEvent.mouseLocation
            return NSScreen.screens.first(where: { $0.frame.contains(pointer) })
                ?? NSScreen.main
        case .mainDisplay:
            return NSScreen.screens.first(where: { $0.frame.origin == .zero })
                ?? NSScreen.main
        case .activeDisplay:
            return activeModel.flatMap(activeScreen(for:)) ?? NSScreen.main
        }
    }

    private func activeScreen(
        for model: WindowSwitcherPresentationModel
    ) -> NSScreen? {
        let processIdentifier = model.context.frontmostProcessIdentifier
            ?? lastExternalProcessIdentifier
        let preferredWindow = processIdentifier.flatMap { processIdentifier in
            model.windows.first(where: {
                $0.processIdentifier == processIdentifier && $0.isFocused
            }) ?? model.windows.first(where: {
                $0.processIdentifier == processIdentifier && $0.isWindowless == false
            })
        } ?? model.windows.first(where: { $0.isFocused })
            ?? model.selectedWindow
            ?? model.windows.first(where: { $0.isWindowless == false })
        guard let preferredWindow else { return nil }
        return NSScreen.screens.max { left, right in
            left.frame.intersection(preferredWindow.frame).area
                < right.frame.intersection(preferredWindow.frame).area
        }
    }

    private func installMouseMonitors() {
        removeMouseMonitors()
        guard let sessionToken = activeSessionToken else { return }
        mouseMonitor.start { [weak self] location in
            guard self?.activeSessionToken == sessionToken else { return }
            self?.dismissIfOutsidePanel(location: location)
        }
    }

    private func dismissIfOutsidePanel(location: CGPoint) {
        guard let panelFrame = windowController.panelFrame,
              panelFrame.contains(location) == false else {
            return
        }
        dismissSession(committed: false)
    }

    private func removeMouseMonitors() {
        mouseMonitor.stop()
    }

    private func installObservers() {
        observerTokens.append(
            workspaceNotificationCenter.addObserver(
                forName: NSWorkspace.didActivateApplicationNotification,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                    as? NSRunningApplication
                MainActor.assumeIsolated {
                    guard let self, let application,
                          application.processIdentifier
                            != ProcessInfo.processInfo.processIdentifier else {
                        return
                    }
                    self.lastExternalProcessIdentifier = application.processIdentifier
                }
            }
        )
        observerTokens.append(
            workspaceNotificationCenter.addObserver(
                forName: NSWorkspace.activeSpaceDidChangeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    if self.activeModel?.context.isDockPreview == true {
                        self.dismissSession(committed: false)
                    } else {
                        self.activeModel?.refresh()
                    }
                }
            }
        )
        observerTokens.append(
            workspaceNotificationCenter.addObserver(
                forName: NSWorkspace.didTerminateApplicationNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.activeModel?.refresh()
                }
            }
        )
        observerTokens.append(
            notificationCenter.addObserver(
                forName: NSApplication.didBecomeActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, self.isEnabled else { return }
                    self.synchronizePermissionBoundServices(
                        restartWhenAuthorized: false
                    )
                }
            }
        )
        observerTokens.append(
            notificationCenter.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, let model = self.activeModel else { return }
                    let screen = self.resolveScreen(
                        configuration: model.configuration,
                        context: model.context
                    )
                    self.activeScreenFrame = screen?.visibleFrame
                    self.updatePanelFrame()
                }
            }
        )
    }

    private func captureFrontmostApplication() {
        guard let application = NSWorkspace.shared.frontmostApplication,
              application.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
            return
        }
        lastExternalProcessIdentifier = application.processIdentifier
    }

    isolated deinit {
        mouseMonitor.stop()
    }
}

private extension CGRect {
    nonisolated var area: CGFloat { isNull ? 0 : width * height }
}
