import CommandKit
import Foundation
import Infrastructure
import Observation
import SecurityKit
import Testing
@testable import Commandly

@Suite("Camera preview model", .timeLimit(.minutes(1)))
@MainActor
struct CameraViewModelTests {
    @Test
    func constructionAndInactiveActionsDoNotAccessPermissionsCameraOrClipboard() async {
        let harness = CameraModelHarness()
        let model = harness.model

        #expect(model.state == .idle && model.frame == nil && model.photo == nil)
        #expect(model.footerActions.first?.id == CameraActionID.start)
        #expect(model.canCapture == false)
        model.takePhoto()
        model.copyPhoto()
        model.perform(CameraActionID.save)

        #expect(await harness.permissions.checks().isEmpty)
        #expect(await harness.permissions.requests().isEmpty)
        #expect(harness.factory.calls == 0)
        #expect(await harness.copier.attempts().isEmpty)
        #expect(await harness.opener.openedPanes().isEmpty)
        #expect(model.showsFileExporter == false)
    }

    @Test
    func explicitStartChecksAndRequestsUndeterminedAccessOnlyOnce() async throws {
        let frame = try CameraModelFixtures.frame(1)
        let capture = CameraCaptureDouble(initialFrame: frame)
        let harness = CameraModelHarness(permission: .notDetermined, captures: [capture])
        let model = harness.model

        model.start()
        model.start()
        await model.waitForWorkForTesting()
        await Self.waitForFrame(in: model)

        #expect(await harness.permissions.checks() == [.camera])
        #expect(await harness.permissions.requests() == [.camera])
        #expect(harness.factory.calls == 1)
        #expect(await capture.startRequests() == [nil])
        #expect(model.permissionState == .authorized && model.state == .previewing)
        #expect(model.frame == frame && model.canCapture)
        #expect(model.selectedDeviceID == CameraModelFixtures.devices[0].id)
        #expect(await harness.copier.attempts().isEmpty && model.showsFileExporter == false)
        model.stop()
        await model.waitForCleanupForTesting()
    }

    @Test
    func deniedAndRestrictedAccessNeverConstructCameraAndOfferRecovery() async {
        for permission in [PermissionState.denied, .restricted] {
            let harness = CameraModelHarness(permission: permission)
            let model = harness.model
            model.start()
            await model.waitForWorkForTesting()

            #expect(model.state == .failed(.permissionRequired))
            #expect(model.permissionState == permission && model.needsSettingsRecovery)
            #expect(model.footerActions.first?.id == CameraActionID.openSettings)
            #expect(harness.factory.calls == 0)
            #expect(await harness.permissions.checks() == [.camera])
            #expect(await harness.permissions.requests().isEmpty)
            #expect(await harness.opener.openedPanes().isEmpty)

            model.perform(CameraActionID.openSettings)
            #expect(await harness.opener.nextOpenedPane() == .camera)
        }
    }

    @Test
    func decliningInitialPermissionLeavesTheCameraUnconstructed() async {
        let harness = CameraModelHarness(permission: .notDetermined, requestedPermission: .denied)
        harness.model.start()
        await harness.model.waitForWorkForTesting()

        #expect(await harness.permissions.requests() == [.camera])
        #expect(harness.factory.calls == 0)
        #expect(harness.model.state == .failed(.permissionRequired))
        #expect(harness.model.needsSettingsRecovery)
    }

    @Test
    func newestPreviewReplacesPreviousFrameAndCaptureIsDisabledUntilAFrameArrives() async throws {
        let capture = CameraCaptureDouble()
        let harness = CameraModelHarness(captures: [capture])
        let model = harness.model
        model.start()
        await model.waitForWorkForTesting()
        #expect(model.state == .previewing && model.canCapture == false)
        #expect(await harness.permissions.requests().isEmpty)
        model.takePhoto()
        #expect(await capture.photoRequests().isEmpty)

        let first = try CameraModelFixtures.frame(1)
        let newest = try CameraModelFixtures.frame(2)
        await Self.sendFrame(first, from: capture, to: model)
        #expect(model.frame == first && model.canCapture)
        await Self.sendFrame(newest, from: capture, to: model)
        #expect(model.frame == newest)
        model.stop()
        await model.waitForCleanupForTesting()
    }

