import CoreMedia
import Foundation
import Infrastructure
import Speech

/// Both modules process audio on-device. No SFSpeechRecognizer/server fallback is constructed.
nonisolated enum NativeDictationModule: Sendable {
    case speech(SpeechTranscriber)
    case dictation(DictationTranscriber)
    var module: any SpeechModule { switch self { case .speech(let value): value; case .dictation(let value): value } }
    var locale: Locale { moduleLocale }
    private var moduleLocale: Locale {
        switch self {
        case .speech(let value): value.selectedLocales.first ?? Locale(identifier: "und")
        case .dictation(let value): value.selectedLocales.first ?? Locale(identifier: "und")
        }
    }
    static func make(_ language: DictationLanguage) async throws -> Self {
        switch language.engine {
        case .speechTranscriber:
            guard SpeechTranscriber.isAvailable,
                  let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: language.id)) else { throw DictationError.languageUnsupported }
            return .speech(SpeechTranscriber(locale: locale, transcriptionOptions: [], reportingOptions: [.volatileResults], attributeOptions: [.audioTimeRange]))
        case .dictationTranscriber:
            guard let locale = await DictationTranscriber.supportedLocale(equivalentTo: Locale(identifier: language.id)) else { throw DictationError.languageUnsupported }
            return .dictation(DictationTranscriber(locale: locale, contentHints: [], transcriptionOptions: [.punctuation], reportingOptions: [.volatileResults], attributeOptions: [.audioTimeRange]))
        }
    }
    func collect(_ receive: @escaping @Sendable (DictationTranscript) async -> Void) async throws {
        var buffer = NativeDictationTranscriptBuffer()
        switch self {
        case .speech(let transcriber):
            for try await result in transcriber.results {
                try Task.checkCancellation()
                let value = try buffer.apply(result.text, range: result.range, finalizationTime: result.resultsFinalizationTime)
                await receive(value)
            }
        case .dictation(let transcriber):
            for try await result in transcriber.results {
                try Task.checkCancellation()
                let value = try buffer.apply(result.text, range: result.range, finalizationTime: result.resultsFinalizationTime)
                await receive(value)
            }
        }
    }
}

/// Uses the native word-time attributes to replace partial text without duplicating finalized words.
nonisolated struct NativeDictationTranscriptBuffer {
    private var transcript = AttributedString()
    private var provisionalRanges: [CMTimeRange] = []
    mutating func apply(_ text: AttributedString, range: CMTimeRange, finalizationTime: CMTime) throws -> DictationTranscript {
        guard range.isValid, range.start.isNumeric, range.duration.isNumeric,
              CMTimeCompare(range.duration, .zero) >= 0,
              String(text.characters).utf8.count <= 64 * 1_024 else { throw DictationError.transcriptLimit }
        var replacement = transcript
        if let target = replacement.rangeOfAudioTimeRangeAttributes(intersecting: range) { replacement.replaceSubrange(target, with: text) }
        else { replacement.append(text) }
        let string = String(replacement.characters)
        guard string.utf8.count <= 64 * 1_024 else { throw DictationError.transcriptLimit }
        provisionalRanges.removeAll { old in
            CMTimeCompare(old.end, finalizationTime) <= 0
                || (CMTimeCompare(old.start, range.end) < 0 && CMTimeCompare(range.start, old.end) < 0)
        }
        if CMTimeCompare(range.end, finalizationTime) > 0 { provisionalRanges.append(range) }
        transcript = replacement
        return try DictationTranscript(text: string, containsProvisionalText: !provisionalRanges.isEmpty)
    }
}
