import CoreGraphics
import Foundation
import Infrastructure
import SecurityKit
import Testing
@testable import Commandly

@Suite("Window Switcher runtime")
@MainActor
struct WindowSwitcherRuntimeTests {
    @Test func disabledOrUnauthorizedSwitcherDoesNotInstallRuntimeMonitors() async {
        let fixture = makeWindowSwitcherRuntimeFixture(permissionState: .denied)
        defer { fixture.coordinator.tearDown() }

        fixture.coordinator.configure(.default, isEnabled: false)
        fixture.coordinator.presentCurrentConfiguration()
        #expect(fixture.presenter.presentCount == 0)
        #expect(fixture.input.isRunning == false)

        var configuration = WindowSwitcherConfiguration.default
        configuration.showsDockPreviews = true
        fixture.coordinator.configure(configuration, isEnabled: true)
        await yieldToRuntime()

        #expect(fixture.input.isRunning == false)
        fixture.input.send(.begin(source: .optionTab, reverse: false))
        fixture.dock.sendHover(DockHoveredApplication(
            processIdentifier: 202,
            bundleIdentifier: "com.example.beta",
            anchorFrame: CGRect(x: 500, y: 0, width: 48, height: 48)
        ))
        #expect(fixture.presenter.presentCount == 0)
    }

