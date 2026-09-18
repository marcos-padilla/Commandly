import Foundation
import Infrastructure

@MainActor
struct WritingToolsApplicationServices {
    let checker: any WritingChecking
    let pasteboard: any PasteboardAccessing
    init(checker: any WritingChecking, pasteboard: any PasteboardAccessing) {
        self.checker = checker; self.pasteboard = pasteboard
    }
    static var live: Self { .init(checker: NativeWritingChecker(), pasteboard: SystemPasteboard()) }
    static var inMemory: Self { .init(checker: InMemoryWritingChecker(), pasteboard: InMemoryPasteboard()) }
}

/// Explicit inert reports for previews; no native spelling service, clipboard, or network call.
@MainActor
final class InMemoryWritingChecker: WritingChecking {
    let availableLanguages = ["en_US"]
    let issues: [WritingIssue]
    init(issues: [WritingIssue] = []) { self.issues = issues }
    func check(text: String, language: String?,
               completion: @escaping @MainActor @Sendable (Result<WritingCheckReport, WritingCheckError>) -> Void
    ) -> any WritingCheckCancelling {
        completion(.success(.init(source: text, issues: issues, language: language)))
        return InMemoryWritingRequest()
    }
}

@MainActor
private final class InMemoryWritingRequest: WritingCheckCancelling { func cancel() {} }
