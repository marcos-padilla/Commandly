import AVFoundation
import CoreMedia
import Dispatch
import Foundation
import Infrastructure
import Speech

/// One shared serial owner for microphone capture, assets, and pending operations. Construction is inert.
actor NativeDictationService {
    nonisolated private let queue = DispatchSerialQueue(label: "com.commandly.dictation", qos: .userInitiated)
    nonisolated var unownedExecutor: UnownedSerialExecutor { queue.asUnownedSerialExecutor() }
    private var requestID: UUID?
    private var assetOperationID: UUID?
    private var session: AVCaptureSession?
    private var provider: CaptureInputSequenceProvider?
    private var analyzer: SpeechAnalyzer?
    private var analysisTask: Task<CMTime?, Error>?
    private var resultsTask: Task<Void, Never>?
    private var finishTask: Task<Void, Error>?
    private var events: AsyncStream<DictationCaptureEvent>.Continuation?
    private var transcript: DictationTranscript?
    private var timer: DispatchSourceTimer?
    private var observations: [NSObjectProtocol] = []
    private var reachedLimit = false
    private var ending = false
    private var isCancelling = false
    private var captureFailure: DictationError?

    func languages() async throws -> [DictationLanguage] {
        let enhanced = SpeechTranscriber.isAvailable ? await SpeechTranscriber.supportedLocales : []
        let standard = await DictationTranscriber.supportedLocales
        try Task.checkCancellation()
        var values: [String: DictationLanguage] = [:]
        for (locales, engine) in [(standard, DictationRecognitionEngine.dictationTranscriber), (enhanced, .speechTranscriber)] {
            for locale in locales {
                let id = locale.identifier(.bcp47)
                values[id] = DictationLanguage(id: id, name: Locale.current.localizedString(forIdentifier: id) ?? id, engine: engine)
            }
        }
        return values.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    func preferredLanguageID() async -> String? {
        if SpeechTranscriber.isAvailable, let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale.current) { return locale.identifier(.bcp47) }
        return await DictationTranscriber.supportedLocale(equivalentTo: Locale.current)?.identifier(.bcp47)
    }
    func availability(for language: DictationLanguage) async throws -> DictationModelAvailability {
        let module = try await NativeDictationModule.make(language)
        try Task.checkCancellation()
        switch await AssetInventory.status(forModules: [module.module]) {
        case .unsupported: return .unsupported
        case .supported: return .downloadRequired
        case .downloading: return .downloading
        case .installed: return .installed
        @unknown default: return .unsupported
        }
    }
    func download(language: DictationLanguage) async throws {
        guard requestID == nil, assetOperationID == nil else { throw DictationError.busy }
        let id = UUID(); assetOperationID = id
        defer { if assetOperationID == id { assetOperationID = nil } }
        do {
            let module = try await NativeDictationModule.make(language)
            try Task.checkCancellation()
            // Only this explicit download may rotate this app's unused locale reservations.
            // No capture can start until this operation finishes; other apps retain their reservations.
            let reserved = await AssetInventory.reservedLocales
            if !reserved.contains(module.locale), reserved.count >= AssetInventory.maximumReservedLocales {
                if let previous = reserved.first { _ = await AssetInventory.release(reservedLocale: previous) }
            }
            try Task.checkCancellation()
            if let request = try await AssetInventory.assetInstallationRequest(supporting: [module.module]) {
                try await withTaskCancellationHandler { try await request.downloadAndInstall() }
                onCancel: { request.progress.cancel() }
            }
            try Task.checkCancellation()
        } catch is CancellationError { throw CancellationError() }
        catch let error as DictationError { throw error }
        catch { throw DictationError.downloadFailed }
    }
    func microphones() throws -> [DictationMicrophone] {
        try Task.checkCancellation()
        let preferred = AVCaptureDevice.default(for: .audio)?.uniqueID
        return AVCaptureDevice.DiscoverySession(deviceTypes: [.microphone, .external], mediaType: .audio, position: .unspecified).devices
            .map { DictationMicrophone(id: $0.uniqueID, name: $0.localizedName, isDefault: $0.uniqueID == preferred) }
    }
    func start(_ request: DictationCaptureRequest) async throws -> DictationCaptureSession {
        guard requestID == nil, assetOperationID == nil else { throw DictationError.busy }
        requestID = request.id; ending = false; isCancelling = false; reachedLimit = false; captureFailure = nil; transcript = nil
        do {
            guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else { throw DictationError.permissionRequired }
            let module = try await NativeDictationModule.make(request.language)
            try validatePending(request.id)
            guard await AssetInventory.status(forModules: [module.module]) == .installed else { throw DictationError.modelDownloadRequired }
            try validatePending(request.id)
            _ = try await AssetInventory.reserve(locale: module.locale)
            try validatePending(request.id)
            guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [module.module]) else { throw DictationError.modelUnavailable }
            try validatePending(request.id)
            let available = AVCaptureDevice.DiscoverySession(deviceTypes: [.microphone, .external], mediaType: .audio, position: .unspecified).devices
            let device = request.microphoneID.flatMap { id in available.first { $0.uniqueID == id } }
                ?? (request.microphoneID == nil ? AVCaptureDevice.default(for: .audio) : nil)
            guard let device else { throw available.isEmpty ? DictationError.noMicrophone : DictationError.microphoneUnavailable }
            guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else { throw DictationError.permissionRequired }
            let capture = AVCaptureSession()
            let input = try AVCaptureDeviceInput(device: device)
            let provider = try CaptureInputSequenceProvider(session: capture, analyzerFormat: format, priority: .userInitiated)
            capture.beginConfiguration()
            guard capture.canAddInput(input), capture.canAddOutput(provider.captureAudioDataOutput) else {
                capture.commitConfiguration(); throw DictationError.startFailed
            }
            capture.addInput(input); capture.addOutput(provider.captureAudioDataOutput); capture.commitConfiguration()
            let analyzer = SpeechAnalyzer(modules: [module.module], options: .init(priority: .userInitiated, modelRetention: .whileInUse))
            let pair = AsyncStream<DictationCaptureEvent>.makeStream(bufferingPolicy: .bufferingNewest(1))
            let audio = provider.analyzerInputs
            self.session = capture; self.provider = provider; self.analyzer = analyzer; events = pair.continuation
            pair.continuation.onTermination = { [weak self] _ in Task { await self?.cancel(requestID: request.id) } }
            resultsTask = Task { [weak self] in
                do { try await module.collect { [weak self] value in await self?.received(value, id: request.id) } }
                catch {
                    guard !Task.isCancelled else { return }
                    await self?.failed((error as? DictationError) ?? .recognitionFailed, id: request.id)
                }
            }
            analysisTask = Task { [weak self] in
                do {
                    let last = try await analyzer.analyzeSequence(audio)
                    await self?.analysisEnded(id: request.id)
                    return last
                } catch {
                    if !Task.isCancelled { await self?.failed(.recognitionFailed, id: request.id) }
                    throw error
                }
            }
            observe(capture, device: device, id: request.id)
            try validatePending(request.id)
            // Synchronous device start/stop stays on this serial executor, never MainActor.
            capture.startRunning()
            guard capture.isRunning else { throw DictationError.startFailed }
            try validatePending(request.id)
            armDurationLimit(id: request.id)
            return DictationCaptureSession(id: request.id,
                microphone: DictationMicrophone(id: device.uniqueID, name: device.localizedName, isDefault: device.uniqueID == AVCaptureDevice.default(for: .audio)?.uniqueID), events: pair.stream)
        } catch {
            await cancel(requestID: request.id)
            if error is CancellationError { throw CancellationError() }
            throw (error as? DictationError) ?? .startFailed
        }
    }
    private func validatePending(_ id: UUID) throws {
        try Task.checkCancellation()
        guard requestID == id, !ending else { throw CancellationError() }
    }
    private func analysisEnded(id: UUID) {
        // A disconnected or unexpectedly ended sequence must not leave a silent microphone running.
        guard requestID == id, !ending else { return }
        failed(.recognitionFailed, id: id)
    }
    private func received(_ value: DictationTranscript, id: UUID) {
        guard requestID == id, captureFailure == nil else { return }
        transcript = value; events?.yield(.transcript(value))
    }
    func finish(requestID id: UUID) async throws {
        guard requestID == id else { return }
        if let finishTask { try await finishTask.value; return }
        guard session != nil else { await cancel(requestID: id); return }
        ending = true; stopMicrophone()
        analysisTask?.cancel() // Ends only native input analysis. The result reader stays uncancelled.
        let task = Task { try await finalize(id: id) }
        finishTask = task
        try await task.value
    }
    private func finalize(id: UUID) async throws {
        guard let analyzer else { clear(id: id); return }
        do {
            let last = try await analysisTask?.value
            if let last { try await analyzer.finalizeAndFinish(through: last) }
            else { await analyzer.cancelAndFinishNow() }
            await resultsTask?.value
            guard requestID == id, !isCancelling else { return }
            if let failure = captureFailure { events?.yield(.failed(failure, transcript: transcript)) }
            else if let transcript { events?.yield(.finished(transcript, reachedDurationLimit: reachedLimit)) }
            else { events?.yield(.finished(try DictationTranscript(text: "", containsProvisionalText: false), reachedDurationLimit: reachedLimit)) }
            clear(id: id)
        } catch {
            await analyzer.cancelAndFinishNow(); resultsTask?.cancel(); await resultsTask?.value
            guard requestID == id, !isCancelling else { return }
            events?.yield(.failed((error as? DictationError) ?? .recognitionFailed, transcript: transcript)); clear(id: id)
            throw (error as? DictationError) ?? .recognitionFailed
        }
    }
    func cancel(requestID id: UUID) async {
        guard requestID == id else { return }
        ending = true; isCancelling = true; stopMicrophone(); analysisTask?.cancel(); resultsTask?.cancel(); finishTask?.cancel()
        await analyzer?.cancelAndFinishNow()
        _ = await analysisTask?.result
        await resultsTask?.value
        _ = await finishTask?.result
        guard requestID == id else { return }
        events?.yield(.cancelled); clear(id: id)
    }
    private func failed(_ error: DictationError, id: UUID) {
        guard requestID == id, captureFailure == nil, !isCancelling else { return }
        captureFailure = error; stopMicrophone(); analysisTask?.cancel()
        // This separate tracked termination task never waits on itself when a result reader fails.
        if finishTask == nil {
            ending = true
            finishTask = Task { try await finalize(id: id) }
        }
    }
    private func stopMicrophone() {
        timer?.cancel(); timer = nil
        if let session, session.isRunning { session.stopRunning() }
    }
    private func clear(id: UUID) {
        guard requestID == id else { return }
        stopMicrophone()
        observations.forEach(NotificationCenter.default.removeObserver); observations = []
        requestID = nil; session = nil; provider = nil; analyzer = nil; analysisTask = nil; resultsTask = nil; finishTask = nil
        events?.finish(); events = nil; ending = false; isCancelling = false; transcript = nil; captureFailure = nil
    }
    private func armDurationLimit(id: UUID) {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 300)
        timer.setEventHandler { [weak self] in Task { await self?.limitReached(id: id) } }
        self.timer = timer; timer.resume()
    }
    private func limitReached(id: UUID) async {
        guard requestID == id, !ending else { return }
        reachedLimit = true
        do { try await finish(requestID: id) }
        catch { failed(.recognitionFailed, id: id) }
    }
    private func observe(_ capture: AVCaptureSession, device: AVCaptureDevice, id: UUID) {
        for name in [AVCaptureSession.runtimeErrorNotification, AVCaptureSession.wasInterruptedNotification] {
            observations.append(NotificationCenter.default.addObserver(forName: name, object: capture, queue: nil) { [weak self] _ in
                Task { await self?.failed(.interrupted, id: id) }
            })
        }
        observations.append(NotificationCenter.default.addObserver(forName: AVCaptureDevice.wasDisconnectedNotification, object: device, queue: nil) { [weak self] _ in
            Task { await self?.failed(.interrupted, id: id) }
        })
    }
}

extension NativeDictationService: DictationCapturing, DictationLanguageProviding {}
