import AppKit
import Foundation
import Infrastructure

/// Uses macOS spelling services without a BYOK provider, transcript, or network client.
@MainActor
final class NativeWritingChecker: WritingChecking {
    var availableLanguages: [String] { NSSpellChecker.shared.availableLanguages.sorted() }

    func check(text: String, language: String?,
               completion: @escaping @MainActor @Sendable (Result<WritingCheckReport, WritingCheckError>) -> Void
    ) -> any WritingCheckCancelling {
        let request = NativeWritingCheckRequest(completion: completion)
        do { try WritingCorrectionPolicy.validateInput(text) }
        catch let error as WritingCheckError { request.finish(.failure(error)); return request }
        catch { request.finish(.failure(.unavailable)); return request }
        if let language, availableLanguages.contains(language) == false {
            request.finish(.failure(.unsupportedLanguage)); return request
        }
        let tag = NSSpellChecker.uniqueSpellDocumentTag()
        request.documentTag = tag
        var options: [NSSpellChecker.OptionKey: Any] = [.waitForAllGrammarCheckingResultsKey: true]
        if let language { options[.orthography] = NSOrthography.defaultOrthography(forLanguage: language) }
        let types = NSTextCheckingResult.CheckingType.spelling.rawValue
            | NSTextCheckingResult.CheckingType.grammar.rawValue
            | NSTextCheckingResult.CheckingType.correction.rawValue
        NSSpellChecker.shared.requestChecking(of: text, range: NSRange(location: 0, length: text.utf16.count),
            types: types, options: options, inSpellDocumentWithTag: tag) { @Sendable _, results, orthography, _ in
                let outcome: Result<WritingCheckReport, WritingCheckError>
                do { outcome = .success(try NativeWritingResultParser.report(text: text, results: results, language: language ?? orthography.dominantLanguage)) }
                catch let error as WritingCheckError { outcome = .failure(error) }
                catch { outcome = .failure(.unavailable) }
                // Native completion can arrive on any queue. Run-loop delivery also services the
                // explicitly bounded Services modal loop; it does not wait on a Swift main task.
                RunLoop.main.perform(inModes: [.default, .modalPanel]) {
                    MainActor.assumeIsolated { request.finish(outcome) }
                }
            }
        return request
    }
}

@MainActor
private final class NativeWritingCheckRequest: WritingCheckCancelling {
    var documentTag: Int?
    private var completion: (@MainActor @Sendable (Result<WritingCheckReport, WritingCheckError>) -> Void)?
    init(completion: @escaping @MainActor @Sendable (Result<WritingCheckReport, WritingCheckError>) -> Void) {
        self.completion = completion
    }
    func finish(_ result: Result<WritingCheckReport, WritingCheckError>) {
        guard let completion else { return }
        self.completion = nil
        closeDocument()
        completion(result)
    }
    func cancel() { completion = nil; closeDocument() }
    private func closeDocument() {
        if let documentTag { NSSpellChecker.shared.closeSpellDocument(withTag: documentTag); self.documentTag = nil }
    }
}