    @Test
    func captureFreezesMirroringAndStopsCameraBeforeReviewWithoutImplicitExport() async throws {
        let capture = CameraCaptureDouble(
            initialFrame: try CameraModelFixtures.frame(1), blocksPhoto: true, blocksStop: true
        )
        let harness = CameraModelHarness(captures: [capture])
        let model = harness.model
        model.start()
        await model.waitForWorkForTesting()
        await Self.waitForFrame(in: model)
        model.mirrorsImage = false
        model.takePhoto()
        await capture.waitUntilPhotoRequested()
        model.mirrorsImage = true
        model.takePhoto()
        #expect(model.state == .capturing)
        #expect(await capture.photoRequests() == [false])

        await capture.releasePhoto()
        await capture.waitUntilStopRequested()
        #expect(model.state == .capturing && model.photo == nil)
        await capture.releaseStop()
        await model.waitForWorkForTesting()

        #expect(await capture.stops() == 1)
        #expect(model.state == .reviewing && model.photo == CameraModelFixtures.photo)
        #expect(model.frame == nil && model.canCapture == false)
        #expect(model.footerActions.first?.id == CameraActionID.save)
        #expect(model.showsFileExporter == false)
        #expect(await harness.copier.attempts().isEmpty)
        model.stop()
        #expect(model.photo == nil)
    }

    @Test
    func copyFailureKeepsReviewAndExplicitRetryCopiesExactPhotoBytes() async throws {
        let harness = try await Self.reviewingHarness()
        let model = harness.model
        await harness.copier.setFails(true)
        model.copyPhoto()
        await model.waitForWorkForTesting()

        #expect(model.photo == CameraModelFixtures.photo && model.state == .reviewing)
        #expect(model.isCopying == false && model.statusMessage?.contains("couldn’t be copied") == true)
        #expect(model.showsFileExporter == false)

        await harness.copier.setFails(false)
        model.copyPhoto()
        await model.waitForWorkForTesting()
        #expect(await harness.copier.attempts() == [CameraModelFixtures.photo.pngData, CameraModelFixtures.photo.pngData])
        #expect(model.statusMessage == "Photo copied." && model.isCopying == false)
        #expect(model.photo == CameraModelFixtures.photo)
        model.stop()
    }

    @Test
    func saveRequiresExplicitActionAndExportFailurePreservesPhotoForRetry() async throws {
        let harness = try await Self.reviewingHarness()
        let model = harness.model
        let beforeCancellation = model.statusMessage
        model.exportCompleted(.failure(NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError)))
        #expect(model.statusMessage == beforeCancellation)
        #expect(model.photo == CameraModelFixtures.photo && model.showsFileExporter == false)

