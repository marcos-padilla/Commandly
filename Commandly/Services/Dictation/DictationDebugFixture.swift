#if DEBUG
import Foundation
import Infrastructure

/// Generated interaction data only. This never opens a microphone or executes speech recognition.
@MainActor
enum DictationDebugFixture {
    static func services(pasteboard: any PasteboardAccessing, quickAI: any QuickAIServicing) -> DictationApplicationServices {
        let capture = GeneratedDictationCapture()
        return .init(microphonePermission: GeneratedDictationPermission(), languages: capture, capture: capture,
                     history: GeneratedDictationHistory(), rewriter: ProviderDictationStyleRewriter(service: quickAI),
                     pasteboard: pasteboard, fixtureLabel: "Generated UI Fixture — no microphone or speech recognition")
    }
}
private actor GeneratedDictationCapture {
    private let english = DictationLanguage(id: "en-US", name: "English (Generated Fixture)", engine: .speechTranscriber)
    private let spanish = DictationLanguage(id: "es-ES", name: "Spanish (Generated Fixture)", engine: .dictationTranscriber)
    private let microphone = DictationMicrophone(id: "generated", name: "Generated Fixture Input", isDefault: true)
    private var current: DictationCaptureRequest?
    private var events: AsyncStream<DictationCaptureEvent>.Continuation?
    func languages() -> [DictationLanguage] { [english, spanish] }
    func preferredLanguageID() -> String? { english.id }
    func availability(for language: DictationLanguage) -> DictationModelAvailability { .installed }
    func download(language: DictationLanguage) {}
    func microphones() -> [DictationMicrophone] { [microphone] }
    func start(_ request: DictationCaptureRequest) throws -> DictationCaptureSession {
        guard current == nil else { throw DictationError.busy }
        let pair = AsyncStream<DictationCaptureEvent>.makeStream(bufferingPolicy: .bufferingNewest(1))
        current = request; events = pair.continuation
        pair.continuation.yield(.transcript(try DictationTranscript(text: "Generated preview. Choose Stop & Review to finish this example.", containsProvisionalText: true)))
        return .init(id: request.id, microphone: microphone, events: pair.stream)
    }
    func finish(requestID: UUID) throws {
        guard let current, current.id == requestID else { return }
        let text = current.language.id == spanish.id
            ? "Este es un ejemplo generado. Revisa el texto y cópialo cuando esté listo."
            : "This is a generated example. Review the text and copy it when it is ready."
        events?.yield(.finished(try DictationTranscript(text: text, containsProvisionalText: false), reachedDurationLimit: false))
        events?.finish(); events = nil; self.current = nil
    }
    func cancel(requestID: UUID) {
        guard current?.id == requestID else { return }
        events?.yield(.cancelled); events?.finish(); events = nil; current = nil
    }
}
extension GeneratedDictationCapture: DictationCapturing, DictationLanguageProviding {}
private struct GeneratedDictationPermission: DictationMicrophoneAuthorizing {
    func authorization() async -> DictationMicrophoneAuthorization { .authorized }
    func requestAuthorization() async -> DictationMicrophoneAuthorization { .authorized }
    func openSettings() async {}
}
private actor GeneratedDictationHistory {
    private var entries: [DictationHistoryEntry] = []
    func load() -> [DictationHistoryEntry] { entries }
    func save(_ entry: DictationHistoryEntry) throws -> [DictationHistoryEntry] {
        guard entry.isValid else { throw DictationError.historyUnavailable }
        guard entries.count < 50 || entries.contains(where: { $0.id == entry.id }) else { throw DictationError.historyFull }
        entries.removeAll { $0.id == entry.id }; entries.insert(entry, at: 0); return entries
    }
    func delete(id: UUID) -> [DictationHistoryEntry] { entries.removeAll { $0.id == id }; return entries }
    func clear() { entries = [] }
}
extension GeneratedDictationHistory: DictationHistoryStoring {}
#endif
