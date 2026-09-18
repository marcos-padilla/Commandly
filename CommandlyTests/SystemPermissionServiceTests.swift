import Foundation
import AppCore
import Infrastructure
import SecurityKit
import Testing
@testable import Commandly

@Suite("System permissions")
struct SystemPermissionServiceTests {
    @Test @MainActor
    func accessibilityStateDistinguishesUnrequestedDeniedAndAuthorized() async {
        let unrequested = AccessibilityPermissionStub(isTrusted: false, wasRequested: false)
        let denied = AccessibilityPermissionStub(isTrusted: false, wasRequested: true)
        let authorized = AccessibilityPermissionStub(isTrusted: true, wasRequested: true)

        #expect(await makeService(accessibilityStub: unrequested).state(for: .accessibility)
            == .notDetermined)
        #expect(await makeService(accessibilityStub: denied).state(for: .accessibility) == .denied)
        #expect(await makeService(accessibilityStub: authorized).state(for: .accessibility)
            == .authorized)
    }

    @Test @MainActor
    func rejectedAccessibilityRequestPersistsItsRecoveryMarker() async {
        let stub = AccessibilityPermissionStub(isTrusted: false, wasRequested: false)
        let service = makeService(accessibilityStub: stub)

        #expect(await service.request(.accessibility) == .denied)
        #expect(stub.requestCount == 1)
        #expect(stub.markCount == 1)
        #expect(stub.requestObservedMarker)
        #expect(await service.state(for: .accessibility) == .denied)
    }

    @Test @MainActor
    func statePreflightsWithoutRequestingOrPrompting() async {
        let stub = ScreenRecordingPermissionStub(
            preflightResult: false,
            requestResult: true,
            wasRequested: false
        )
        let service = makeService(stub: stub)

        let state = await service.state(for: .screenRecording)

        #expect(state == .notDetermined)
        #expect(stub.preflightCount == 1)
        #expect(stub.requestCount == 0)
        #expect(stub.markCount == 0)
    }

    @Test @MainActor
    func stateDistinguishesAuthorizedAndPreviouslyDeniedAccess() async {
        let authorizedStub = ScreenRecordingPermissionStub(
            preflightResult: true,
            requestResult: false,
            wasRequested: true
        )
        let deniedStub = ScreenRecordingPermissionStub(
            preflightResult: false,
            requestResult: false,
            wasRequested: true
        )

        let authorized = await makeService(stub: authorizedStub).state(for: .screenRecording)
        let denied = await makeService(stub: deniedStub).state(for: .screenRecording)

        #expect(authorized == .authorized)
        #expect(denied == .denied)
        #expect(authorizedStub.requestCount == 0)
        #expect(deniedStub.requestCount == 0)
    }

    @Test @MainActor
    func explicitRequestPersistsMarkerBeforeCallingSystemRequest() async {
        let stub = ScreenRecordingPermissionStub(
            preflightResult: false,
            requestResult: true,
            wasRequested: false
        )
        let service = makeService(stub: stub)

        let state = await service.request(.screenRecording)

        #expect(state == .authorized)
        #expect(stub.markCount == 1)
        #expect(stub.requestCount == 1)
        #expect(stub.requestObservedMarker)
    }

    @Test @MainActor
    func cancelledScreenRecordingRequestDoesNotPromptOrPersistMarker() async {
        let stub = ScreenRecordingPermissionStub(
            preflightResult: false,
            requestResult: true,
            wasRequested: false
        )
        let service = makeService(stub: stub)
        // MainActor serialization makes cancellation precede execution without a timing delay.
        let request = Task { @MainActor in await service.request(.screenRecording) }
        request.cancel()

        #expect(await request.value == .notDetermined)
        #expect(stub.requestCount == 0)
        #expect(stub.markCount == 0)
    }

    @Test @MainActor
    func rejectedRequestRemainsDeniedOnLaterPreflight() async {
        let stub = ScreenRecordingPermissionStub(
            preflightResult: false,
            requestResult: false,
            wasRequested: false
        )
        let service = makeService(stub: stub)

        #expect(await service.request(.screenRecording) == .denied)
        #expect(await service.state(for: .screenRecording) == .denied)
        #expect(stub.requestCount == 1)
        #expect(stub.markCount == 1)
    }

    @Test @MainActor
    func requestDoesNotInvokeSystemRequestWhenAlreadyAuthorized() async {
        let stub = ScreenRecordingPermissionStub(
            preflightResult: true,
            requestResult: false,
            wasRequested: false
        )
        let service = makeService(stub: stub)

        #expect(await service.request(.screenRecording) == .authorized)
        #expect(stub.requestCount == 0)
        #expect(stub.markCount == 0)
    }

    @Test @MainActor
    func settingsRefreshIncludesScreenRecordingState() async {
        let viewModel = makeSettingsViewModel(
            permissionService: InMemoryPermissionService(
                states: [.screenRecording: .authorized]
            )
        )

        await viewModel.refreshPermissions()

        #expect(viewModel.state(for: .screenRecording) == .authorized)
    }

    @Test @MainActor
    func deniedScreenRecordingActionOpensItsRecoveryPane() async {
        let opener = PrivacyPaneRecorder()
        let viewModel = makeSettingsViewModel(
            permissionService: InMemoryPermissionService(
                states: [.screenRecording: .denied]
            ),
            privacySettingsOpener: opener
        )
        await viewModel.refreshPermissions()

        viewModel.requestPermission(.screenRecording)

        #expect(await opener.nextOpenedPane() == .screenRecording)
    }

    @Test
    func workspaceOpenerUsesScreenCapturePrivacyPaneURL() {
        #expect(
            WorkspacePrivacySettingsOpener.url(for: .screenRecording)?.absoluteString
                == "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
        )
    }

    @MainActor
    private func makeService(stub: ScreenRecordingPermissionStub) -> SystemPermissionService {
        SystemPermissionService(
            folderAccessStore: InMemoryFolderAccessStore(),
            screenRecordingPreflight: { stub.preflight() },
            screenRecordingRequest: { stub.request() },
            screenRecordingWasRequested: { stub.wasRequested },
            markScreenRecordingRequested: { stub.markRequested() }
        )
    }

    @MainActor
    private func makeService(
        accessibilityStub: AccessibilityPermissionStub
    ) -> SystemPermissionService {
        SystemPermissionService(
            folderAccessStore: InMemoryFolderAccessStore(),
            accessibilityPreflight: { accessibilityStub.preflight() },
            accessibilityRequest: { accessibilityStub.request() },
            accessibilityWasRequested: { accessibilityStub.wasRequested },
            markAccessibilityRequested: { accessibilityStub.markRequested() }
        )
    }

    @MainActor
    private func makeSettingsViewModel(
        permissionService: any PermissionServicing,
        privacySettingsOpener: any PrivacySettingsOpening = InMemoryPrivacySettingsOpener()
    ) -> SettingsViewModel {
        SettingsViewModel(
            settingsStore: InMemoryAppSettingsStore(),
            loginItemManager: InMemoryLoginItemManager(),
            permissionService: permissionService,
            privacySettingsOpener: privacySettingsOpener,
            metadata: ApplicationMetadata(
                name: "Commandly",
                version: "1.0",
                build: "1",
                bundleIdentifier: "com.businessmate360.Commandly",
                environment: .testing
            )
        )
    }
}

