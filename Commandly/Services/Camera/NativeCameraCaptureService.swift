import AVFoundation
import CoreGraphics
import CoreImage
import Dispatch
import Foundation
import Infrastructure

/// All capture configuration, start/stop, and video callbacks share one serial executor.
/// No AVCaptureSession, sample buffer, or pixel buffer crosses into UI state.
actor NativeCameraCaptureService: CameraCapturing {
    nonisolated private let captureQueue = DispatchSerialQueue(label: "com.commandly.camera.capture", qos: .userInitiated)
    nonisolated var unownedExecutor: UnownedSerialExecutor { captureQueue.asUnownedSerialExecutor() }

    private var session: AVCaptureSession?
    private var currentSessionID: UUID?
    private var events: AsyncStream<CameraCaptureEvent>.Continuation?
    private var videoDelegate: NativeCameraVideoDelegate?
    private var photoOutput: AVCapturePhotoOutput?
    private var photoDelegate: NativeCameraPhotoDelegate?
    private var photoContinuation: CheckedContinuation<CameraPhoto, Error>?
    private var photoID: UUID?
    private var photoIsMirrored = false
    private let photoProcessor: any CameraPhotoProcessing
    private var photoProcessing: Task<Void, Never>?
    private var observerTokens: [NSObjectProtocol] = []

    // Initialization constructs no AVCaptureSession, device discovery, or device input.
    init(photoProcessor: any CameraPhotoProcessing = NativeCameraPhotoProcessor()) {
        self.photoProcessor = photoProcessor
    }

    func start(deviceID: String?) throws -> CameraCaptureSession {
        try Task.checkCancellation()
        stop()
        guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else {
            throw CameraCaptureError.permissionRequired
        }
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .external], mediaType: .video, position: .unspecified
        )
        let available = discovery.devices
        guard available.isEmpty == false else { throw CameraCaptureError.noCamera }
        let preferred = AVCaptureDevice.default(for: .video)?.uniqueID
        let selected = deviceID.flatMap { id in available.first { $0.uniqueID == id } }
            ?? (deviceID == nil ? available.first { $0.uniqueID == preferred } ?? available.first : nil)
        guard let selected else { throw CameraCaptureError.deviceUnavailable }
        let newSession = AVCaptureSession()
        let output = AVCapturePhotoOutput()
        let videoOutput = AVCaptureVideoDataOutput()
        let sessionID = UUID()
        let stream = AsyncStream<CameraCaptureEvent>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let delegate = NativeCameraVideoDelegate(events: stream.continuation, onFailure: { [weak self] in
            Task { await self?.fail(.invalidFrame, sessionID: sessionID) }
        })
        do {
            try configure(newSession, device: selected, videoOutput: videoOutput, photoOutput: output)
        } catch {
            throw CameraCaptureError.startFailed
        }
        session = newSession
        currentSessionID = sessionID
        stream.continuation.onTermination = { [weak self] _ in
            Task { await self?.stop(sessionID: sessionID) }
        }
        events = stream.continuation
        photoOutput = output
        videoDelegate = delegate
        videoOutput.setSampleBufferDelegate(delegate, queue: captureQueue)
        observe(newSession, device: selected, sessionID: sessionID)
        // startRunning is synchronous and can block; the custom executor keeps it off MainActor.
        // The configuration transaction is already committed before this call.
        newSession.startRunning()
        guard newSession.isRunning else { stop(); throw CameraCaptureError.startFailed }
        do { try Task.checkCancellation() }
        catch { stop(); throw error }
        return CameraCaptureSession(
            devices: available.map { CameraDevice(id: $0.uniqueID, name: $0.localizedName) },
            selectedDeviceID: selected.uniqueID,
            events: stream.stream
        )
    }

    func takePhoto(mirrored: Bool) async throws -> CameraPhoto {
        try Task.checkCancellation()
        guard session?.isRunning == true, photoContinuation == nil, let output = photoOutput,
              output.connection(with: .video)?.isEnabled == true else { throw CameraCaptureError.captureUnavailable }
        let requestID = UUID()
        let delegate = NativeCameraPhotoDelegate(owner: self, requestID: requestID)
        photoID = requestID
        photoDelegate = delegate
        photoIsMirrored = mirrored
        let settings = AVCapturePhotoSettings()
        let photo = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                photoContinuation = continuation
                output.capturePhoto(with: settings, delegate: delegate)
            }
        } onCancel: {
            // The cancellation callback cannot synchronously enter the capture executor.
            Task { await self.cancelPhoto(requestID: requestID) }
        }
        try Task.checkCancellation()
        return photo
    }

    func stop() {
        // Cancel the independent byte worker before any synchronous native shutdown.
        finishPhoto(.failure(CancellationError()))
        currentSessionID = nil
        observerTokens.forEach(NotificationCenter.default.removeObserver)
        observerTokens.removeAll()
        if let session {
            for output in session.outputs {
                (output as? AVCaptureVideoDataOutput)?.setSampleBufferDelegate(nil, queue: nil)
            }
            if session.isRunning { session.stopRunning() }
        }
        session = nil
        photoOutput = nil
        videoDelegate = nil
        events?.yield(.stopped)
        events?.finish()
        events = nil
    }

    fileprivate func receivedPhoto(_ data: Data?, requestID: UUID) {
        guard photoID == requestID, photoContinuation != nil else { return }
        guard let data else { finishPhoto(.failure(CameraCaptureError.captureFailed)); return }
        guard photoProcessing == nil else { return }
        let mirrored = photoIsMirrored
        // Only immutable bytes cross executors. This tracked task, not the delegate callback's
        // delivery task, owns encoding and is cancelled by Stop or by the photo request caller.
        photoProcessing = Task { [weak self, photoProcessor] in
            do {
                let photo = try await photoProcessor.render(data, mirrored: mirrored)
                try Task.checkCancellation()
                await self?.processedPhoto(.success(photo), requestID: requestID)
            } catch {
                let failure: Error = error is CancellationError ? CancellationError() : CameraCaptureError.encodingFailed
                await self?.processedPhoto(.failure(failure), requestID: requestID)
            }
        }
    }

    private func processedPhoto(_ result: Result<CameraPhoto, Error>, requestID: UUID) {
        guard photoID == requestID else { return }
        photoProcessing = nil
        finishPhoto(result)
    }

    #if DEBUG
    /// Enters the real callback/processing/stop path with generated bytes, without camera access.
    func processPhotoForTesting(_ data: Data, mirrored: Bool) async throws -> CameraPhoto {
        try Task.checkCancellation()
        guard photoContinuation == nil else { throw CameraCaptureError.captureUnavailable }
        let requestID = UUID()
        photoID = requestID
        photoIsMirrored = mirrored
        let photo = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                photoContinuation = continuation
                receivedPhoto(data, requestID: requestID)
            }
        } onCancel: {
            Task { await self.cancelPhoto(requestID: requestID) }
        }
        try Task.checkCancellation()
        return photo
    }

    func pendingPhotoProcessingForTesting() -> Task<Void, Never>? { photoProcessing }
    #endif

    private func configure(_ session: AVCaptureSession, device: AVCaptureDevice,
                           videoOutput: AVCaptureVideoDataOutput, photoOutput: AVCapturePhotoOutput) throws {
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        if session.canSetSessionPreset(.hd1280x720) { session.sessionPreset = .hd1280x720 }
        else if session.canSetSessionPreset(.medium) { session.sessionPreset = .medium }
        else { throw CameraCaptureError.startFailed }
        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else {
            throw CameraCaptureError.startFailed
        }
        session.addInput(input)
        guard session.canAddOutput(videoOutput), session.canAddOutput(photoOutput) else {
            throw CameraCaptureError.startFailed
        }
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        session.addOutput(videoOutput)
        session.addOutput(photoOutput)
        for connection in [videoOutput.connection(with: .video), photoOutput.connection(with: .video)].compactMap({ $0 }) {
            if connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = false
            }
        }
        // Video only: no microphone device/input, audio output, or audio authorization request.
    }

    private func observe(_ session: AVCaptureSession, device: AVCaptureDevice, sessionID: UUID) {
        let sessionNames: [Notification.Name] = [AVCaptureSession.runtimeErrorNotification, AVCaptureSession.wasInterruptedNotification]
        for name in sessionNames {
            observerTokens.append(NotificationCenter.default.addObserver(forName: name, object: session, queue: nil) { [weak self] _ in
                Task { await self?.fail(.interrupted, sessionID: sessionID) }
            })
        }
        observerTokens.append(NotificationCenter.default.addObserver(
            forName: AVCaptureDevice.wasDisconnectedNotification, object: device, queue: nil
        ) { [weak self] _ in
            Task { await self?.fail(.deviceUnavailable, sessionID: sessionID) }
        })
    }

    private func fail(_ error: CameraCaptureError, sessionID: UUID) {
        guard currentSessionID == sessionID else { return }
        let continuation = events
        events = nil
        stop()
        continuation?.yield(.failed(error))
        continuation?.finish()
    }

    private func stop(sessionID: UUID) {
        guard currentSessionID == sessionID else { return }
        stop()
    }

    private func cancelPhoto(requestID: UUID) {
        guard photoID == requestID else { return }
        finishPhoto(.failure(CancellationError()))
    }

    private func finishPhoto(_ result: Result<CameraPhoto, Error>) {
        photoProcessing?.cancel()
        photoProcessing = nil
        let continuation = photoContinuation
        photoContinuation = nil
        photoDelegate = nil
        photoID = nil
        continuation?.resume(with: result)
    }
}

