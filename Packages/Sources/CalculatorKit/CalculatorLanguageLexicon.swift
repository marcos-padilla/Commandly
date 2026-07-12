import Foundation

/// Shared language data for normalization and live completion.
///
/// Keeping these rules together prevents the normalizer and suggestion engine
/// from developing separate, exact-string vocabularies as expression coverage
/// grows. Evaluators still own the grammar and calculations themselves.
enum CalculatorLanguageLexicon {
    static let normalizationRules: [(phrase: String, replacement: String)] = [
        ("open parenthesis", "("),
        ("close parenthesis", ")"),
        ("to the power of", "^"),
        ("raised to the", "^"),
        ("raised to", "^"),
        ("multiplied by", "*"),
        ("divided by", "/"),
        ("cube root of", "cbrt "),
        ("square root of", "sqrt"),
        ("absolute value of", "abs "),
        ("factorial of", "factorial "),
        ("natural log of", "ln "),
        ("arcsine", "asin"),
        ("arccosine", "acos"),
        ("arctangent", "atan"),
        ("arcsin", "asin"),
        ("arccos", "acos"),
        ("arctan", "atan"),
        ("sine", "sin"),
        ("cosine", "cos"),
        ("tangent", "tan"),
        ("modulo", "mod"),
        ("golden ratio", "phi"),
        ("percent of", "% of"),
        ("percentage of", "% of"),
        ("plus", "+"),
        ("minus", "-"),
        ("times", "*"),
        ("over", "/"),
        ("squared", "^2"),
        ("cubed", "^3"),
        ("percent", "%"),
        ("percentage", "%"),
    ]

    static let commandPrefixPattern =
        #"^(?:what\s+is\s+the|find\s+the|what\s+is|how\s+much\s+is|calculate|calc|convert|find|show)\s+"#

    static let functionPriority = [
        "sqrt", "cbrt", "sin", "cos", "tan", "abs", "round", "log", "ln",
        "min", "max", "sum", "mean", "median", "pow", "hypot", "factorial",
    ]

    static let completionTemplates = [
        "square root of ", "cube root of ", "absolute value of ",
        "percentage change from ", "percent increase from ", "percent decrease from ",
        "days until ", "days since ", "time in ", "current time in ",
        "convert ", "calculate ", "round ", "simple interest on ",
        "monthly payment on ", "area of a circle radius ", "area of a rectangle ",
    ]

    /// Words used for bounded fuzzy correction. Most operator/function words
    /// are derived from normalization rules so normalization and correction do
    /// not drift apart; domain grammar adds the remaining variable words.
    static let correctableWords: [String] = {
        let ruleWords = normalizationRules.flatMap { rule in
            rule.phrase.split(separator: " ").map(String.init)
        }
        let grammarWords = [
            "remainder", "square", "cube", "root", "absolute", "increase",
            "decrease", "discount", "markup", "margin", "convert", "calculate", "round",
            "degrees", "radians", "hours", "minutes", "seconds", "days", "weeks",
            "months", "years", "today", "tomorrow", "between", "after", "before",
        ]
        return Array(Set(ruleWords + grammarWords)).sorted()
    }()
}
