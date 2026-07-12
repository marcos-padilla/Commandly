import Testing
@testable import AppCore

@Suite("String distance")
struct StringDistanceTests {
    @Test("Insertions, deletions, substitutions, and transpositions")
    func editOperations() {
        #expect(StringDistance.damerauLevenshtein("sqrt", "sqrt") == 0)
        #expect(StringDistance.damerauLevenshtein("sqart", "sqrt") == 1)
        #expect(StringDistance.damerauLevenshtein("sqaure", "square") == 1)
        #expect(StringDistance.damerauLevenshtein("kilomter", "kilometer") == 1)
    }

    @Test("Unique best match refuses ties and weak guesses")
    func uniqueMatch() {
        #expect(StringDistance.uniqueBestMatch(for: "sqaure", in: ["square", "cube"]) == "square")
        #expect(StringDistance.uniqueBestMatch(for: "cat", in: ["bat", "hat"]) == nil)
        #expect(StringDistance.uniqueBestMatch(for: "ordinary prose", in: ["sqrt", "sin"]) == nil)
    }
}
