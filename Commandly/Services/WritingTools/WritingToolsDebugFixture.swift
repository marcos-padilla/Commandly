#if DEBUG
import Foundation
import Infrastructure

/// Explicit generated UI data. Only the documented sentence is recognized; this is not a spell checker.
@MainActor
enum WritingToolsDebugFixture {
    static let sampleInput = "🙂 This are teh sample sentence."
    static let sampleOutput = "🙂 This is the sample sentence."
    static var services: WritingToolsApplicationServices {
        .init(checker: GeneratedWritingChecker(), pasteboard: InMemoryPasteboard())
    }
}

@MainActor
private final class GeneratedWritingChecker: WritingChecking {
    let availableLanguages = ["en_US"]

    func check(text: String, language: String?,
               completion: @escaping @MainActor @Sendable (Result<WritingCheckReport, WritingCheckError>) -> Void
    ) -> any WritingCheckCancelling {
        let request = GeneratedWritingRequest()
        guard text == WritingToolsDebugFixture.sampleInput else {
            completion(.failure(.malformedResult)); return request
        }
        guard language == nil || language == "en_US" else {
            completion(.failure(.unsupportedLanguage)); return request
        }
        let source = text as NSString
        let grammar = source.range(of: "are")
        let spelling = source.range(of: "teh")
        let issues: [WritingIssue] = [
            .init(id: UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1)),
                kind: .grammar, range: .init(location: grammar.location, length: grammar.length),
                explanation: "Generated fixture: singular subject agreement.", suggestions: ["is"], automaticReplacement: "is"),
            .init(id: UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2)),
                kind: .correction, range: .init(location: spelling.location, length: spelling.length),
                explanation: "Generated fixture: spelling replacement.", suggestions: ["the"], automaticReplacement: "the")
        ]
        guard issues.allSatisfy({ $0.range.isValid(in: text) }) else {
            completion(.failure(.malformedResult)); return request
        }
        completion(.success(.init(source: text, issues: issues, language: "en_US")))
        return request
    }
}

@MainActor
private final class GeneratedWritingRequest: WritingCheckCancelling { func cancel() {} }
#endif