        model.perform(CameraActionID.save)
        #expect(model.showsFileExporter)
        #expect(model.handleEscape())
        #expect(model.showsFileExporter == false && model.photo == CameraModelFixtures.photo)
        model.exportCompleted(.failure(CocoaError(.fileWriteNoPermission)))
        #expect(model.statusMessage?.contains("Choose another location") == true)
        #expect(model.state == .reviewing && model.photo == CameraModelFixtures.photo)
        model.perform(CameraActionID.save)
        #expect(model.showsFileExporter)
        model.exportCompleted(.success(URL(fileURLWithPath: "/tmp/generated-camera-photo.png")))
        #expect(model.statusMessage == "Photo saved.")
        #expect(await harness.copier.attempts().isEmpty)
        model.stop()
    }

    @Test
    func escapeStopsPreviewClearsPrivateStateAndRejectsLateFrames() async throws {
        let capture = CameraCaptureDouble(initialFrame: try CameraModelFixtures.frame(1))
        let harness = CameraModelHarness(captures: [capture])
        let model = harness.model
        model.start()
        await model.waitForWorkForTesting()
        await Self.waitForFrame(in: model)
        #expect(model.handleEscape())
        await model.waitForCleanupForTesting()
        await capture.waitUntilStreamTerminated()
        await capture.send(.frame(try CameraModelFixtures.frame(2)))

        #expect(model.state == .idle && model.frame == nil && model.photo == nil)
        #expect(model.devices.isEmpty && model.selectedDeviceID == nil)
        #expect(await capture.stops() == 1)
        #expect(model.handleEscape() == false)
        #expect(await harness.copier.attempts().isEmpty)
    }

    @Test
    func cancelledLateStartCannotReplaceOrStopANewerPreview() async throws {
        let oldCapture = CameraCaptureDouble(blocksStart: true)
        let latestFrame = try CameraModelFixtures.frame(9)
        let newCapture = CameraCaptureDouble(initialFrame: latestFrame)
        let harness = CameraModelHarness(captures: [oldCapture, newCapture])
        let model = harness.model
        model.start()
        await oldCapture.waitUntilStartRequested()
        let pending = model.pendingWorkForTesting()
        model.stop()
        model.start()
        await model.waitForWorkForTesting()
        await Self.waitForFrame(in: model)
        await oldCapture.releaseStart()
        await pending?.value

        #expect(harness.factory.calls == 2)
        #expect(model.state == .previewing && model.frame == latestFrame)
        #expect(await oldCapture.stops() >= 1)
        #expect(await newCapture.stops() == 0)
        model.stop()
        await model.waitForCleanupForTesting()
    }

    @Test
    func stoppedNonCooperativePhotoCannotRestoreReviewOrCopyAfterDismissal() async throws {
        let capture = CameraCaptureDouble(initialFrame: try CameraModelFixtures.frame(1), blocksPhoto: true)
        let harness = CameraModelHarness(captures: [capture])
        let model = harness.model
        model.start()
        await model.waitForWorkForTesting()
        await Self.waitForFrame(in: model)
        model.takePhoto()
        await capture.waitUntilPhotoRequested()
        let pending = model.pendingWorkForTesting()
        model.goBack()
        await model.waitForCleanupForTesting()
        await capture.releasePhoto()
        await pending?.value

        #expect(harness.navigation.backCount == 1)
        #expect(model.state == .idle && model.photo == nil && model.frame == nil)
        #expect(model.devices.isEmpty && model.showsFileExporter == false)
        #expect(await harness.copier.attempts().isEmpty)
        #expect(await capture.stops() >= 1)
    }

    @Test
    func deviceSelectionStartsAFreshCaptureWithTheSelectedDevice() async throws {
        let first = CameraCaptureDouble(initialFrame: try CameraModelFixtures.frame(1))
        let secondFrame = try CameraModelFixtures.frame(2)
        let second = CameraCaptureDouble(initialFrame: secondFrame)
        let harness = CameraModelHarness(captures: [first, second])
        let model = harness.model
        model.start()
        await model.waitForWorkForTesting()
        await Self.waitForFrame(in: model)
        model.selectDevice("unavailable-device")
        model.selectDevice(CameraModelFixtures.devices[0].id)
        #expect(harness.factory.calls == 1)

        model.selectDevice(CameraModelFixtures.devices[1].id)
        await model.waitForWorkForTesting()
        await model.waitForCleanupForTesting()
        await Self.waitForFrame(in: model)

        #expect(harness.factory.calls == 2)
        #expect(await first.stops() == 1)
        #expect(await second.startRequests() == [CameraModelFixtures.devices[1].id])
        #expect(model.selectedDeviceID == CameraModelFixtures.devices[1].id)
        #expect(model.state == .previewing && model.frame == secondFrame)
        model.stop()
        await model.waitForCleanupForTesting()
    }

    @Test(arguments: [false, true])
    func replacementWaitsForPreviousCameraShutdownBeforeCreatingANewCapture(switchDevice: Bool) async throws {
        let first = CameraCaptureDouble(initialFrame: try CameraModelFixtures.frame(1), blocksStop: true)
        let second = CameraCaptureDouble(initialFrame: try CameraModelFixtures.frame(2))
        let harness = CameraModelHarness(captures: [first, second])
        let model = harness.model
        model.start()
        await model.waitForWorkForTesting()
        await Self.waitForFrame(in: model)

        if switchDevice { model.selectDevice(CameraModelFixtures.devices[1].id) }
        else { model.stop(); model.start() }
        await first.waitUntilStopRequested()
        await Self.waitForPermissionCheck(in: model)

        #expect(model.state == .starting && model.frame == nil)
        #expect(harness.factory.calls == 1)
        #expect(await second.startRequests().isEmpty)
        await first.releaseStop()
        await model.waitForWorkForTesting()
        await Self.waitForFrame(in: model)

        #expect(harness.factory.calls == 2 && model.state == .previewing)
        #expect(await second.startRequests() == [switchDevice ? CameraModelFixtures.devices[1].id : nil])
        model.stop()
        await model.waitForCleanupForTesting()
    }

    @Test
    func escapeWhileWaitingForShutdownDoesNotOpenAReplacementCamera() async throws {
        let first = CameraCaptureDouble(initialFrame: try CameraModelFixtures.frame(1), blocksStop: true)
        let second = CameraCaptureDouble(initialFrame: try CameraModelFixtures.frame(2))
        let harness = CameraModelHarness(captures: [first, second])
        let model = harness.model
        model.start()
        await model.waitForWorkForTesting()
        await Self.waitForFrame(in: model)
        model.selectDevice(CameraModelFixtures.devices[1].id)
        await first.waitUntilStopRequested()
        await Self.waitForPermissionCheck(in: model)
        let pendingRestart = model.pendingWorkForTesting()

        #expect(model.handleEscape())
        #expect(model.state == .idle && model.frame == nil)
        await first.releaseStop()
        await pendingRestart?.value
        await model.waitForCleanupForTesting()
        #expect(harness.factory.calls == 1)
        #expect(await second.startRequests().isEmpty)
        #expect(model.state == .idle && model.photo == nil)

        // Cancellation does not poison the next explicit Start or cancel native cleanup.
        model.start()
        await model.waitForWorkForTesting()
        await Self.waitForFrame(in: model)
        #expect(harness.factory.calls == 2 && model.state == .previewing)
        model.stop()
        await model.waitForCleanupForTesting()
    }

    private static func waitForPermissionCheck(in model: CameraViewModel) async {
        guard model.state == .requestingPermission else { return }
        await withCheckedContinuation { continuation in
            withObservationTracking { _ = model.state } onChange: { continuation.resume() }
        }
    }

    private static func reviewingHarness() async throws -> CameraModelHarness {
        let capture = CameraCaptureDouble(initialFrame: try CameraModelFixtures.frame(1))
        let harness = CameraModelHarness(captures: [capture])
        harness.model.start()
        await harness.model.waitForWorkForTesting()
        await waitForFrame(in: harness.model)
        harness.model.takePhoto()
        await harness.model.waitForWorkForTesting()
        return harness
    }

    private static func waitForFrame(in model: CameraViewModel) async {
        if model.frame != nil { return }
        await withCheckedContinuation { continuation in
            withObservationTracking { _ = model.frame } onChange: { continuation.resume() }
        }
    }

    private static func sendFrame(
        _ frame: CameraPreviewFrame, from capture: CameraCaptureDouble, to model: CameraViewModel
    ) async {
        await withCheckedContinuation { continuation in
            withObservationTracking { _ = model.frame } onChange: { continuation.resume() }
            Task { await capture.send(.frame(frame)) }
        }
    }
}

