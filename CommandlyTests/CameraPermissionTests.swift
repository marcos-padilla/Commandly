import AVFoundation
import SecurityKit
import Testing
@testable import Commandly

@Suite("Camera permissions")
struct CameraPermissionTests {
    @Test @MainActor
    func constructionDoesNotCheckOrRequestCameraAccess() {
        let stub = CameraAuthorizationStub(status: .notDetermined)
        _ = makeService(stub)

        #expect(stub.preflightCount == 0)
        #expect(stub.requestCount == 0)
    }

    @Test @MainActor
    func cameraStateMapsEveryKnownStatusWithoutPrompting() async {
        let cases: [(AVAuthorizationStatus, PermissionState)] = [
            (.notDetermined, .notDetermined),
            (.denied, .denied),
            (.authorized, .authorized),
            (.restricted, .restricted)
        ]

        for (status, expectedState) in cases {
            let stub = CameraAuthorizationStub(status: status)
            let service = makeService(stub)

            #expect(await service.state(for: .camera) == expectedState)
            #expect(stub.preflightCount == 1)
            #expect(stub.requestCount == 0)
        }
    }

    @Test @MainActor
    func explicitRequestCanAuthorizeUndeterminedCameraAccess() async {
        let stub = CameraAuthorizationStub(status: .notDetermined, requestResult: true)
        let service = makeService(stub)

        #expect(await service.request(.camera) == .authorized)
        #expect(await service.state(for: .camera) == .authorized)
        #expect(stub.requestCount == 1)
    }

    @Test @MainActor
    func deniedCameraRequestDoesNotPromptAgain() async {
        let stub = CameraAuthorizationStub(status: .notDetermined, requestResult: false)
        let service = makeService(stub)

        #expect(await service.request(.camera) == .denied)
        #expect(await service.state(for: .camera) == .denied)
        #expect(await service.request(.camera) == .denied)
        #expect(stub.requestCount == 1)
    }

    @Test @MainActor
    func decidedCameraAccessNeverInvokesRequestClosure() async {
        let cases: [(AVAuthorizationStatus, PermissionState)] = [
            (.authorized, .authorized),
            (.denied, .denied),
            (.restricted, .restricted)
        ]

        for (status, expectedState) in cases {
            let stub = CameraAuthorizationStub(status: status)
            #expect(await makeService(stub).request(.camera) == expectedState)
            #expect(stub.requestCount == 0)
        }
    }

    @Test @MainActor
    func cameraPreflightReflectsRevocationAndSettingsRecovery() async {
        let stub = CameraAuthorizationStub(status: .authorized)
        let service = makeService(stub)
        #expect(await service.state(for: .camera) == .authorized)

        stub.status = .denied
        #expect(await service.state(for: .camera) == .denied)

        stub.status = .authorized
        #expect(await service.state(for: .camera) == .authorized)
        #expect(stub.requestCount == 0)
    }

    @Test @MainActor
    func cancelledCameraRequestDoesNotInvokeRequestClosure() async {
        let stub = CameraAuthorizationStub(status: .notDetermined)
        let service = makeService(stub)
        // MainActor serialization guarantees cancellation precedes execution without a delay.
        let request = Task { @MainActor in
            await service.request(.camera)
        }
        request.cancel()

        #expect(await request.value == .notDetermined)
        #expect(stub.requestCount == 0)
    }

    @MainActor
    private func makeService(_ stub: CameraAuthorizationStub) -> SystemPermissionService {
        SystemPermissionService(
            folderAccessStore: InMemoryFolderAccessStore(),
            cameraPreflight: { stub.preflight() },
            cameraRequest: { stub.request() }
        )
    }
}

@MainActor
private final class CameraAuthorizationStub {
    var status: AVAuthorizationStatus
    let requestResult: Bool
    private(set) var preflightCount = 0
    private(set) var requestCount = 0

    init(status: AVAuthorizationStatus, requestResult: Bool = false) {
        self.status = status
        self.requestResult = requestResult
    }

    func preflight() -> AVAuthorizationStatus {
        preflightCount += 1
        return status
    }

    func request() -> Bool {
        requestCount += 1
        status = requestResult ? .authorized : .denied
        return requestResult
    }
}
