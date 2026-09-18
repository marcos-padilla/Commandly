import CommandKit
import Foundation
import Infrastructure
import SecurityKit
import Testing
@testable import Commandly

@MainActor
@Suite("Screenshot model", .timeLimit(.minutes(1)))
struct ScreenshotViewModelTests {
    @Test
    func openingAndInactiveCopySaveActionsDoNotReadPermissionsOrConstructCapture() async {
        let harness = ScreenshotModelHarness()
        let model = harness.model
        model.copy()
        model.perform(ScreenshotActionID.save)
        #expect(model.image == nil && model.isCapturing == false && model.showsFileExporter == false)
        #expect(harness.factory.calls == 0)
        #expect(await harness.permissions.counts() == [0, 0])
        #expect(await harness.copier.contents().isEmpty)
    }

    @Test
    func windowAndDisplayUseExplicitPickerCaptureWithoutBroadScreenPermissionEvenWhenDenied() async throws {
        for kind in [ScreenshotKind.window, .display] {
            let harness = ScreenshotModelHarness(permission: .denied)
            let model = harness.model
            model.kind = kind
            model.showsCursor = true
            model.capture()
            await model.waitForWorkForTesting()
            #expect(harness.factory.calls == 1)
            #expect(await harness.permissions.counts() == [0, 0])
            #expect(harness.factory.created.first?.requests == [ScreenshotRequest(kind: kind, showsCursor: true)])
            #expect(model.image?.kind == kind && model.isCapturing == false)
            #expect(await harness.copier.contents().isEmpty && model.showsFileExporter == false)
            model.stop()
        }
    }

    @Test
    func regionChecksAndRequestsOnlyFromExplicitCaptureAndHonorsDenial() async {
        let granted = ScreenshotModelHarness(permission: .notDetermined)
        granted.model.capture()
        await granted.model.waitForWorkForTesting()
        #expect(await granted.permissions.counts() == [1, 1])
        #expect(granted.model.regionPermission == .authorized && granted.model.image?.kind == .region)
        for permission in [PermissionState.denied, .restricted] {
            let denied = ScreenshotModelHarness(permission: permission)
            denied.model.capture()
            await denied.model.waitForWorkForTesting()
            #expect(await denied.permissions.counts() == [1, 0])
            #expect(denied.factory.calls == 0 && denied.model.image == nil)
            #expect(denied.model.needsSettingsRecovery && denied.model.isCapturing == false)
        }
    }

    @Test
    func cancellationDuringPermissionPreflightCannotPromptOrConstructCaptureLater() async {
        let permissions = ScreenshotModelPermissions(state: .notDetermined, blocksCheck: true)
        let harness = ScreenshotModelHarness(permissions: permissions)
        harness.model.capture()
        await permissions.waitUntilChecked()
        let pending = harness.model.pendingWorkForTesting()
        harness.model.stop()
        await permissions.releaseCheck()
        await pending?.value
        #expect(await permissions.counts() == [1, 0])
        #expect(harness.factory.calls == 0 && harness.model.image == nil && harness.model.isCapturing == false)
    }

    @Test
    func cancelledLateCaptureCannotRestorePixelsOrReplaceANewerResult() async throws {
        let old = ScreenshotCaptureFake(blocks: true, seed: 1)
        let latest = ScreenshotCaptureFake(seed: 2)
        let harness = ScreenshotModelHarness(captures: [old, latest])
        let model = harness.model
        model.kind = .window
        model.capture()
        await old.waitUntilRequested()
        let oldTask = model.pendingWorkForTesting()
        #expect(model.handleEscape())
        #expect(old.cancelCount == 1 && model.image == nil)
        model.kind = .display
        model.capture()
        await model.waitForWorkForTesting()
        let latestImage = try #require(model.image)
        try old.release()
        await oldTask?.value
        #expect(model.image == latestImage && model.image?.kind == .display)
        #expect(latest.cancelCount == 0)
        #expect(await harness.copier.contents().isEmpty)
        model.stop()
    }