@MainActor
private struct CameraModelHarness {
    let permissions: CameraModelPermissions
    let copier = CameraModelCopier()
    let opener = CameraModelPrivacyOpener()
    let navigation = CameraModelNavigation()
    let factory: CameraModelFactory
    let model: CameraViewModel

    init(
        permission: PermissionState = .authorized,
        requestedPermission: PermissionState = .authorized,
        captures: [CameraCaptureDouble] = []
    ) {
        permissions = CameraModelPermissions(state: permission, requestedState: requestedPermission)
        factory = CameraModelFactory(captures: captures)
        let factory = self.factory
        let navigation = self.navigation
        model = CameraViewModel(
            permissions: permissions, makeCapture: { factory.make() }, photoCopier: copier,
            privacySettingsOpener: opener, onGoBack: { navigation.backCount += 1 }
        )
    }
}

@MainActor
private final class CameraModelFactory {
    private let captures: [CameraCaptureDouble]
    private(set) var calls = 0
    init(captures: [CameraCaptureDouble]) { self.captures = captures }
    func make() -> any CameraCapturing {
        defer { calls += 1 }
        return captures.indices.contains(calls) ? captures[calls] : CameraCaptureDouble()
    }
}

@MainActor
private final class CameraModelNavigation {
    var backCount = 0
}

