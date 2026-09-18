import AppKit
import Foundation
import Infrastructure

/// Converts immutable native results off the UI actor. No native object crosses into the view model.
nonisolated enum NativeWritingResultParser {
    static func report(text: String, results: [NSTextCheckingResult], language: String?) throws -> WritingCheckReport {
        try WritingCorrectionPolicy.validateInput(text)
        var issues: [WritingIssue] = []
        var truncated = false
        for result in results.prefix(512) {
            let range = WritingTextRange(location: result.range.location, length: result.range.length)
            guard range.isValid(in: text), range.length > 0 else { throw WritingCheckError.malformedResult }
            if result.resultType == .grammar {
                let details = result.grammarDetails ?? []
                if details.count > WritingCorrectionPolicy.maximumIssues { truncated = true }
                for detail in details.prefix(WritingCorrectionPolicy.maximumIssues) {
                    let local = (detail[NSGrammarRange] as? NSValue)?.rangeValue ?? NSRange(location: 0, length: range.length)
                    guard local.location >= 0, local.length > 0, local.location <= range.length,
                          local.length <= range.length - local.location else { throw WritingCheckError.malformedResult }
                    let absolute = WritingTextRange(location: range.location + local.location, length: local.length)
                    guard absolute.isValid(in: text) else { throw WritingCheckError.malformedResult }
                    let options = normalizedSuggestions(detail[NSGrammarCorrections] as? [String] ?? [])
                    let explanation = String((detail[NSGrammarUserDescription] as? String ?? "Review this grammar suggestion.").prefix(512))
                    issues.append(.init(kind: .grammar, range: absolute, explanation: explanation,
                        suggestions: options, automaticReplacement: options.count == 1 ? options.first : nil))
                }
            } else if result.resultType == .correction {
                let options = normalizedSuggestions([result.replacementString].compactMap { $0 } + (result.alternativeStrings ?? []))
                issues.append(.init(kind: .correction, range: range, explanation: "Suggested spelling correction.",
                    suggestions: options, automaticReplacement: result.replacementString.flatMap { options.contains($0) ? $0 : nil }))
            } else if result.resultType == .spelling {
                issues.append(.init(kind: .spelling, range: range, explanation: "Check the spelling of this word.", suggestions: []))
            }
            if issues.count > WritingCorrectionPolicy.maximumIssues { truncated = true; break }
        }
        // Native spelling and autocorrection can describe the same range. Keep the useful replacement.
        let correctionRanges = Set(issues.filter { $0.kind == .correction }.map(\.range))
        issues.removeAll { $0.kind == .spelling && correctionRanges.contains($0.range) }
        var seen: Set<String> = []
        issues = issues.filter { seen.insert("\($0.kind.rawValue):\($0.range.location):\($0.range.length):\($0.automaticReplacement ?? "")").inserted }
        return WritingCheckReport(source: text, issues: Array(issues.prefix(WritingCorrectionPolicy.maximumIssues)),
            language: language, isTruncated: truncated || results.count > 512)
    }

    private static func normalizedSuggestions(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        return values.filter { $0.utf8.count <= 4_096 && seen.insert($0).inserted }.prefix(8).map { $0 }
    }
}
