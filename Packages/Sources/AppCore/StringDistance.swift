import Foundation

/// Unicode-aware string-distance utilities shared by search-like features.
public enum StringDistance {
    /// Computes an optimal-string-alignment Damerau–Levenshtein distance.
    ///
    /// Adjacent transpositions count as one edit, which matches common typing
    /// mistakes such as `sqaure` → `square`. Supplying `maximum` allows callers
    /// to abandon rows that can no longer produce an acceptable match.
    public static func damerauLevenshtein(
        _ source: String,
        _ target: String,
        maximum: Int? = nil
    ) -> Int {
        let lhs = Array(source.precomposedStringWithCanonicalMapping.lowercased())
        let rhs = Array(target.precomposedStringWithCanonicalMapping.lowercased())
        if lhs.isEmpty { return rhs.count }
        if rhs.isEmpty { return lhs.count }
        if let maximum, abs(lhs.count - rhs.count) > maximum { return maximum + 1 }

        var previousPrevious = Array(0...rhs.count)
        var previous = previousPrevious
        var current = Array(repeating: 0, count: rhs.count + 1)

        for row in 1...lhs.count {
            current[0] = row
            var rowMinimum = row
            for column in 1...rhs.count {
                let substitutionCost = lhs[row - 1] == rhs[column - 1] ? 0 : 1
                current[column] = min(
                    min(previous[column] + 1, current[column - 1] + 1),
                    previous[column - 1] + substitutionCost
                )
                if row > 1, column > 1,
                   lhs[row - 1] == rhs[column - 2],
                   lhs[row - 2] == rhs[column - 1] {
                    current[column] = min(current[column], previousPrevious[column - 2] + 1)
                }
                rowMinimum = min(rowMinimum, current[column])
            }
            if let maximum, rowMinimum > maximum { return maximum + 1 }
            previousPrevious = previous
            previous = current
        }
        return previous[rhs.count]
    }

    /// Returns similarity from `0` (unrelated) through `1` (exact match).
    public static func similarity(_ source: String, _ target: String) -> Double {
        let length = max(source.count, target.count)
        guard length > 0 else { return 1 }
        return 1 - Double(damerauLevenshtein(source, target)) / Double(length)
    }

    /// Finds the unique best candidate when it satisfies `minimumSimilarity`.
    /// A tied best score returns `nil` so callers never guess materially.
    public static func uniqueBestMatch<C: Collection>(
        for input: String,
        in candidates: C,
        minimumSimilarity: Double = 0.72
    ) -> C.Element? where C.Element == String {
        var best: (candidate: String, similarity: Double)?
        var tied = false
        for candidate in candidates {
            let score = similarity(input, candidate)
            if score > (best?.similarity ?? -1) {
                best = (candidate, score)
                tied = false
            } else if score == best?.similarity, candidate != best?.candidate {
                tied = true
            }
        }
        guard let best, best.similarity >= minimumSimilarity, tied == false else { return nil }
        return best.candidate
    }
}