private actor CameraModelPermissions: PermissionServicing {
    private var currentState: PermissionState
    private let requestedState: PermissionState
    private var checkedKinds: [PermissionKind] = []
    private var requestedKinds: [PermissionKind] = []
    init(state: PermissionState, requestedState: PermissionState) {
        currentState = state
        self.requestedState = requestedState
    }
    func state(for kind: PermissionKind) -> PermissionState {
        checkedKinds.append(kind)
        return currentState
    }
    func request(_ kind: PermissionKind) -> PermissionState {
        requestedKinds.append(kind)
        currentState = requestedState
        return currentState
    }
    func checks() -> [PermissionKind] { checkedKinds }
    func requests() -> [PermissionKind] { requestedKinds }
}

private actor CameraModelCopier: CameraPhotoCopying {
    private var fails = false
    private var receivedData: [Data] = []
    func copyPNG(_ data: Data) throws {
        receivedData.append(data)
        if fails { throw CameraCaptureError.copyFailed }
    }
    func attempts() -> [Data] { receivedData }
    func setFails(_ value: Bool) { fails = value }
}

private actor CameraModelPrivacyOpener: PrivacySettingsOpening {
    private var panes: [PrivacySettingsPane] = []
    private var waiter: CheckedContinuation<PrivacySettingsPane, Never>?
    func open(_ pane: PrivacySettingsPane) {
        panes.append(pane)
        waiter?.resume(returning: pane)
        waiter = nil
    }
    func openedPanes() -> [PrivacySettingsPane] { panes }
    func nextOpenedPane() async -> PrivacySettingsPane {
        if let pane = panes.last { return pane }
        return await withCheckedContinuation { waiter = $0 }
    }
}

