import Foundation
import Infrastructure

@MainActor
struct DictationApplicationServices {
    let microphonePermission: any DictationMicrophoneAuthorizing
    let languages: any DictationLanguageProviding
    let capture: any DictationCapturing
    let history: any DictationHistoryStoring
    let rewriter: any DictationStyleRewriting
    let pasteboard: any PasteboardAccessing
    let now: @MainActor () -> Date
    let fixtureLabel: String?
    init(microphonePermission: any DictationMicrophoneAuthorizing, languages: any DictationLanguageProviding,
         capture: any DictationCapturing, history: any DictationHistoryStoring, rewriter: any DictationStyleRewriting,
         pasteboard: any PasteboardAccessing, now: @escaping @MainActor () -> Date = Date.init, fixtureLabel: String? = nil) {
        self.microphonePermission = microphonePermission; self.languages = languages; self.capture = capture
        self.history = history; self.rewriter = rewriter; self.pasteboard = pasteboard; self.now = now; self.fixtureLabel = fixtureLabel
    }
    static func live(pasteboard: any PasteboardAccessing, quickAI: any QuickAIServicing) -> Self {
        // Sharing one native actor prevents overlapping capture/download reservations across launcher sessions.
        let native = NativeDictationService()
        return Self(microphonePermission: NativeDictationMicrophonePermission(), languages: native, capture: native,
                    history: JSONDictationHistoryStore(), rewriter: ProviderDictationStyleRewriter(service: quickAI), pasteboard: pasteboard)
    }
}
