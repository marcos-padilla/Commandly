import Foundation
import Infrastructure
import SwiftUI
// SDK 27 TranslationSession has no Sendable annotation although translate/prepare are @concurrent.
// The supported SwiftUI callback below owns one session for exactly one awaited API call. It is
// never stored, passed to another task, used concurrently, or accessed after that await. This
// narrowly scoped compatibility import bridges the SDK annotation gap without an unchecked box.
@preconcurrency import Translation

struct NativeTranslationTaskView: View {
    @Bindable var bridge: NativeTranslationBridge

    var body: some View {
        if let operation = bridge.operation {
            NativeTranslationOperationView(bridge: bridge, operation: operation)
                .id(operation.id)
        }
    }
}

/// A request owns one stable configuration even when the surrounding view is recomputed.
/// A new UUID gives SwiftUI a new child and session; an old configuration is never invalidated or reused.
private struct NativeTranslationOperationView: View {
    let bridge: NativeTranslationBridge
    let operation: NativeTranslationOperation
    @State private var configuration: TranslationSession.Configuration

    init(bridge: NativeTranslationBridge, operation: NativeTranslationOperation) {
        self.bridge = bridge; self.operation = operation
        _configuration = State(initialValue: Self.configuration(for: operation))
    }

    var body: some View {
        Color.clear.frame(width: 1, height: 1)
                .translationTask(configuration) { @MainActor session in
                    guard bridge.claim(operation.id) else { return }
                    do {
                        try Task.checkCancellation()
                        let outcome: NativeTranslationOutcome
                        switch operation.work {
                        case .translate(let request):
                            let response = try await session.translate(request.text)
                            try Task.checkCancellation()
                            outcome = .translated(try TextTranslationResult(text: response.targetText,
                                sourceLanguage: NativeTranslationLanguage.value(response.sourceLanguage),
                                targetLanguage: NativeTranslationLanguage.value(response.targetLanguage)))
                        case .prepare:
                            try await session.prepareTranslation()
                            try Task.checkCancellation()
                            outcome = .prepared
                        }
                        bridge.finish(operation.id, with: .success(outcome))
                    } catch {
                        bridge.finish(operation.id, with: .failure(NativeTranslationFailure.sanitized(error)))
                    }
                }
                .accessibilityHidden(true)
    }

    private static func configuration(for operation: NativeTranslationOperation) -> TranslationSession.Configuration {
        let source: String?
        let target: String
        switch operation.work {
        case .translate(let request): source = request.sourceLanguageID; target = request.targetLanguageID
        case .prepare(let chosenSource, let chosenTarget): source = chosenSource; target = chosenTarget
        }
        return TranslationSession.Configuration(source: source.map(Locale.Language.init(identifier:)),
            target: Locale.Language(identifier: target), preferredStrategy: .highFidelity)
    }
}

nonisolated enum NativeTranslationFailure {
    static func sanitized(_ error: Error) -> Error {
        if error is CancellationError { return CancellationError() }
        if let error = error as? TextTranslationError { return error }
        switch error {
        case TranslationError.alreadyCancelled: return CancellationError()
        case TranslationError.nothingToTranslate: return TextTranslationError.emptyInput
        case TranslationError.unsupportedSourceLanguage, TranslationError.unsupportedTargetLanguage: return TextTranslationError.unsupportedLanguage
        case TranslationError.unsupportedLanguagePairing: return TextTranslationError.unsupportedPair
        case TranslationError.unableToIdentifyLanguage: return TextTranslationError.unableToDetectSource
        case TranslationError.notInstalled: return TextTranslationError.languagesNotInstalled
        default: return TextTranslationError.translationFailed
        }
    }
}