    @Test func inputSessionCyclesPerformsActionsCommitsAndClearsEphemeralState() async throws {
        let fixture = makeWindowSwitcherRuntimeFixture(permissionState: .authorized)
        defer { fixture.coordinator.tearDown() }
        var configuration = WindowSwitcherConfiguration.default
        configuration.showsThumbnails = false
        configuration.usesLivePreviews = false

        fixture.coordinator.configure(configuration, isEnabled: true)
        #expect(await waitUntil { fixture.input.isRunning })

        fixture.input.send(.begin(source: .optionTab, reverse: false))
        #expect(await waitUntil { fixture.presenter.model?.phase == .ready })
        let model = try #require(fixture.presenter.model)
        #expect(model.selectedID == windowID("beta", processIdentifier: 202))

        fixture.input.send(.perform(.leftHalf))
        #expect(await waitForActionCount(1, service: fixture.windowService))
        #expect(fixture.presenter.isPresented)

        fixture.input.send(.cycle(reverse: false))
        #expect(model.selectedID == windowID("alpha", processIdentifier: 101))
        fixture.input.send(.appendText("Alpha"))
        #expect(model.query == "Alpha")
        #expect(model.visibleWindows.map(\.id) == [windowID("alpha", processIdentifier: 101)])

        fixture.input.send(.commit)
        #expect(await waitForActionCount(2, service: fixture.windowService))
        #expect(await waitUntil { fixture.presenter.isPresented == false })

        let actions = await fixture.windowService.performedActions
        #expect(actions == [
            WindowActionInvocation(
                action: .leftHalf,
                windowID: windowID("beta", processIdentifier: 202)
            ),
            WindowActionInvocation(
                action: .activate,
                windowID: windowID("alpha", processIdentifier: 101)
            ),
        ])
        #expect(model.phase == .idle)
        #expect(model.windows.isEmpty)
        #expect(model.query.isEmpty)
        #expect(model.thumbnails.isEmpty)
        #expect(fixture.input.isRunning)

        fixture.coordinator.configure(configuration, isEnabled: false)
        #expect(fixture.input.isRunning == false)
    }

    @Test func reverseBeginSelectsTheWindowBeforeTheFocusedItem() async throws {
        let windows = [
            makeWindowSnapshot(
                rawID: "alpha",
                processIdentifier: 101,
                applicationName: "Alpha",
                title: "Alpha Draft",
                isFocused: true
            ),
            makeWindowSnapshot(
                rawID: "beta",
                processIdentifier: 202,
                applicationName: "Beta",
                title: "Beta Board",
                isFocused: false
            ),
            makeWindowSnapshot(
                rawID: "gamma",
                processIdentifier: 303,
                applicationName: "Gamma",
                title: "Gamma Notes",
                isFocused: false
            ),
        ]
        let fixture = makeWindowSwitcherRuntimeFixture(
            permissionState: .authorized,
            windows: windows
        )
        defer { fixture.coordinator.tearDown() }
        var configuration = WindowSwitcherConfiguration.default
        configuration.showsThumbnails = false

        fixture.coordinator.configure(configuration, isEnabled: true)
        #expect(await waitUntil { fixture.input.isRunning })
        fixture.input.send(.begin(source: .optionTab, reverse: true))
        #expect(await waitUntil { fixture.presenter.model?.phase == .ready })

        #expect(fixture.presenter.model?.selectedID == windowID(
            "gamma",
            processIdentifier: 303
        ))
    }

    @Test func cyclesAndCommitBeforeDiscoveryApplyToTheLoadedSelection() async throws {
        let windows = [
            makeWindowSnapshot(
                rawID: "alpha",
                processIdentifier: 101,
                applicationName: "Alpha",
                title: "Alpha Draft",
                isFocused: true
            ),
            makeWindowSnapshot(
                rawID: "beta",
                processIdentifier: 202,
                applicationName: "Beta",
                title: "Beta Board",
                isFocused: false
            ),
            makeWindowSnapshot(
                rawID: "gamma",
                processIdentifier: 303,
                applicationName: "Gamma",
                title: "Gamma Notes",
                isFocused: false
            ),
        ]
        let service = SuspendedQueryWindowService(windows: windows)
        let permissions = InMemoryPermissionService(states: [
            .accessibility: .authorized,
            .screenRecording: .denied,
        ])
        let input = InMemoryWindowSwitcherInputMonitor()
        let presenter = RecordingWindowSwitcherPresenter()
        let coordinator = WindowSwitcherCoordinator(
            queryService: service,
            controlService: service,
            thumbnailService: InMemoryWindowThumbnailService(),
            permissionService: permissions,
            inputMonitor: input,
            dockHoverMonitor: InMemoryDockHoverMonitor(),
            mouseMonitor: RecordingWindowSwitcherMouseMonitor(),
            windowController: presenter,
            notificationCenter: NotificationCenter(),
            workspaceNotificationCenter: NotificationCenter()
        )
        defer { coordinator.tearDown() }
        var configuration = WindowSwitcherConfiguration.default
        configuration.showsThumbnails = false

        coordinator.configure(configuration, isEnabled: true)
        #expect(await waitUntil { input.isRunning })
        input.send(.begin(source: .optionTab, reverse: false))
        input.send(.cycle(reverse: false))
        input.send(.commit)

        #expect(await waitForPendingQuery(service))
        #expect(presenter.model?.phase == .loading)
        #expect(presenter.isPresented)
        await service.resumeQuery()

        #expect(await waitUntil { presenter.isPresented == false })
        #expect(await service.performedActions == [
            WindowActionInvocation(
                action: .activate,
                windowID: windowID("gamma", processIdentifier: 303)
            ),
        ])
    }

    @Test func staleActionCompletionCannotDismissAReplacementSession() async throws {
        let windows = [
            makeWindowSnapshot(
                rawID: "alpha",
                processIdentifier: 101,
                applicationName: "Alpha",
                title: "Alpha Draft",
                isFocused: true
            ),
            makeWindowSnapshot(
                rawID: "beta",
                processIdentifier: 202,
                applicationName: "Beta",
                title: "Beta Board",
                isFocused: false
            ),
        ]
        let service = SuspendedActionWindowService(windows: windows)
        let permissions = InMemoryPermissionService(states: [
            .accessibility: .authorized,
            .screenRecording: .denied,
        ])
        let input = InMemoryWindowSwitcherInputMonitor()
        let presenter = RecordingWindowSwitcherPresenter()
        let coordinator = WindowSwitcherCoordinator(
            queryService: service,
            controlService: service,
            thumbnailService: InMemoryWindowThumbnailService(),
            permissionService: permissions,
            inputMonitor: input,
            dockHoverMonitor: InMemoryDockHoverMonitor(),
            mouseMonitor: RecordingWindowSwitcherMouseMonitor(),
            windowController: presenter,
            notificationCenter: NotificationCenter(),
            workspaceNotificationCenter: NotificationCenter()
        )
        defer { coordinator.tearDown() }
        var configuration = WindowSwitcherConfiguration.default
        configuration.showsThumbnails = false

        coordinator.configure(configuration, isEnabled: true)
        #expect(await waitUntil { input.isRunning })
        input.send(.begin(source: .optionTab, reverse: false))
        #expect(await waitUntil { presenter.model?.phase == .ready })
        let firstModel = try #require(presenter.model)
        input.send(.commit)
        #expect(await waitForPendingAction(service))

        input.send(.begin(source: .optionTab, reverse: true))
        #expect(await waitUntil {
            presenter.model?.phase == .ready && presenter.model !== firstModel
        })
        let replacementModel = try #require(presenter.model)
        await service.resumeAction()
        await yieldToRuntime()

        #expect(presenter.isPresented)
        #expect(presenter.model === replacementModel)
        #expect(replacementModel.phase == .ready)
        #expect(firstModel.phase == .idle)
    }

    @Test func permissionRevocationDismissesAndClearsAnActiveSession() async throws {
        let fixture = makeWindowSwitcherRuntimeFixture(permissionState: .authorized)
        defer { fixture.coordinator.tearDown() }
        var configuration = WindowSwitcherConfiguration.default
        configuration.showsThumbnails = false

        fixture.coordinator.configure(configuration, isEnabled: true)
        #expect(await waitUntil { fixture.input.isRunning })
        fixture.input.send(.begin(source: .optionTab, reverse: false))
        #expect(await waitUntil { fixture.presenter.model?.phase == .ready })
        let model = try #require(fixture.presenter.model)

        fixture.permissions.setState(.denied, for: .accessibility)
        fixture.coordinator.configure(configuration, isEnabled: true)
        #expect(await waitUntil { fixture.input.isRunning == false })

        #expect(fixture.presenter.isPresented == false)
        #expect(model.phase == .idle)
        #expect(model.windows.isEmpty)
    }

    @Test func outsideClicksAreSessionScopedAndStopWithDismissal() async throws {
        let fixture = makeWindowSwitcherRuntimeFixture(permissionState: .authorized)
        defer { fixture.coordinator.tearDown() }
        var configuration = WindowSwitcherConfiguration.default
        configuration.showsThumbnails = false
        fixture.coordinator.configure(configuration, isEnabled: true)
        #expect(await waitUntil { fixture.input.isRunning })
        fixture.input.send(.begin(source: .optionTab, reverse: false))
        #expect(await waitUntil { fixture.presenter.model?.phase == .ready })
        let firstModel = try #require(fixture.presenter.model)
        let frame = try #require(fixture.presenter.panelFrame)
        let oldHandler = try #require(fixture.mouse.onMouseDown)
        let outside = CGPoint(x: frame.maxX + 100, y: frame.maxY + 100)

        fixture.mouse.send(CGPoint(x: frame.midX, y: frame.midY))
        #expect(fixture.presenter.isPresented)
        fixture.input.send(.begin(source: .optionTab, reverse: true))
        #expect(await waitUntil {
            fixture.presenter.model?.phase == .ready && fixture.presenter.model !== firstModel
        })
        oldHandler(outside)
        #expect(fixture.presenter.isPresented)

        fixture.mouse.send(outside)
        #expect(fixture.presenter.isPresented == false)
        #expect(fixture.mouse.onMouseDown == nil)
        let dismissCount = fixture.presenter.dismissCount
        fixture.mouse.send(outside)
        #expect(fixture.presenter.dismissCount == dismissCount)
        fixture.coordinator.tearDown()
        #expect(fixture.mouse.onMouseDown == nil)
    }

    @Test func directTogglePresentationDismissesAnExistingSwitcherSession() async throws {
        let fixture = makeWindowSwitcherRuntimeFixture(permissionState: .authorized)
        defer { fixture.coordinator.tearDown() }
        var configuration = WindowSwitcherConfiguration.default
        configuration.showsThumbnails = false

        fixture.coordinator.configure(configuration, isEnabled: true)
        #expect(await waitUntil { fixture.input.isRunning })
        fixture.coordinator.presentCurrentConfiguration()
        #expect(await waitUntil { fixture.presenter.model?.phase == .ready })
        let model = try #require(fixture.presenter.model)

        fixture.coordinator.presentCurrentConfiguration()

        #expect(fixture.presenter.isPresented == false)
        #expect(model.phase == .idle)
        #expect(model.windows.isEmpty)
    }

    @Test func dockPreviewRestrictsWindowsAndPinControlsHoverDismissal() async throws {
        let fixture = makeWindowSwitcherRuntimeFixture(permissionState: .authorized)
        defer { fixture.coordinator.tearDown() }
        var configuration = WindowSwitcherConfiguration.default
        configuration.showsDockPreviews = true
        configuration.showsThumbnails = false
        configuration.usesLivePreviews = false

        fixture.coordinator.configure(configuration, isEnabled: true)
        #expect(await waitUntil { fixture.input.isRunning })
        fixture.dock.sendHover(DockHoveredApplication(
            processIdentifier: 202,
            bundleIdentifier: "com.example.beta",
            anchorFrame: CGRect(x: 500, y: 0, width: 48, height: 48)
        ))

        #expect(await waitUntil { fixture.presenter.model?.phase == .ready })
        let model = try #require(fixture.presenter.model)
        #expect(model.context.isDockPreview)
        #expect(model.visibleWindows.map(\.processIdentifier) == [202])

        model.isPinned = true
        fixture.dock.sendLeave()
        #expect(fixture.presenter.isPresented)

        model.isPinned = false
        #expect(fixture.presenter.isPresented == false)
        #expect(model.phase == .idle)
        #expect(model.windows.isEmpty)
    }

    @Test func dockHoverDoesNotReplaceAnActiveKeyboardSession() async throws {
        let fixture = makeWindowSwitcherRuntimeFixture(permissionState: .authorized)
        defer { fixture.coordinator.tearDown() }
        var configuration = WindowSwitcherConfiguration.default
        configuration.showsDockPreviews = true
        configuration.showsThumbnails = false

        fixture.coordinator.configure(configuration, isEnabled: true)
        #expect(await waitUntil { fixture.input.isRunning })
        fixture.input.send(.begin(source: .optionTab, reverse: false))
        #expect(await waitUntil { fixture.presenter.model?.phase == .ready })
        let keyboardModel = try #require(fixture.presenter.model)

        fixture.dock.sendHover(DockHoveredApplication(
            processIdentifier: 202,
            bundleIdentifier: "com.example.beta",
            anchorFrame: CGRect(x: 500, y: 0, width: 48, height: 48)
        ))

        #expect(fixture.presenter.presentCount == 1)
        #expect(fixture.presenter.model === keyboardModel)
        #expect(keyboardModel.context.isDockPreview == false)
    }

    @Test func permissionRevocationDismissesAPinnedDockPreview() async throws {
        let fixture = makeWindowSwitcherRuntimeFixture(permissionState: .authorized)
        defer { fixture.coordinator.tearDown() }
        var configuration = WindowSwitcherConfiguration.default
        configuration.showsDockPreviews = true
        configuration.showsThumbnails = false

        fixture.coordinator.configure(configuration, isEnabled: true)
        #expect(await waitUntil { fixture.input.isRunning })
        fixture.dock.sendHover(DockHoveredApplication(
            processIdentifier: 202,
            bundleIdentifier: "com.example.beta",
            anchorFrame: CGRect(x: 500, y: 0, width: 48, height: 48)
        ))
        #expect(await waitUntil { fixture.presenter.model?.phase == .ready })
        let model = try #require(fixture.presenter.model)
        model.isPinned = true

        fixture.permissions.setState(.denied, for: .accessibility)
        fixture.coordinator.configure(configuration, isEnabled: true)
        #expect(await waitUntil { fixture.input.isRunning == false })

        #expect(fixture.presenter.isPresented == false)
        #expect(model.phase == .idle)
        #expect(model.windows.isEmpty)
    }

    @Test func geometryClampsLargeOffsetsToNegativeOriginDisplay() {
        var configuration = WindowSwitcherConfiguration.default
        configuration.layoutStyle = .grid
        configuration.itemSize = .large
        configuration.gridColumnCount = 8
        configuration.horizontalOffset = 600
        configuration.verticalOffset = -600
        let screenFrame = CGRect(x: -1_600, y: -200, width: 1_200, height: 900)

        let frame = WindowSwitcherGeometry.panelFrame(
            configuration: configuration,
            windowCount: 40,
            screenFrame: screenFrame
        )
        let reachableFrame = screenFrame.insetBy(dx: 12, dy: 12)

        #expect(frame.minX >= reachableFrame.minX)
        #expect(frame.maxX <= reachableFrame.maxX)
        #expect(frame.minY >= reachableFrame.minY)
        #expect(frame.maxY <= reachableFrame.maxY)
        #expect(frame.width <= reachableFrame.width)
        #expect(frame.height <= reachableFrame.height)
    }

    @Test func dockGeometryPrefersTheAnchoredEdgeAndRemainsReachable() {
        var configuration = WindowSwitcherConfiguration.default
        configuration.layoutStyle = .strip
        configuration.itemSize = .compact
        let screenFrame = CGRect(x: 0, y: 0, width: 1_000, height: 800)
        let dockAnchor = CGRect(x: 476, y: 8, width: 48, height: 48)

        let frame = WindowSwitcherGeometry.panelFrame(
            configuration: configuration,
            windowCount: 3,
            screenFrame: screenFrame,
            dockAnchor: dockAnchor
        )
        let reachableFrame = screenFrame.insetBy(dx: 12, dy: 12)

        #expect(frame.minY >= dockAnchor.maxY + 9)
        #expect(frame.minX >= reachableFrame.minX)
        #expect(frame.maxX <= reachableFrame.maxX)
        #expect(frame.minY >= reachableFrame.minY)
        #expect(frame.maxY <= reachableFrame.maxY)
    }
}