/// AVFoundation calls this non-Sendable delegate only on the capture actor's serial queue.
/// Its processing state is created lazily on that queue and never accessed by another executor.
/// Native sample/pixel buffers remain inside the synchronous callback; only bounded immutable
/// frame bytes enter the Sendable stream. Finishing an old session drops any late callback yield.
nonisolated private final class NativeCameraVideoDelegate: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    private let events: AsyncStream<CameraCaptureEvent>.Continuation
    private let onFailure: @Sendable () -> Void
    private var lastFrameTimestamp: Double?
    private lazy var imageContext = CIContext(options: [.cacheIntermediates: false])

    init(events: AsyncStream<CameraCaptureEvent>.Continuation, onFailure: @escaping @Sendable () -> Void) {
        self.events = events
        self.onFailure = onFailure
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let timestamp = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
        guard timestamp.isFinite else { return }
        if let lastFrameTimestamp, timestamp >= lastFrameTimestamp, timestamp - lastFrameTimestamp < 1.0 / 12 { return }
        lastFrameTimestamp = timestamp
        guard let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let input = CIImage(cvPixelBuffer: buffer)
        let longest = max(input.extent.width, input.extent.height)
        guard longest > 0, longest <= 16_384 else { return }
        let scale = min(1, 960 / longest)
        let scaled = input.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        // Explicit integral dimensions avoid a floating-point ceil producing a 961px edge.
        let width = min(960, max(1, Int((input.extent.width * scale).rounded())))
        let height = min(960, max(1, Int((input.extent.height * scale).rounded())))
        guard let image = imageContext.createCGImage(scaled, from: CGRect(x: 0, y: 0, width: width, height: height)) else { return }
        do { events.yield(.frame(try CameraFrameRenderer.frame(from: image))) }
        catch { onFailure() }
    }
}

/// Photo callbacks convert their native object to immutable Data before entering the capture actor.
nonisolated private final class NativeCameraPhotoDelegate: NSObject, AVCapturePhotoCaptureDelegate {
    private weak var owner: NativeCameraCaptureService?
    private let requestID: UUID
    init(owner: NativeCameraCaptureService, requestID: UUID) { self.owner = owner; self.requestID = requestID }
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        let data = error == nil ? photo.fileDataRepresentation() : nil
        Task { [weak owner, requestID] in await owner?.receivedPhoto(data, requestID: requestID) }
    }
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings, error: Error?) {
        guard error != nil else { return }
        Task { [weak owner, requestID] in await owner?.receivedPhoto(nil, requestID: requestID) }
    }
}
