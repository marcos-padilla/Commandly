enum CalculatorDocumentationArticle {
    static let article = CoreDocumentationArticle(
        id: "core.calculator",
        title: "Calculator",
        subtitle: "Arithmetic, science, units, currency, dates, finance, geometry, and developer utilities.",
        systemImage: "function",
        category: .coreFeatures,
        order: 110,
        documentation: LauncherApplicationDocumentation(
            category: .coreFeatures,
            overview: "Type a calculator-shaped query directly into the launcher. Commandly evaluates it alongside normal search, pins a two-pane Calculator card above other results, and keeps the original expression available for editing. The engine uses deterministic parsers and focused evaluators rather than dynamic code execution.",
            sections: interactionAndMathSections
                + conversionAndTimeSections
                + financeUtilityAndSafetySections,
            keywords: [
                "calculator", "math", "arithmetic", "scientific", "statistics", "percent", "tax",
                "tip", "discount", "markup", "margin", "ratio", "algebra", "prime", "random",
                "units", "conversion", "currency", "exchange rate", "dates", "calendar", "time zone",
                "clock", "cron", "finance", "loan", "mortgage", "interest", "geometry", "BMI",
                "business metrics", "binary", "hex", "bitwise", "ASCII", "Unicode", "Base64",
                "URL encode", "ans", "variables", "history", "autocomplete", "Tab",
            ]
        )
    )
}