@MainActor
private final class RecordingWindowSwitcherMouseMonitor: WindowSwitcherMouseMonitoring {
    private(set) var onMouseDown: ((CGPoint) -> Void)?

    func start(onMouseDown: @escaping (CGPoint) -> Void) {
        self.onMouseDown = onMouseDown
    }

    func stop() {
        onMouseDown = nil
    }

    func send(_ location: CGPoint) {
        onMouseDown?(location)
    }
}

@MainActor
private struct WindowSwitcherRuntimeFixture {
    let coordinator: WindowSwitcherCoordinator
    let permissions: InMemoryPermissionService
    let windowService: InMemoryWindowService
    let input: InMemoryWindowSwitcherInputMonitor
    let mouse: RecordingWindowSwitcherMouseMonitor
    let dock: InMemoryDockHoverMonitor
    let presenter: RecordingWindowSwitcherPresenter
}

@MainActor
private func makeWindowSwitcherRuntimeFixture(
    permissionState: PermissionState,
    windows: [WindowSnapshot]? = nil
) -> WindowSwitcherRuntimeFixture {
    let permissions = InMemoryPermissionService(states: [
        .accessibility: permissionState,
        .screenRecording: .denied,
    ])
    let defaultWindows = [
        makeWindowSnapshot(
            rawID: "alpha",
            processIdentifier: 101,
            applicationName: "Alpha",
            title: "Alpha Draft",
            isFocused: true
        ),
        makeWindowSnapshot(
            rawID: "beta",
            processIdentifier: 202,
            applicationName: "Beta",
            title: "Beta Board",
            isFocused: false
        ),
    ]
    let windowService = InMemoryWindowService(windows: windows ?? defaultWindows)
    let input = InMemoryWindowSwitcherInputMonitor()
    let mouse = RecordingWindowSwitcherMouseMonitor()
    let dock = InMemoryDockHoverMonitor()
    let presenter = RecordingWindowSwitcherPresenter()
    let coordinator = WindowSwitcherCoordinator(
        queryService: windowService,
        controlService: windowService,
        thumbnailService: InMemoryWindowThumbnailService(),
        permissionService: permissions,
        inputMonitor: input,
        dockHoverMonitor: dock,
        mouseMonitor: mouse,
        windowController: presenter,
        notificationCenter: NotificationCenter(),
        workspaceNotificationCenter: NotificationCenter()
    )
    return WindowSwitcherRuntimeFixture(
        coordinator: coordinator,
        permissions: permissions,
        windowService: windowService,
        input: input,
        mouse: mouse,
        dock: dock,
        presenter: presenter
    )
}

