import Foundation
import Infrastructure
import Observation
import Testing
@testable import Commandly

@MainActor
final class RecordingCaptureDouble: ScreenRecordingCapturing {
    private(set) var requests: [ScreenRecordingOptions] = []
    private(set) var stopCalls = 0
    private(set) var cancelCalls = 0
    var blocksCancellation = false
    var startError: ScreenRecordingError?
    private var events: AsyncStream<ScreenRecordingEvent>.Continuation?
    private var beginWaiter: CheckedContinuation<Void, Never>?
    private var stopWaiter: CheckedContinuation<Void, Never>?
    private var cancelWaiter: CheckedContinuation<Void, Never>?
    private var cancelRelease: CheckedContinuation<Void, Never>?

    func begin(options: ScreenRecordingOptions, destination: ScreenRecordingDraft,
               limits: ScreenRecordingLimits) async throws -> AsyncStream<ScreenRecordingEvent> {
        requests.append(options)
        if let startError { throw startError }
        let stream = AsyncStream<ScreenRecordingEvent>.makeStream()
        events = stream.continuation
        beginWaiter?.resume(); beginWaiter = nil
        return stream.stream
    }
    func stop() async { stopCalls += 1; stopWaiter?.resume(); stopWaiter = nil }
    func cancel() async {
        cancelCalls += 1
        cancelWaiter?.resume(); cancelWaiter = nil
        if blocksCancellation { await withCheckedContinuation { cancelRelease = $0 } }
        send(.cancelled)
    }
    func send(_ event: ScreenRecordingEvent) {
        events?.yield(event)
        switch event {
        case .finished, .failed, .cancelled: events?.finish(); events = nil
        default: break
        }
    }
    func waitForBegin() async { if requests.isEmpty { await withCheckedContinuation { beginWaiter = $0 } } }
    func waitForStop() async { if stopCalls == 0 { await withCheckedContinuation { stopWaiter = $0 } } }
    func waitForCancel() async { if cancelCalls == 0 { await withCheckedContinuation { cancelWaiter = $0 } } }
    func releaseCancellation() { blocksCancellation = false; cancelRelease?.resume(); cancelRelease = nil }
}

actor RecordingStoreDouble: ScreenRecordingStoring {
    private(set) var prepares = 0
    private(set) var discards: [ScreenRecordingDraft] = []
    private(set) var exports: [ScreenRecordingArtifact] = []
    private(set) var finalizations = 0
    private var blocksPrepare: Bool
    private var prepareRelease: CheckedContinuation<Void, Never>?
    private var prepareWaiter: CheckedContinuation<Void, Never>?
    var failsExport = false
    var failsDiscard = false
    private var blocksDiscard = false
    private var discardWaiter: CheckedContinuation<Void, Never>?
    private var discardRelease: CheckedContinuation<Void, Never>?
    private var discardStarted = false
    init(blocksPrepare: Bool = false) { self.blocksPrepare = blocksPrepare }
    func prepare(container: ScreenRecordingContainer, limits: ScreenRecordingLimits) async throws -> ScreenRecordingDraft {
        prepares += 1
        prepareWaiter?.resume(); prepareWaiter = nil
        if blocksPrepare { await withCheckedContinuation { prepareRelease = $0 } }
        let id = UUID()
        return ScreenRecordingDraft(id: id, url: URL(fileURLWithPath: "/generated-test-\(id.uuidString).\(container.rawValue)"), container: container)
    }
    func finalize(_ draft: ScreenRecordingDraft, summary: ScreenRecordingSummary,
                  limits: ScreenRecordingLimits) async throws -> ScreenRecordingArtifact {
        finalizations += 1
        return ScreenRecordingArtifact(draft: draft, summary: summary)
    }
    func export(_ artifact: ScreenRecordingArtifact, to destination: URL) throws {
        if failsExport { throw ScreenRecordingError.exportFailed }
        exports.append(artifact)
    }
    func discard(_ draft: ScreenRecordingDraft) async throws {
        discardStarted = true
        discardWaiter?.resume(); discardWaiter = nil
        if blocksDiscard { await withCheckedContinuation { discardRelease = $0 } }
        if failsDiscard { throw ScreenRecordingError.storageUnavailable }
        discards.append(draft)
    }
    func setBlocksDiscard(_ value: Bool) { blocksDiscard = value; discardStarted = false }
    func waitForDiscard() async { if !discardStarted { await withCheckedContinuation { discardWaiter = $0 } } }
    func releaseDiscard() { blocksDiscard = false; discardRelease?.resume(); discardRelease = nil }
    func setExportFailure(_ value: Bool) { failsExport = value }
    func setDiscardFailure(_ value: Bool) { failsDiscard = value }
    func waitForPrepare() async { if prepares == 0 { await withCheckedContinuation { prepareWaiter = $0 } } }
    func releasePrepare() { blocksPrepare = false; prepareRelease?.resume(); prepareRelease = nil }
}

@MainActor
func waitForRecordingPhase(_ phase: ScreenRecordingModel.Phase, in model: ScreenRecordingModel) async {
    while model.phase != phase {
        await withCheckedContinuation { continuation in
            withObservationTracking { _ = model.phase } onChange: { continuation.resume() }
        }
    }
}

nonisolated enum RecordingTestFixture {
    static var summary: ScreenRecordingSummary {
        ScreenRecordingSummary(duration: 3, fileBytes: 2_048, pixelWidth: 640, pixelHeight: 360)
    }
}

@MainActor
final class RecordingWindowDouble: ScreenRecordingWindowPresenting {
    var focusCalls = 0
    var closeCalls = 0
    var model: ScreenRecordingModel?
    var onClosed: (() -> Void)?
    func present(model: ScreenRecordingModel, onClosed: @escaping () -> Void) { self.model = model; self.onClosed = onClosed }
    func focus() { focusCalls += 1 }
    func close() { closeCalls += 1; onClosed?() }
}

@MainActor
final class RecordingCallbackDouble {
    var closes = 0
    var results: [Bool] = []
}
