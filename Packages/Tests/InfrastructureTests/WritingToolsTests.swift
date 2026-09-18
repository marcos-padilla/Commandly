import Foundation
import Testing
@testable import Infrastructure

struct WritingToolsTests {
    @Test func unicodeRangesPreserveEverythingOutsideChosenCorrection() throws {
        let source = "🙂 teh café"
        let issue = WritingIssue(kind: .correction, range: .init(location: 3, length: 3), explanation: "Spelling",
            suggestions: ["the"], automaticReplacement: "the")
        let report = WritingCheckReport(source: source, issues: [issue])
        #expect(try WritingCorrectionPolicy.automaticResult(report) == "🙂 the café")
        #expect(WritingTextRange(location: 1, length: 1).isValid(in: source) == false)
        #expect(WritingTextRange(location: 0, length: 1).isValid(in: source) == false)
        #expect(WritingTextRange(location: 0, length: 2).isValid(in: source))
    }

    @Test func ambiguousAndExplanationOnlyIssuesRemainUnchanged() throws {
        let issue = WritingIssue(kind: .grammar, range: .init(location: 0, length: 4), explanation: "Review",
            suggestions: ["They", "This"])
        #expect(try WritingCorrectionPolicy.automaticResult(.init(source: "That are fine", issues: [issue])) == "That are fine")
    }

    @Test func overlappingMalformedAndDuplicateIssuesFailWithoutPartialCorrection() {
        let first = WritingIssue(kind: .grammar, range: .init(location: 0, length: 4), explanation: "Review",
            suggestions: ["This"], automaticReplacement: "This")
        let overlap = WritingIssue(kind: .correction, range: .init(location: 2, length: 4), explanation: "Review",
            suggestions: ["other"], automaticReplacement: "other")
        #expect(throws: WritingCheckError.malformedResult) {
            try WritingCorrectionPolicy.automaticResult(.init(source: "That are", issues: [first, overlap]))
        }
        #expect(throws: WritingCheckError.malformedResult) {
            try WritingCorrectionPolicy.automaticResult(.init(source: "That are", issues: [first, first]))
        }
        #expect(throws: WritingCheckError.malformedResult) {
            try WritingCorrectionPolicy.automaticResult(.init(source: "That are", issues: [first], isTruncated: true))
        }
    }

    @Test func boundsAndUnlistedChoicesAreRejected() {
        #expect(throws: WritingCheckError.inputTooLarge) {
            try WritingCorrectionPolicy.validateInput(String(repeating: "x", count: WritingCorrectionPolicy.maximumInputBytes + 1))
        }
        let issue = WritingIssue(kind: .correction, range: .init(location: 0, length: 3), explanation: "Review", suggestions: ["the"])
        #expect(throws: WritingCheckError.malformedResult) {
            try WritingCorrectionPolicy.applying([issue.id: "unlisted"], to: .init(source: "teh", issues: [issue]))
        }
        #expect(WritingTextRange(location: Int.max, length: Int.max).isValid(in: "text") == false)
    }
}