private func makeWindowSnapshot(
    rawID: String,
    processIdentifier: Int32,
    applicationName: String,
    title: String,
    isFocused: Bool
) -> WindowSnapshot {
    WindowSnapshot(
        id: windowID(rawID, processIdentifier: processIdentifier),
        processIdentifier: processIdentifier,
        bundleIdentifier: "com.example.\(rawID)",
        applicationName: applicationName,
        title: title,
        frame: CGRect(x: 100, y: 100, width: 800, height: 600),
        isMinimized: false,
        isHidden: false,
        isOnCurrentDesktop: true,
        isFocused: isFocused,
        captureWindowID: nil
    )
}

private func windowID(_ rawValue: String, processIdentifier: Int32) -> WindowID {
    WindowID(rawValue: rawValue, processIdentifier: processIdentifier)
}

@MainActor
private final class RecordingWindowSwitcherPresenter: WindowSwitcherWindowPresenting {
    private(set) var isPresented = false
    private(set) var panelFrame: CGRect?
    private(set) var model: WindowSwitcherPresentationModel?
    private(set) var presentCount = 0
    private(set) var dismissCount = 0
    private(set) var tearDownCount = 0

    func present(model: WindowSwitcherPresentationModel, frame: CGRect) {
        isPresented = true
        panelFrame = frame
        self.model = model
        presentCount += 1
    }