private actor CameraCaptureDouble: CameraCapturing {
    private let initialFrame: CameraPreviewFrame?
    private let blocksStart: Bool
    private let blocksPhoto: Bool
    private let blocksStop: Bool
    private var requestedDevices: [String?] = []
    private var requestedMirroring: [Bool] = []
    private var stopCount = 0
    private var events: AsyncStream<CameraCaptureEvent>.Continuation?
    private var startGate: CheckedContinuation<Void, Never>?
    private var photoGate: CheckedContinuation<Void, Never>?
    private var stopGate: CheckedContinuation<Void, Never>?
    private var startWaiter: CheckedContinuation<Void, Never>?
    private var photoWaiter: CheckedContinuation<Void, Never>?
    private var stopWaiter: CheckedContinuation<Void, Never>?
    private var streamTerminated = false
    private var terminationWaiter: CheckedContinuation<Void, Never>?

    init(
        initialFrame: CameraPreviewFrame? = nil, blocksStart: Bool = false,
        blocksPhoto: Bool = false, blocksStop: Bool = false
    ) {
        self.initialFrame = initialFrame
        self.blocksStart = blocksStart
        self.blocksPhoto = blocksPhoto
        self.blocksStop = blocksStop
    }

    func start(deviceID: String?) async -> CameraCaptureSession {
        requestedDevices.append(deviceID)
        let stream = AsyncStream<CameraCaptureEvent>.makeStream(bufferingPolicy: .bufferingNewest(1))
        events = stream.continuation
        events?.onTermination = { [weak self] _ in Task { await self?.markStreamTerminated() } }
        if let initialFrame { events?.yield(.frame(initialFrame)) }
        startWaiter?.resume()
        startWaiter = nil
        if blocksStart { await withCheckedContinuation { startGate = $0 } }
        return CameraCaptureSession(
            devices: CameraModelFixtures.devices,
            selectedDeviceID: deviceID ?? CameraModelFixtures.devices[0].id,
            events: stream.stream
        )
    }

    func takePhoto(mirrored: Bool) async -> CameraPhoto {
        requestedMirroring.append(mirrored)
        photoWaiter?.resume()
        photoWaiter = nil
        if blocksPhoto { await withCheckedContinuation { photoGate = $0 } }
        return CameraModelFixtures.photo
    }

    // Deliberately noncooperative: old streams and pending operations can still yield after stop.
    // Tests prove the model rejects them rather than depending on a cooperative native adapter.
    func stop() async {
        stopCount += 1
        stopWaiter?.resume()
        stopWaiter = nil
        if blocksStop { await withCheckedContinuation { stopGate = $0 } }
    }
    func send(_ event: CameraCaptureEvent) { events?.yield(event) }
    func startRequests() -> [String?] { requestedDevices }
    func photoRequests() -> [Bool] { requestedMirroring }
    func stops() -> Int { stopCount }
    func releaseStart() { startGate?.resume(); startGate = nil }
    func releasePhoto() { photoGate?.resume(); photoGate = nil }
    func releaseStop() { stopGate?.resume(); stopGate = nil }
    func waitUntilStartRequested() async {
        if requestedDevices.isEmpty == false { return }
        await withCheckedContinuation { startWaiter = $0 }
    }
    func waitUntilPhotoRequested() async {
        if requestedMirroring.isEmpty == false { return }
        await withCheckedContinuation { photoWaiter = $0 }
    }
    func waitUntilStreamTerminated() async {
        if streamTerminated { return }
        await withCheckedContinuation { terminationWaiter = $0 }
    }
    func waitUntilStopRequested() async {
        if stopCount > 0 { return }
        await withCheckedContinuation { stopWaiter = $0 }
    }
    private func markStreamTerminated() {
        streamTerminated = true
        terminationWaiter?.resume()
        terminationWaiter = nil
    }
}

nonisolated private enum CameraModelFixtures {
    static let devices = [CameraDevice(id: "built-in-fixture", name: "Built-in Fixture"),
                          CameraDevice(id: "external-fixture", name: "External Fixture")]
    static var photo: CameraPhoto {
        CameraPhoto(pngData: Data([137, 80, 78, 71, 1]), previewPNGData: Data([137, 80, 78, 71, 2]),
                    pixelWidth: 1, pixelHeight: 1)
    }
    static func frame(_ value: UInt8) throws -> CameraPreviewFrame {
        try CameraPreviewFrame(data: Data([value, 10, 20, 255]), pixelWidth: 1, pixelHeight: 1)
    }
}