    @Test
    func screenshotReturnedForADifferentSelectionKindIsRejected() async {
        let fake = ScreenshotCaptureFake(forcedKind: .display)
        let harness = ScreenshotModelHarness(captures: [fake])
        harness.model.kind = .window
        harness.model.capture()
        await harness.model.waitForWorkForTesting()
        #expect(harness.model.image == nil && harness.model.errorMessage?.contains("processed") == true)
    }

    @Test
    func nativePermissionRevocationClearsResultAndOffersSettingsRecovery() async {
        let fake = ScreenshotCaptureFake(error: .permissionRequired)
        let harness = ScreenshotModelHarness(captures: [fake])
        harness.model.capture()
        await harness.model.waitForWorkForTesting()
        #expect(harness.model.image == nil && harness.model.regionPermission == .denied)
        #expect(harness.model.needsSettingsRecovery)
    }

    @Test
    func selectionCancellationIsNotAnErrorAndNeverWritesClipboard() async {
        let fake = ScreenshotCaptureFake(error: .cancelled)
        let harness = ScreenshotModelHarness(captures: [fake])
        harness.model.kind = .window
        harness.model.capture()
        await harness.model.waitForWorkForTesting()
        #expect(harness.model.errorMessage == nil && harness.model.image == nil && harness.model.isCapturing == false)
        #expect(await harness.copier.contents().isEmpty)
    }

    @Test
    func copyAndSaveAreExplicitAndFailuresKeepTheReviewedImageForRetry() async throws {
        let harness = ScreenshotModelHarness()
        let model = harness.model
        model.kind = .window
        model.capture()
        await model.waitForWorkForTesting()
        let image = try #require(model.image)
        #expect(await harness.copier.contents().isEmpty && model.showsFileExporter == false)
        await harness.copier.setFails(true)
        model.copy()
        await model.waitForWorkForTesting()
        #expect(model.image == image && model.isCopying == false && model.errorMessage?.contains("copied") == true)
        await harness.copier.setFails(false)
        model.copy()
        await model.waitForWorkForTesting()
        #expect(await harness.copier.contents() == [image.pngData, image.pngData])
        #expect(model.statusMessage == "Screenshot copied." && model.errorMessage == nil)
        model.perform(ScreenshotActionID.save)
        #expect(model.showsFileExporter)
        #expect(model.handleEscape() && model.image == image)
        model.exportCompleted(.failure(CocoaError(.fileWriteNoPermission)))
        #expect(model.image == image && model.errorMessage?.contains("saved") == true)
        model.stop()
        #expect(model.image == nil && model.showsFileExporter == false)
    }

    @Test
    func saveCancellationKeepsReviewAndLeavingClearsPrivateState() async throws {
        let harness = ScreenshotModelHarness()
        let model = harness.model
        model.kind = .display
        model.capture()
        await model.waitForWorkForTesting()
        let image = try #require(model.image)
        model.exportCompleted(.failure(NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError)))
        #expect(model.image == image && model.errorMessage == nil)
        model.goBack()
        #expect(harness.navigation.count == 1 && model.image == nil && model.isCapturing == false)
        #expect(model.handleEscape() == false)
    }
}