    func updateFrame(_ frame: CGRect) {
        panelFrame = frame
    }

    func dismiss() {
        isPresented = false
        panelFrame = nil
        dismissCount += 1
    }

    func tearDown() {
        dismiss()
        tearDownCount += 1
    }
}

@MainActor
private func waitUntil(
    _ predicate: () -> Bool,
    attempts: Int = 200
) async -> Bool {
    for _ in 0 ..< attempts {
        if predicate() { return true }
        await Task.yield()
    }
    return predicate()
}

private func waitForActionCount(
    _ expectedCount: Int,
    service: InMemoryWindowService
) async -> Bool {
    for _ in 0 ..< 200 {
        if await service.performedActions.count >= expectedCount { return true }
        await Task.yield()
    }
    return await service.performedActions.count >= expectedCount
}

private func waitForPendingQuery(
    _ service: SuspendedQueryWindowService
) async -> Bool {
    for _ in 0 ..< 200 {
        if await service.hasPendingQuery { return true }
        await Task.yield()
    }
    return await service.hasPendingQuery
}

private func waitForPendingAction(
    _ service: SuspendedActionWindowService
) async -> Bool {
    for _ in 0 ..< 200 {
        if await service.hasPendingAction { return true }
        await Task.yield()
    }
    return await service.hasPendingAction
}

