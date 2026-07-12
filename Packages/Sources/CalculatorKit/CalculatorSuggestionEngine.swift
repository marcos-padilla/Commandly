import AppCore
import Foundation

/// Produces safe, recomputable autocomplete candidates for live calculator input.
struct CalculatorSuggestionEngine: Sendable {
    func suggestion(for rawInput: String) -> CalculatorSuggestion? {
        let input = rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard input.isEmpty == false else { return nil }

        if let completion = CalculatorUnitRegistry.shared.inferredConversion(for: input),
           completion.caseInsensitiveCompare(input) != .orderedSame {
            return CalculatorSuggestion(completedInput: completion, kind: .unitConversion, confidence: .high)
        }

        if let zoneSuggestion = timeZoneSuggestion(input) { return zoneSuggestion }
        if let functionSuggestion = functionSuggestion(input) { return functionSuggestion }
        if let corrected = correctedNaturalLanguage(input), corrected != input {
            return CalculatorSuggestion(completedInput: corrected, kind: .naturalLanguage, confidence: .medium)
        }

        let openCount = input.filter { $0 == "(" }.count
        let closeCount = input.filter { $0 == ")" }.count
        if openCount > closeCount {
            return CalculatorSuggestion(
                completedInput: input + String(repeating: ")", count: openCount - closeCount),
                kind: .closingDelimiter,
                confidence: .high
            )
        }

        if let last = input.last, "+-*/^".contains(last) {
            let neutral = last == "*" || last == "/" || last == "^" ? "1" : "0"
            return CalculatorSuggestion(completedInput: input + neutral, kind: .missingOperand, confidence: .low)
        }

        let lowered = input.lowercased()
        let templateMatches = CalculatorLanguageLexicon.completionTemplates.filter { $0.hasPrefix(lowered) && $0 != lowered }
        if templateMatches.count == 1, let match = templateMatches.first {
            return CalculatorSuggestion(completedInput: match, kind: .naturalLanguage, confidence: .medium)
        }
        return nil
    }

    private func functionSuggestion(_ input: String) -> CalculatorSuggestion? {
        if let groups = captures(#"^([a-z]+)\s*\((.*)$"#, input), groups.count == 2 {
            let typed = groups[0].lowercased()
            let name = functionMatch(for: typed)
            guard let name else { return nil }
            var completion = "\(name)(\(groups[1])"
            let opens = completion.filter { $0 == "(" }.count
            let closes = completion.filter { $0 == ")" }.count
            if opens > closes { completion += String(repeating: ")", count: opens - closes) }
            guard completion.caseInsensitiveCompare(input) != .orderedSame else { return nil }
            return CalculatorSuggestion(completedInput: completion, kind: .function, confidence: typed == name ? .high : .medium)
        }

        let typed = input.lowercased()
        guard typed.allSatisfy(\.isLetter), typed.count >= 2 else { return nil }
        let prefixMatches = CalculatorScientific.functionNames.filter { $0.hasPrefix(typed) }
        let name: String?
        if prefixMatches.count == 1 {
            name = prefixMatches.first
        } else {
            name = CalculatorLanguageLexicon.functionPriority.first { $0.hasPrefix(typed) }
        }
        guard let name, name != typed else { return nil }
        return CalculatorSuggestion(completedInput: "\(name)(", kind: .function, confidence: .medium)
    }

    private func functionMatch(for typed: String) -> String? {
        if CalculatorScientific.functionNames.contains(typed) { return typed }
        let candidates = Array(CalculatorScientific.functionNames)
        return StringDistance.uniqueBestMatch(for: typed, in: candidates, minimumSimilarity: 0.68)
    }

    private func correctedNaturalLanguage(_ input: String) -> String? {
        let tokens = input.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
        var corrected = tokens
        var changed = false
        for index in tokens.indices {
            let token = tokens[index].lowercased().trimmingCharacters(in: .punctuationCharacters)
            guard token.count >= 4, CalculatorLanguageLexicon.correctableWords.contains(token) == false,
                  let match = StringDistance.uniqueBestMatch(
                      for: token,
                      in: CalculatorLanguageLexicon.correctableWords,
                      minimumSimilarity: 0.74
                  ),
                  StringDistance.damerauLevenshtein(token, match, maximum: 2) <= 2 else { continue }
            corrected[index] = match
            changed = true
        }
        return changed ? corrected.joined(separator: " ") : nil
    }

    private func timeZoneSuggestion(_ input: String) -> CalculatorSuggestion? {
        guard let groups = captures(#"^(.+?\s+(?:in|to))\s+(.+)$"#, input), groups.count == 2,
              groups[0].lowercased().contains("time") || input.range(of: #"\d\s*(?:am|pm)"#, options: .regularExpression) != nil,
              let zone = CalculatorTimeZoneRegistry.shared.completion(for: groups[1]) else { return nil }
        return CalculatorSuggestion(completedInput: "\(groups[0]) \(zone)", kind: .timeZone, confidence: .medium)
    }

    private func captures(_ pattern: String, _ text: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text)) else { return nil }
        return (1..<match.numberOfRanges).compactMap { index in
            guard let range = Range(match.range(at: index), in: text) else { return nil }
            return String(text[range])
        }
    }
}