@MainActor
private struct ScreenshotModelHarness {
    let permissions: ScreenshotModelPermissions
    let copier = ScreenshotModelCopier()
    let factory: ScreenshotModelFactory
    let navigation = ScreenshotNavigationCount()
    let model: ScreenshotViewModel
    init(permission: PermissionState = .authorized, captures: [ScreenshotCaptureFake] = [], permissions: ScreenshotModelPermissions? = nil) {
        self.permissions = permissions ?? ScreenshotModelPermissions(state: permission)
        factory = ScreenshotModelFactory(captures: captures)
        let factory = self.factory
        let navigation = self.navigation
        model = ScreenshotViewModel(services: ScreenshotApplicationServices(
            permissions: self.permissions, makeCapture: { factory.make() }, copier: copier, privacySettings: InMemoryPrivacySettingsOpener()
        ), onGoBack: { navigation.count += 1 })
    }
}
@MainActor private final class ScreenshotNavigationCount { var count = 0 }
@MainActor private final class ScreenshotModelFactory {
    private let captures: [ScreenshotCaptureFake]
    private(set) var calls = 0
    private(set) var created: [ScreenshotCaptureFake] = []
    init(captures: [ScreenshotCaptureFake]) { self.captures = captures }
    func make() -> any ScreenshotCapturing {
        let value = captures.indices.contains(calls) ? captures[calls] : ScreenshotCaptureFake()
        calls += 1
        created.append(value)
        return value
    }
}
@MainActor private final class ScreenshotCaptureFake: ScreenshotCapturing {
    let blocks: Bool
    let seed: UInt8
    let error: ScreenshotCaptureError?
    let forcedKind: ScreenshotKind?
    private(set) var requests: [ScreenshotRequest] = []
    private(set) var cancelCount = 0
    private var pending: CheckedContinuation<ScreenshotImage, Error>?
    private var waiter: CheckedContinuation<Void, Never>?
    init(blocks: Bool = false, seed: UInt8 = 3, error: ScreenshotCaptureError? = nil, forcedKind: ScreenshotKind? = nil) {
        self.blocks = blocks; self.seed = seed; self.error = error; self.forcedKind = forcedKind
    }
    func capture(_ request: ScreenshotRequest) async throws -> ScreenshotImage {
        requests.append(request)
        waiter?.resume(); waiter = nil
        if let error { throw error }
        if blocks { return try await withCheckedThrowingContinuation { pending = $0 } }
        return try result(kind: request.kind)
    }
    // Noncooperative on purpose: tests explicitly release old work after cancel.
    func cancel() { cancelCount += 1 }
    func waitUntilRequested() async {
        if requests.isEmpty == false { return }
        await withCheckedContinuation { waiter = $0 }
    }
    func release() throws {
        let value = try result(kind: requests.last?.kind ?? .region)
        pending?.resume(returning: value); pending = nil
    }
    private func result(kind: ScreenshotKind) throws -> ScreenshotImage {
        try ScreenshotImage(pngData: Data([137, 80, 78, 71, seed]), previewPNGData: Data([seed]),
                            kind: forcedKind ?? kind, pixelWidth: 20, pixelHeight: 10)
    }
}
private actor ScreenshotModelCopier: ScreenshotCopying {
    private var values: [Data] = []
    private var fails = false
    func copyPNG(_ data: Data) throws { values.append(data); if fails { throw ScreenshotCaptureError.copyFailed } }
    func contents() -> [Data] { values }
    func setFails(_ value: Bool) { fails = value }
}
private actor ScreenshotModelPermissions: PermissionServicing {
    private var state: PermissionState
    private let blocksCheck: Bool
    private var checkCount = 0
    private var requestCount = 0
    private var pending: CheckedContinuation<Void, Never>?
    private var waiter: CheckedContinuation<Void, Never>?
    init(state: PermissionState, blocksCheck: Bool = false) { self.state = state; self.blocksCheck = blocksCheck }
    func state(for kind: PermissionKind) async -> PermissionState {
        checkCount += 1
        waiter?.resume(); waiter = nil
        if blocksCheck { await withCheckedContinuation { pending = $0 } }
        return state
    }
    func request(_ kind: PermissionKind) -> PermissionState { requestCount += 1; state = .authorized; return state }
    func counts() -> [Int] { [checkCount, requestCount] }
    func waitUntilChecked() async { if checkCount > 0 { return }; await withCheckedContinuation { waiter = $0 } }
    func releaseCheck() { pending?.resume(); pending = nil }
}
