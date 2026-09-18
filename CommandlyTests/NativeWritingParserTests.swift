import AppKit
import Infrastructure
import Testing
@testable import Commandly

@MainActor
struct NativeWritingParserTests {
    @Test func grammarSubrangesAreRelativeToTheirSentenceAndAutocorrectionDeduplicatesSpelling() throws {
        let source = "Okay. He go now."
        let grammar = NSTextCheckingResult.grammarCheckingResult(range: NSRange(location: 6, length: 10), details: [
            [NSGrammarRange: NSValue(range: NSRange(location: 3, length: 2)),
             NSGrammarUserDescription: "Verb agreement", NSGrammarCorrections: ["goes"]]
        ])
        let report = try NativeWritingResultParser.report(text: source, results: [grammar], language: "en_US")
        #expect(report.issues.first?.range == .init(location: 9, length: 2))
        #expect(try WritingCorrectionPolicy.automaticResult(report) == "Okay. He goes now.")
        let spelling = NSTextCheckingResult.spellCheckingResult(range: NSRange(location: 0, length: 3))
        let correction = NSTextCheckingResult.correctionCheckingResult(range: NSRange(location: 0, length: 3), replacementString: "the")
        let corrected = try NativeWritingResultParser.report(text: "teh", results: [spelling, correction], language: nil)
        #expect(corrected.issues.count == 1)
        #expect(try WritingCorrectionPolicy.automaticResult(corrected) == "the")
    }

    @Test func malformedGrammarRangesAndUnicodeSplitsAreRejected() {
        let grammar = NSTextCheckingResult.grammarCheckingResult(range: NSRange(location: 0, length: 3), details: [
            [NSGrammarRange: NSValue(range: NSRange(location: 2, length: 9)), NSGrammarCorrections: ["replace"]]
        ])
        #expect(throws: WritingCheckError.malformedResult) {
            try NativeWritingResultParser.report(text: "abc", results: [grammar], language: nil)
        }
        let correction = NSTextCheckingResult.correctionCheckingResult(range: NSRange(location: 1, length: 1), replacementString: "x")
        #expect(throws: WritingCheckError.malformedResult) {
            try NativeWritingResultParser.report(text: "🙂", results: [correction], language: nil)
        }
    }

    @Test func grammarWithoutReplacementRemainsAReviewIssue() throws {
        let grammar = NSTextCheckingResult.grammarCheckingResult(range: NSRange(location: 0, length: 3), details: [
            [NSGrammarUserDescription: "Review the sentence"]
        ])
        let report = try NativeWritingResultParser.report(text: "abc", results: [grammar], language: nil)
        #expect(report.issues.count == 1)
        #expect(report.issues.first?.suggestions.isEmpty == true)
        #expect(try WritingCorrectionPolicy.automaticResult(report) == "abc")
    }
}
