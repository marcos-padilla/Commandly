import Foundation
import Infrastructure
import Testing
@testable import Commandly

@Suite("Camera photo processing lifecycle", .timeLimit(.minutes(1)))
@MainActor
struct NativeCameraPhotoProcessingTests {
    @Test
    func stopCancelsSuspendedEncodingAndLateCompletionCannotFinishANewerPhoto() async throws {
        let processor = SuspendedCameraPhotoProcessor()
        let service = NativeCameraCaptureService(photoProcessor: processor)
        let oldRequest = Task { try await service.processPhotoForTesting(Data([1]), mirrored: true) }
        await processor.waitUntilStarted(1)
        let oldWorker = try #require(await service.pendingPhotoProcessingForTesting())

        // Neither Stop nor the request's cancellation result waits for noncooperative encoding.
        await service.stop()
        await Self.expectCancellation(of: oldRequest)
        await processor.waitUntilCancelled(0)
        #expect(await service.pendingPhotoProcessingForTesting() == nil)

        let newRequest = Task { try await service.processPhotoForTesting(Data([2]), mirrored: false) }
        await processor.waitUntilStarted(2)
        await processor.release(0, result: .success(Self.photo(1)))
        await oldWorker.value
        #expect(await service.pendingPhotoProcessingForTesting() != nil)
        await processor.release(1, result: .success(Self.photo(2)))
        #expect(try await newRequest.value == Self.photo(2))
        #expect(await processor.receivedData() == [Data([1]), Data([2])])
        #expect(await processor.receivedMirroring() == [true, false])
        #expect(await service.pendingPhotoProcessingForTesting() == nil)
        await service.stop()
    }

    @Test
    func cancellingThePhotoCallerCancelsItsWorkerWithoutWaitingForEncoding() async throws {
        let processor = SuspendedCameraPhotoProcessor()
        let service = NativeCameraCaptureService(photoProcessor: processor)
        let request = Task { try await service.processPhotoForTesting(Data([3]), mirrored: false) }
        await processor.waitUntilStarted(1)
        let worker = try #require(await service.pendingPhotoProcessingForTesting())
        request.cancel()
        await Self.expectCancellation(of: request)
        await processor.waitUntilCancelled(0)
        #expect(await service.pendingPhotoProcessingForTesting() == nil)

        await processor.release(0, result: .success(Self.photo(3)))
        await worker.value
        #expect(await service.pendingPhotoProcessingForTesting() == nil)
        await service.stop()
    }

    @Test
    func encodingFailureClearsTheRequestAndAllowsAnExplicitRetry() async throws {
        let processor = SuspendedCameraPhotoProcessor()
        let service = NativeCameraCaptureService(photoProcessor: processor)
        let failedRequest = Task { try await service.processPhotoForTesting(Data([4]), mirrored: true) }
        await processor.waitUntilStarted(1)
        await processor.release(0, result: .failure(CocoaError(.coderInvalidValue)))
        do {
            _ = try await failedRequest.value
            Issue.record("Expected the safe encoding failure")
        } catch {
            #expect(error as? CameraCaptureError == .encodingFailed)
        }
        #expect(await service.pendingPhotoProcessingForTesting() == nil)

        let retry = Task { try await service.processPhotoForTesting(Data([5]), mirrored: true) }
        await processor.waitUntilStarted(2)
        await processor.release(1, result: .success(Self.photo(5)))
        #expect(try await retry.value == Self.photo(5))
        await service.stop()
    }

    private static func expectCancellation(of request: Task<CameraPhoto, Error>) async {
        do {
            _ = try await request.value
            Issue.record("A cancelled photo must not become a reviewed photo")
        } catch { #expect(error is CancellationError) }
    }

    private static func photo(_ byte: UInt8) -> CameraPhoto {
        CameraPhoto(pngData: Data([byte]), previewPNGData: Data([byte]), pixelWidth: 1, pixelHeight: 1)
    }
}

/// Immutable fixture bytes only. Rendering deliberately ignores cancellation until explicitly
/// released so tests can prove native cleanup and newer request identities remain independent.
private actor SuspendedCameraPhotoProcessor: CameraPhotoProcessing {
    private var data: [Data] = []
    private var mirroring: [Bool] = []
    private var gates: [Int: CheckedContinuation<Result<CameraPhoto, Error>, Never>] = [:]
    private var startedWaiters: [Int: CheckedContinuation<Void, Never>] = [:]
    private var cancelled: Set<Int> = []
    private var cancelledWaiters: [Int: CheckedContinuation<Void, Never>] = [:]

    func render(_ bytes: Data, mirrored: Bool) async throws -> CameraPhoto {
        let index = data.count
        data.append(bytes)
        mirroring.append(mirrored)
        return try await withTaskCancellationHandler {
            let result = await withCheckedContinuation { continuation in
                gates[index] = continuation
                startedWaiters.removeValue(forKey: data.count)?.resume()
            }
            return try result.get()
        } onCancel: {
            Task { await self.markCancelled(index) }
        }
    }

    func waitUntilStarted(_ count: Int) async {
        if data.count >= count { return }
        await withCheckedContinuation { startedWaiters[count] = $0 }
    }

    func waitUntilCancelled(_ index: Int) async {
        if cancelled.contains(index) { return }
        await withCheckedContinuation { cancelledWaiters[index] = $0 }
    }

    func release(_ index: Int, result: Result<CameraPhoto, Error>) {
        gates.removeValue(forKey: index)?.resume(returning: result)
    }

    func receivedData() -> [Data] { data }
    func receivedMirroring() -> [Bool] { mirroring }

    private func markCancelled(_ index: Int) {
        cancelled.insert(index)
        cancelledWaiters.removeValue(forKey: index)?.resume()
    }
}
