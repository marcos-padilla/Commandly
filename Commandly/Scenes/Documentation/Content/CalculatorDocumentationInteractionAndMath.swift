extension CalculatorDocumentationArticle {
    static let interactionAndMathSections: [DocumentationSection] = [
                DocumentationSection(
                    id: "calculator-use-result",
                    title: "Use a calculator result",
                    blocks: [
                        .steps("calculator-use-result-steps", [
                            "Open Commandly and type an expression or supported natural-language calculation.",
                            "Keep typing to refine the live result. Command and installed-app search continues underneath the Calculator card.",
                            "Press Return while the Calculator result is selected to copy its formatted answer. Commandly stays visible.",
                            "Click the question pane to restore the original input to the search field for editing.",
                            "Click the answer pane to copy the formatted answer without closing Commandly.",
                            "Open the ellipsis menu on the Calculator card for result-aware actions.",
                        ]),
                        .shortcuts("calculator-use-result-shortcuts", [
                            DocumentationShortcut(
                                id: "calculator-shortcut-copy-answer",
                                title: "Copy selected answer",
                                keys: ["↩"]
                            ),
                            DocumentationShortcut(
                                id: "calculator-shortcut-accept-completion",
                                title: "Accept offered completion",
                                keys: ["Tab"]
                            ),
                            DocumentationShortcut(
                                id: "calculator-shortcut-selection-next",
                                title: "Select next launcher result",
                                keys: ["↓"]
                            ),
                            DocumentationShortcut(
                                id: "calculator-shortcut-selection-previous",
                                title: "Select previous launcher result",
                                keys: ["↑"]
                            ),
                        ]),
                        .callout(
                            "calculator-use-result-actions-note",
                            DocumentationCallout(
                                kind: .tip,
                                title: "Calculator actions are on the card",
                                text: "Use the Calculator card’s ellipsis button for calculator-specific actions. Command–K at launcher home is reserved for actions on a selected installed application."
                            )
                        ),
                    ]
                ),
                DocumentationSection(
                    id: "calculator-result-actions",
                    title: "Calculator actions",
                    blocks: [
                        .bullets("calculator-result-actions-list", [
                            "Copy Answer copies the displayed result.",
                            "Copy Without Formatting removes grouping commas when that action is meaningful for the result.",
                            "Insert Result into Search replaces the current query with the formatted answer.",
                            "Copy Expression and Result copies a ready-to-paste “expression = result” line.",
                            "Open in Calculator first copies a compatible numeric, measurement, or currency result and then opens Apple Calculator.",
                            "Copy and Open Notes copies the expression-and-result line and opens Apple Notes. It does not create or modify a note automatically.",
                            "Actions that do not fit the result type are omitted. For example, a date or text answer does not offer Open in Calculator.",
                        ]),
                        .paragraph(
                            "calculator-history-recording",
                            "Copying a successful Calculator answer records it in the current session’s Calculation History and updates the session’s previous answer. Open Calculation History to search, copy, delete, or clear those recorded results."
                        ),
                    ]
                ),
                DocumentationSection(
                    id: "calculator-arithmetic",
                    title: "Arithmetic, written numbers, and precedence",
                    blocks: [
                        .paragraph(
                            "calculator-arithmetic-summary",
                            "Use symbols, pasted Unicode operators, or plain English. Grouping and decimal separators follow the current locale; valid three-digit grouping with spaces or apostrophes is also accepted."
                        ),
                        .examples("calculator-arithmetic-examples", [
                            DocumentationExample(id: "calculator-arithmetic-basic", input: "2 + 3 * 4", output: "14"),
                            DocumentationExample(id: "calculator-arithmetic-grouped", input: "(25 + 5) * 3", output: "90"),
                            DocumentationExample(id: "calculator-arithmetic-unicode", input: "20 ÷ 5 + 6 × 8", output: "52"),
                            DocumentationExample(id: "calculator-arithmetic-words", input: "one hundred and five times two", output: "210"),
                            DocumentationExample(id: "calculator-arithmetic-decimal-words", input: "three point five plus one point two five", output: "4.75"),
                            DocumentationExample(id: "calculator-arithmetic-mixed-fraction", input: "1 1/2 + 2 1/4", output: "3.75"),
                            DocumentationExample(id: "calculator-arithmetic-vulgar-fraction", input: "½ + ¼", output: "0.75"),
                            DocumentationExample(id: "calculator-arithmetic-factorial", input: "5!", output: "120"),
                            DocumentationExample(id: "calculator-arithmetic-modulo", input: "10 mod 3", output: "1"),
                            DocumentationExample(id: "calculator-arithmetic-absolute", input: "|-25|", output: "25"),
                            DocumentationExample(
                                id: "calculator-arithmetic-unary-power",
                                input: "-5^2",
                                output: "-25",
                                detail: "Unary minus applies outside exponentiation. Use (-5)^2 for 25."
                            ),
                            DocumentationExample(
                                id: "calculator-arithmetic-right-power",
                                input: "2^3^2",
                                output: "512",
                                detail: "Powers associate from the right: 2^(3^2)."
                            ),
                        ]),
                        .callout(
                            "calculator-arithmetic-factorial-limit",
                            DocumentationCallout(
                                kind: .limitation,
                                title: "Factorial bounds",
                                text: "Factorials accept whole numbers from 0 through 32. Negative, fractional, and larger inputs fail instead of overflowing or silently using a different function."
                            )
                        ),
                    ]
                ),
                DocumentationSection(
                    id: "calculator-scientific",
                    title: "Scientific functions, constants, and statistics",
                    blocks: [
                        .paragraph(
                            "calculator-scientific-summary",
                            "Supported functions include roots, powers, absolute value, rounding, trigonometric and hyperbolic functions, logarithms, aggregation, spread, factorial, GCD, LCM, combinations, and permutations. Angle mode defaults to radians unless the expression includes an explicit unit such as degrees."
                        ),
                        .examples("calculator-scientific-examples", [
                            DocumentationExample(id: "calculator-scientific-square-root", input: "sqrt(144)", output: "12"),
                            DocumentationExample(id: "calculator-scientific-nth-root", input: "fifth root of 32", output: "2"),
                            DocumentationExample(id: "calculator-scientific-power-words", input: "2 raised to the tenth power", output: "1024"),
                            DocumentationExample(id: "calculator-scientific-sine", input: "sin(pi / 2)", output: "1"),
                            DocumentationExample(id: "calculator-scientific-degrees", input: "tan(45 degrees)", output: "1"),
                            DocumentationExample(id: "calculator-scientific-log", input: "log base 2 of 1024", output: "10"),
                            DocumentationExample(id: "calculator-scientific-round", input: "round 10.456 to 2 decimal places", output: "10.46"),
                            DocumentationExample(id: "calculator-scientific-significant", input: "12345 to 3 sig figs", output: "12300"),
                            DocumentationExample(id: "calculator-scientific-sum", input: "sum(1, 2, 3, 4)", output: "10"),
                            DocumentationExample(id: "calculator-scientific-median", input: "median(1, 5, 9)", output: "5"),
                            DocumentationExample(id: "calculator-scientific-mode", input: "mode(1, 2, 2, 3)", output: "2"),
                            DocumentationExample(id: "calculator-scientific-stddev", input: "standard deviation of 1, 2, 3", detail: "Population standard deviation."),
                            DocumentationExample(id: "calculator-scientific-gcd", input: "greatest common divisor of 24 and 36", output: "12"),
                            DocumentationExample(id: "calculator-scientific-combination", input: "10 choose 3", output: "120"),
                            DocumentationExample(id: "calculator-scientific-permutation", input: "10 permutations of 3", output: "720"),
                            DocumentationExample(id: "calculator-scientific-constant-pi", input: "2π", detail: "Implicit multiplication by pi."),
                            DocumentationExample(id: "calculator-scientific-constant-phi", input: "golden ratio", detail: "Also accepts phi."),
                            DocumentationExample(id: "calculator-scientific-notation", input: "1.2 × 10^5", output: "120000"),
                        ]),
                        .bullets("calculator-scientific-constants", [
                            "Constants: pi or π, e, tau or τ, phi or golden ratio, sqrt2, ln2, and ln10.",
                            "Aggregation: min, max, clamp, sum, average or mean, median, mode, product, range, variance, and standard deviation.",
                            "Trigonometry: sin, cos, tan, inverse functions, atan2, and hyperbolic counterparts.",
                        ]),
                    ]
                ),
                DocumentationSection(
                    id: "calculator-percentages",
                    title: "Percentages, tax, tips, discounts, and margin",
                    blocks: [
                        .paragraph(
                            "calculator-percentages-summary",
                            "A postfix percent is a percentage value. In addition and subtraction, Commandly applies that percentage to the left-hand base. Structured phrases can also calculate reverse percentages, tax removal, split bills, markup, and gross margin."
                        ),
                        .examples("calculator-percentage-examples", [
                            DocumentationExample(id: "calculator-percent-postfix", input: "20%", output: "0.2"),
                            DocumentationExample(id: "calculator-percent-of", input: "20% of 350", output: "70"),
                            DocumentationExample(id: "calculator-percent-increase", input: "350 + 15%", output: "402.5"),
                            DocumentationExample(id: "calculator-percent-decrease", input: "reduce 350 by 15%", output: "297.5"),
                            DocumentationExample(id: "calculator-percent-change", input: "percent increase from 80 to 100", output: "25%"),
                            DocumentationExample(id: "calculator-percent-portion", input: "45 is what percentage of 60", output: "75%"),
                            DocumentationExample(id: "calculator-percent-reverse", input: "120 is 20% more than what", output: "100"),
                            DocumentationExample(id: "calculator-percent-tip", input: "84.50 plus 15% tip", output: "97.175"),
                            DocumentationExample(id: "calculator-percent-split", input: "split 84.50 plus 15% tip between 4 people", output: "24.29375"),
                            DocumentationExample(id: "calculator-percent-tax", input: "add 8.5% sales tax to 120", output: "130.2"),
                            DocumentationExample(id: "calculator-percent-remove-tax", input: "remove 7% tax from 107", output: "100"),
                            DocumentationExample(id: "calculator-percent-discount", input: "price after 15% discount on 120", output: "102"),
                            DocumentationExample(id: "calculator-percent-markup", input: "add 30% markup to 100", output: "130"),
                            DocumentationExample(id: "calculator-percent-margin", input: "price with 40% gross margin on a cost of 60", output: "100"),
                        ]),
                    ]
                ),
                DocumentationSection(
                    id: "calculator-algebra-primes",
                    title: "Ratios, elementary algebra, primes, and random values",
                    blocks: [
                        .examples("calculator-algebra-primes-examples", [
                            DocumentationExample(id: "calculator-ratio-simplify", input: "simplify 100:25", output: "4:1"),
                            DocumentationExample(id: "calculator-ratio-split", input: "split 100 in a 3:2 ratio", output: "60 and 40"),
                            DocumentationExample(id: "calculator-proportion", input: "if 3 costs 12, how much do 5 cost", output: "20"),
                            DocumentationExample(id: "calculator-linear", input: "3(x + 2) = 21", output: "5"),
                            DocumentationExample(id: "calculator-system", input: "x + y = 10, x - y = 2", output: "x = 6, y = 4"),
                            DocumentationExample(id: "calculator-quadratic", input: "x^2 - 5x + 6 = 0", output: "3, 2"),
                            DocumentationExample(id: "calculator-prime-check", input: "is 97 prime", output: "true"),
                            DocumentationExample(id: "calculator-prime-factors", input: "prime factors of 360", output: "2 × 2 × 2 × 3 × 3 × 5"),
                            DocumentationExample(id: "calculator-prime-next", input: "next prime after 100", output: "101"),
                            DocumentationExample(id: "calculator-random-range", input: "random integer between 10 and 50", detail: "The result is explicitly marked nondeterministic."),
                            DocumentationExample(id: "calculator-random-dice", input: "roll 2d6", detail: "The result is explicitly marked nondeterministic."),
                            DocumentationExample(id: "calculator-random-coin", input: "flip a coin", detail: "Returns heads or tails and is marked nondeterministic."),
                        ]),
                        .callout(
                            "calculator-algebra-limits",
                            DocumentationCallout(
                                kind: .limitation,
                                title: "Algebra scope",
                                text: "Commandly handles ratios, proportions, elementary linear equations, two-variable linear systems, and real-root quadratics. General symbolic algebra, symbolic differentiation, symbolic integration, and complex-only quadratic roots are not supported."
                            )
                        ),
                    ]
                ),
    ]
}