private final class AccessibilityPermissionStub: @unchecked Sendable {
    private struct State {
        var isTrusted: Bool
        var wasRequested: Bool
        var requestCount = 0
        var markCount = 0
        var requestObservedMarker = false
    }

    private let lock = NSLock()
    private var state: State

    init(isTrusted: Bool, wasRequested: Bool) {
        state = State(isTrusted: isTrusted, wasRequested: wasRequested)
    }

    var wasRequested: Bool { lock.withLock { state.wasRequested } }
    var requestCount: Int { lock.withLock { state.requestCount } }
    var markCount: Int { lock.withLock { state.markCount } }
    var requestObservedMarker: Bool { lock.withLock { state.requestObservedMarker } }

    func preflight() -> Bool {
        lock.withLock { state.isTrusted }
    }

    func request() -> Bool {
        lock.withLock {
            state.requestCount += 1
            state.requestObservedMarker = state.wasRequested
            return state.isTrusted
        }
    }

    func markRequested() {
        lock.withLock {
            state.markCount += 1
            state.wasRequested = true
        }
    }
}

private final class ScreenRecordingPermissionStub: @unchecked Sendable {
    private struct State {
        var preflightResult: Bool
        let requestResult: Bool
        var wasRequested: Bool
        var preflightCount = 0
        var requestCount = 0
        var markCount = 0
        var requestObservedMarker = false
    }

    private let lock = NSLock()
    private var state: State

    init(preflightResult: Bool, requestResult: Bool, wasRequested: Bool) {
        state = State(
            preflightResult: preflightResult,
            requestResult: requestResult,
            wasRequested: wasRequested
        )
    }

    var wasRequested: Bool {
        lock.withLock { state.wasRequested }
    }

    var preflightCount: Int {
        lock.withLock { state.preflightCount }
    }

    var requestCount: Int {
        lock.withLock { state.requestCount }
    }

    var markCount: Int {
        lock.withLock { state.markCount }
    }

    var requestObservedMarker: Bool {
        lock.withLock { state.requestObservedMarker }
    }

    func preflight() -> Bool {
        lock.withLock {
            state.preflightCount += 1
            return state.preflightResult
        }
    }

    func request() -> Bool {
        lock.withLock {
            state.requestCount += 1
            state.requestObservedMarker = state.wasRequested
            return state.requestResult
        }
    }

    func markRequested() {
        lock.withLock {
            state.markCount += 1
            state.wasRequested = true
        }
    }
}

private actor PrivacyPaneRecorder: PrivacySettingsOpening {
    private var queuedPanes: [PrivacySettingsPane] = []
    private var waiter: CheckedContinuation<PrivacySettingsPane, Never>?

    func open(_ pane: PrivacySettingsPane) async {
        if let waiter {
            self.waiter = nil
            waiter.resume(returning: pane)
        } else {
            queuedPanes.append(pane)
        }
    }

    func nextOpenedPane() async -> PrivacySettingsPane {
        if queuedPanes.isEmpty == false {
            return queuedPanes.removeFirst()
        }
        return await withCheckedContinuation { continuation in
            waiter = continuation
        }
    }
}