private func yieldToRuntime() async {
    for _ in 0 ..< 20 {
        await Task.yield()
    }
}

private actor SuspendedQueryWindowService: WindowQuerying, WindowControlling {
    private let windows: [WindowSnapshot]
    private var queryContinuation: CheckedContinuation<[WindowSnapshot], Error>?
    private(set) var performedActions: [WindowActionInvocation] = []

    init(windows: [WindowSnapshot]) {
        self.windows = windows
    }

    var hasPendingQuery: Bool { queryContinuation != nil }

    func windows(options: WindowQueryOptions) async throws -> [WindowSnapshot] {
        _ = options
        return try await withCheckedThrowingContinuation { continuation in
            queryContinuation = continuation
        }
    }

    func resumeQuery() {
        guard let queryContinuation else { return }
        self.queryContinuation = nil
        queryContinuation.resume(returning: windows)
    }

    func perform(_ action: WindowAction, on windowID: WindowID) async throws {
        guard windows.contains(where: { $0.id == windowID }) else {
            throw WindowServiceError.windowNotFound(windowID)
        }
        performedActions.append(WindowActionInvocation(action: action, windowID: windowID))
    }
}

private actor SuspendedActionWindowService: WindowQuerying, WindowControlling {
    private let windows: [WindowSnapshot]
    private var actionContinuation: CheckedContinuation<Void, Never>?

    init(windows: [WindowSnapshot]) {
        self.windows = windows
    }

    var hasPendingAction: Bool { actionContinuation != nil }

    func windows(options: WindowQueryOptions) async throws -> [WindowSnapshot] {
        _ = options
        return windows
    }

    func perform(_ action: WindowAction, on windowID: WindowID) async throws {
        _ = action
        guard windows.contains(where: { $0.id == windowID }) else {
            throw WindowServiceError.windowNotFound(windowID)
        }
        await withCheckedContinuation { continuation in
            actionContinuation = continuation
        }
    }

    func resumeAction() {
        guard let actionContinuation else { return }
        self.actionContinuation = nil
        actionContinuation.resume()
    }
}
