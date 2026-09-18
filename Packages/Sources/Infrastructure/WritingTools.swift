import Foundation

/// UTF-16 offsets match native text-checking results without converting character counts to bytes.
public struct WritingTextRange: Equatable, Hashable, Sendable {
    public let location: Int
    public let length: Int
    public init(location: Int, length: Int) { self.location = location; self.length = length }
    public var nsRange: NSRange { NSRange(location: location, length: length) }
    public func isValid(in text: String) -> Bool {
        let units = Array(text.utf16)
        guard location >= 0, length >= 0, location <= units.count,
              length <= units.count - location else { return false }
        func isScalarBoundary(_ offset: Int) -> Bool {
            guard offset > 0, offset < units.count else { return true }
            return (0xD800...0xDBFF).contains(units[offset - 1]) == false
                || (0xDC00...0xDFFF).contains(units[offset]) == false
        }
        guard isScalarBoundary(location), isScalarBoundary(location + length) else { return false }
        return Range(nsRange, in: text) != nil
    }
}

/// A native issue may have an explanation without an automatic replacement.
public struct WritingIssue: Equatable, Identifiable, Sendable {
    public enum Kind: String, Sendable { case spelling, grammar, correction }
    public let id: UUID
    public let kind: Kind
    public let range: WritingTextRange
    public let explanation: String
    public let suggestions: [String]
    public let automaticReplacement: String?
    public init(id: UUID = UUID(), kind: Kind, range: WritingTextRange, explanation: String,
                suggestions: [String], automaticReplacement: String? = nil) {
        self.id = id; self.kind = kind; self.range = range; self.explanation = explanation
        self.suggestions = suggestions; self.automaticReplacement = automaticReplacement
    }
}

/// A memory-only report bound to the exact input checked by the native engine.
public struct WritingCheckReport: Equatable, Sendable {
    public let source: String
    public let issues: [WritingIssue]
    public let language: String?
    public let isTruncated: Bool
    public init(source: String, issues: [WritingIssue], language: String? = nil, isTruncated: Bool = false) {
        self.source = source; self.issues = issues; self.language = language; self.isTruncated = isTruncated
    }
}

/// Fixed errors never include the user's text or an underlying spelling-service error description.
public enum WritingCheckError: Error, Equatable, Sendable {
    case emptyInput, inputTooLarge, unsupportedLanguage, malformedResult, cancelled, timedOut, unavailable
}

/// One native request; cancellation must make every later callback inert.
@MainActor public protocol WritingCheckCancelling: AnyObject { func cancel() }

/// Callback API also works inside the synchronous macOS Services modal event loop.
@MainActor public protocol WritingChecking: AnyObject {
    var availableLanguages: [String] { get }
    @discardableResult func check(
        text: String, language: String?,
        completion: @escaping @MainActor @Sendable (Result<WritingCheckReport, WritingCheckError>) -> Void
    ) -> any WritingCheckCancelling
}

/// Bounded correction application preserves all unselected input and rejects conflicting ranges.
public enum WritingCorrectionPolicy {
    public static let maximumInputBytes = 16 * 1_024
    public static let maximumOutputBytes = 64 * 1_024
    public static let maximumIssues = 128

    public static func validateInput(_ text: String) throws {
        guard text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else { throw WritingCheckError.emptyInput }
        guard text.utf8.count <= maximumInputBytes else { throw WritingCheckError.inputTooLarge }
    }

    /// Applies only explicit native autocorrections or single-choice grammar replacements.
    /// Ambiguous, overlapping, or truncated results require the review workflow instead.
    public static func automaticResult(_ report: WritingCheckReport) throws -> String {
        guard report.isTruncated == false, report.issues.count <= maximumIssues,
              Set(report.issues.map(\.id)).count == report.issues.count else { throw WritingCheckError.malformedResult }
        let changes = Dictionary(uniqueKeysWithValues: report.issues.compactMap { issue in
            issue.automaticReplacement.map { (issue.id, $0) }
        })
        return try applying(changes, to: report)
    }

    /// The caller chooses only options supplied for that exact report; free editing is a separate UI action.
    public static func applying(_ choices: [UUID: String], to report: WritingCheckReport) throws -> String {
        try validateInput(report.source)
        guard report.issues.count <= maximumIssues, Set(report.issues.map(\.id)).count == report.issues.count else {
            throw WritingCheckError.malformedResult
        }
        var replacements: [(WritingTextRange, String)] = []
        for (id, replacement) in choices {
            guard let issue = report.issues.first(where: { $0.id == id }), issue.range.isValid(in: report.source),
                  issue.range.length > 0,
                  issue.suggestions.contains(replacement) || issue.automaticReplacement == replacement,
                  replacement.utf8.count <= maximumOutputBytes else { throw WritingCheckError.malformedResult }
            replacements.append((issue.range, replacement))
        }
        replacements.sort { $0.0.location < $1.0.location }
        var previousEnd = 0
        for (range, _) in replacements {
            guard range.location >= previousEnd else { throw WritingCheckError.malformedResult }
            previousEnd = range.location + range.length
        }
        let result = NSMutableString(string: report.source)
        for (range, replacement) in replacements.reversed() { result.replaceCharacters(in: range.nsRange, with: replacement) }
        let output = result as String
        guard output.utf8.count <= maximumOutputBytes else { throw WritingCheckError.inputTooLarge }
        return output
    }
}
