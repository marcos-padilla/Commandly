import AIKit
import Foundation
import Infrastructure
import Observation
@testable import Commandly

@MainActor
func waitForDictationPhase(_ model: DictationViewModel, _ phase: DictationPhase) async {
    guard model.phase != phase else { return }
    await withCheckedContinuation { continuation in
        withObservationTracking { _ = model.phase } onChange: {
            Task { @MainActor in
                await waitForDictationPhase(model, phase)
                continuation.resume()
            }
        }
    }
}

actor DictationTestPermission {
    private(set) var requests = 0
    var state: DictationMicrophoneAuthorization
    let suspended: Bool
    private var answer: CheckedContinuation<DictationMicrophoneAuthorization, Never>?
    private var waiters: [CheckedContinuation<Void, Never>] = []
    init(state: DictationMicrophoneAuthorization = .authorized, suspended: Bool = false) { self.state = state; self.suspended = suspended }
    func authorization() -> DictationMicrophoneAuthorization { state }
    func requestAuthorization() async -> DictationMicrophoneAuthorization {
        requests += 1
        waiters.forEach { $0.resume() }; waiters = []
        if suspended { return await withCheckedContinuation { answer = $0 } }
        return state
    }
    func openSettings() {}
    func waitForRequest() async { if requests == 0 { await withCheckedContinuation { waiters.append($0) } } }
    func complete(_ state: DictationMicrophoneAuthorization) { self.state = state; answer?.resume(returning: state); answer = nil }
}
extension DictationTestPermission: DictationMicrophoneAuthorizing {}

actor DictationTestCapture {
    nonisolated static let english = DictationLanguage(id: "en-US", name: "English", engine: .speechTranscriber)
    nonisolated static let spanish = DictationLanguage(id: "es-ES", name: "Spanish", engine: .dictationTranscriber)
    nonisolated static let microphone = DictationMicrophone(id: "generated-input", name: "Generated Test Input", isDefault: true)
    var state: DictationModelAvailability
    private(set) var requests: [DictationCaptureRequest] = []
    private(set) var cancellations: [UUID] = []
    private(set) var finishes: [UUID] = []
    private(set) var downloads = 0
    private var streams: [UUID: AsyncStream<DictationCaptureEvent>.Continuation] = [:]
    var startFailure: DictationError?
    let suspendsStart: Bool
    private var pendingStart: CheckedContinuation<Void, Never>?
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    init(state: DictationModelAvailability = .installed, startFailure: DictationError? = nil, suspendsStart: Bool = false) { self.state = state; self.startFailure = startFailure; self.suspendsStart = suspendsStart }
    func languages() -> [DictationLanguage] { [Self.english, Self.spanish] }
    func preferredLanguageID() -> String? { Self.english.id }
    func availability(for language: DictationLanguage) -> DictationModelAvailability { state }
    func download(language: DictationLanguage) { downloads += 1; state = .installed }
    func microphones() -> [DictationMicrophone] { [Self.microphone] }
    func start(_ request: DictationCaptureRequest) async throws -> DictationCaptureSession {
        requests.append(request)
        if let startFailure { throw startFailure }
        let pair = AsyncStream<DictationCaptureEvent>.makeStream(bufferingPolicy: .bufferingNewest(1))
        streams[request.id] = pair.continuation
        startWaiters.forEach { $0.resume() }; startWaiters = []
        if suspendsStart { await withCheckedContinuation { pendingStart = $0 } }
        return DictationCaptureSession(id: request.id, microphone: Self.microphone, events: pair.stream)
    }
    func finish(requestID: UUID) { finishes.append(requestID) }
    func cancel(requestID: UUID) {
        cancellations.append(requestID)
        streams.removeValue(forKey: requestID)?.finish()
    }
    func emit(_ event: DictationCaptureEvent, id: UUID, terminal: Bool = false) {
        streams[id]?.yield(event)
        if terminal { streams.removeValue(forKey: id)?.finish() }
    }
    func disconnectWithoutTerminal(id: UUID) { streams.removeValue(forKey: id)?.finish() }
    func waitForStart() async { if requests.isEmpty { await withCheckedContinuation { startWaiters.append($0) } } }
    func completeStart() { pendingStart?.resume(); pendingStart = nil }
    func setStartFailure(_ value: DictationError?) { startFailure = value }
}
extension DictationTestCapture: DictationCapturing, DictationLanguageProviding {}

actor DictationTestHistory {
    private(set) var saves = 0
    private(set) var entries: [DictationHistoryEntry] = []
    func load() -> [DictationHistoryEntry] { entries }
    func save(_ entry: DictationHistoryEntry) -> [DictationHistoryEntry] {
        saves += 1; entries.removeAll { $0.id == entry.id }; entries.insert(entry, at: 0); return entries
    }
    func delete(id: UUID) -> [DictationHistoryEntry] { entries.removeAll { $0.id == id }; return entries }
    func clear() { entries = [] }
}
extension DictationTestHistory: DictationHistoryStoring {}

actor DictationTestPasteboard {
    private(set) var values: [String] = []
    func readString() -> String? { nil }
    func writeString(_ string: String) { values.append(string) }
    func writeFileURLs(_ urls: [URL]) {}
}
extension DictationTestPasteboard: PasteboardAccessing {}

actor DictationTestStyle {
    nonisolated static let selection = QuickAISelection(providerID: "fixture", providerName: "Generated Test Provider", modelID: "text", modelName: "Text", connectionRevision: "1", supportsStreaming: true)
    private(set) var requests: [(String, DictationWritingStyle)] = []
    private var pending: CheckedContinuation<String, Never>?
    private var waiters: [CheckedContinuation<Void, Never>] = []
    func selections() -> QuickAICatalog { .init(selections: [Self.selection], preferredID: Self.selection.id) }
    func rewrite(_ text: String, style: DictationWritingStyle, selection: QuickAISelection) async -> String {
        requests.append((text, style)); waiters.forEach { $0.resume() }; waiters = []
        return await withCheckedContinuation { pending = $0 }
    }
    func waitForRequest() async { if pending == nil { await withCheckedContinuation { waiters.append($0) } } }
    func complete(_ text: String) { pending?.resume(returning: text); pending = nil }
}
extension DictationTestStyle: DictationStyleRewriting {}

@MainActor
struct DictationTestContext {
    let permission: DictationTestPermission
    let capture: DictationTestCapture
    let history = DictationTestHistory()
    let pasteboard = DictationTestPasteboard()
    let style = DictationTestStyle()
    init(permission: DictationTestPermission = .init(), capture: DictationTestCapture = .init()) { self.permission = permission; self.capture = capture }
    var services: DictationApplicationServices {
        .init(microphonePermission: permission, languages: capture, capture: capture, history: history, rewriter: style, pasteboard: pasteboard,
              now: { Date(timeIntervalSince1970: 1_700_000_000) })
    }
    func model() -> DictationViewModel { .init(services: services, onGoBack: {}, onAISettings: {}) }
}
