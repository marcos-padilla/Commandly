extension CalculatorDocumentationArticle {
    static let financeUtilityAndSafetySections: [DocumentationSection] = [
                DocumentationSection(
                    id: "calculator-finance-pay",
                    title: "Finance, loans, savings, and pay",
                    blocks: [
                        .paragraph(
                            "calculator-finance-pay-summary",
                            "Finance evaluators use deterministic arithmetic for simple and compound interest, present and future value, annuities, fixed-rate loans, mortgage down payments, balances, savings goals, returns, profit, break-even, pay-period conversion, and overtime."
                        ),
                        .examples("calculator-finance-pay-examples", [
                            DocumentationExample(id: "calculator-finance-simple-interest", input: "simple interest on 1000 at 5% for 3 years", output: "1150"),
                            DocumentationExample(id: "calculator-finance-compound", input: "1000 at 5% compounded monthly for 10 years", output: "about 1647.01"),
                            DocumentationExample(id: "calculator-finance-future-value", input: "future value of 10000 at 6% for 5 years", output: "about 13382.26"),
                            DocumentationExample(id: "calculator-finance-present-value", input: "present value of 10000 in 5 years at 6%", output: "about 7472.58"),
                            DocumentationExample(id: "calculator-finance-loan", input: "monthly payment on 300000 at 6.5% for 30 years", output: "about 1896.20", detail: "The result notes principal, payment count, total paid, total interest, and exclusions."),
                            DocumentationExample(id: "calculator-finance-mortgage", input: "mortgage payment on 450000 with 20% down at 6.25% for 30 years", output: "about 2216.58"),
                            DocumentationExample(id: "calculator-finance-down-payment", input: "20% down on 450000", output: "90000"),
                            DocumentationExample(id: "calculator-finance-balance", input: "remaining balance after 5 years on a 300000 loan at 6% for 30 years"),
                            DocumentationExample(id: "calculator-finance-savings", input: "how much to save monthly to reach 10000 in 2 years", output: "about 416.67"),
                            DocumentationExample(id: "calculator-finance-return", input: "return from 10000 growing to 12500", output: "25%"),
                            DocumentationExample(id: "calculator-finance-annualized", input: "annualized return from 10000 to 15000 over 3 years", output: "about 14.47%"),
                            DocumentationExample(id: "calculator-finance-profit", input: "profit if revenue is 10000 and cost is 7500", output: "2500"),
                            DocumentationExample(id: "calculator-finance-break-even", input: "break even units if fixed cost is 10000, price is 50 and variable cost is 20", output: "334", detail: "Break-even units round up to a whole unit."),
                            DocumentationExample(id: "calculator-finance-hourly", input: "25 per hour yearly", output: "52000", detail: "Uses the configured paid hours per week and weeks per year."),
                            DocumentationExample(id: "calculator-finance-overtime", input: "40 hours at 25 plus 10 hours overtime", output: "1375", detail: "Uses the configured overtime multiplier; no legal rule is inferred from locale."),
                        ]),
                        .callout(
                            "calculator-finance-advice",
                            DocumentationCallout(
                                kind: .important,
                                title: "Arithmetic, not financial advice",
                                text: "Loan payments exclude taxes, insurance, HOA charges, and fees. Commandly does not fabricate market returns, tax rules, or legal overtime requirements. Verify assumptions before making a financial decision."
                            )
                        ),
                    ]
                ),
                DocumentationSection(
                    id: "calculator-geometry-health-business",
                    title: "Geometry, health arithmetic, and business metrics",
                    blocks: [
                        .examples("calculator-geometry-examples", [
                            DocumentationExample(id: "calculator-geometry-rectangle", input: "area of a rectangle 10 by 5", output: "50"),
                            DocumentationExample(id: "calculator-geometry-diagonal", input: "diagonal of a 10 by 5 rectangle", output: "about 11.18034"),
                            DocumentationExample(id: "calculator-geometry-circle", input: "area of a circle radius 5", output: "about 78.53982"),
                            DocumentationExample(id: "calculator-geometry-triangle", input: "hypotenuse with sides 3 and 4", output: "5"),
                            DocumentationExample(id: "calculator-geometry-box", input: "volume of a box 10 by 5 by 3", output: "150"),
                            DocumentationExample(id: "calculator-geometry-cylinder", input: "volume of a cylinder radius 3 height 10", output: "about 282.74334"),
                        ]),
                        .examples("calculator-health-business-examples", [
                            DocumentationExample(id: "calculator-health-bmi", input: "BMI for 68 kg and 170 cm", output: "about 23.529", detail: "Informational arithmetic only; not a diagnosis."),
                            DocumentationExample(id: "calculator-health-pace", input: "running pace for 5 km in 25 minutes", output: "5 minutes per km"),
                            DocumentationExample(id: "calculator-health-distance", input: "distance at 6 mph for 30 minutes", output: "3 miles"),
                            DocumentationExample(id: "calculator-health-calories", input: "500 calorie surplus per day for 30 days", output: "15000 calories", detail: "No weight-change guarantee is inferred."),
                            DocumentationExample(id: "calculator-business-hours", input: "hours from 8:30am to 5pm with a 30-minute lunch", output: "8 hours"),
                            DocumentationExample(id: "calculator-business-commission", input: "commission on 100000 at 3% plus 10% over 75000", output: "5500"),
                            DocumentationExample(id: "calculator-business-conversion", input: "conversion rate for 25 sales from 500 leads", output: "5%"),
                            DocumentationExample(id: "calculator-business-growth", input: "growth from 1000 to 1350", output: "35%"),
                            DocumentationExample(id: "calculator-business-cpa", input: "CPA if spend is 5000 and customers are 50", output: "100"),
                            DocumentationExample(id: "calculator-business-roas", input: "ROAS if revenue is 20000 and ad spend is 5000", output: "4"),
                            DocumentationExample(id: "calculator-business-roi", input: "ROI if investment is 10000 and profit is 2500", output: "25%"),
                        ]),
                    ]
                ),
                DocumentationSection(
                    id: "calculator-developer",
                    title: "Developer utilities",
                    blocks: [
                        .paragraph(
                            "calculator-developer-summary",
                            "Developer-shaped calculations cover number bases, contextual bitwise operators, character codes, color formats, transfer-time estimates, percent encoding, and Base64."
                        ),
                        .examples("calculator-developer-examples", [
                            DocumentationExample(id: "calculator-developer-binary", input: "255 in binary", output: "11111111"),
                            DocumentationExample(id: "calculator-developer-hex", input: "FF hex to decimal", output: "255"),
                            DocumentationExample(id: "calculator-developer-hex-add", input: "0xFF + 0x10", output: "0x10F"),
                            DocumentationExample(id: "calculator-developer-bit-and", input: "5 AND 3", output: "1"),
                            DocumentationExample(id: "calculator-developer-bit-xor", input: "5 XOR 3", output: "6"),
                            DocumentationExample(id: "calculator-developer-shift", input: "5 << 2", output: "20"),
                            DocumentationExample(id: "calculator-developer-ascii", input: "ASCII code for A", output: "65"),
                            DocumentationExample(id: "calculator-developer-unicode", input: "Unicode for €", output: "U+20AC"),
                            DocumentationExample(id: "calculator-developer-unicode-character", input: "U+1F600 as character", output: "😀"),
                            DocumentationExample(id: "calculator-developer-color-rgb", input: "#FF0000 to RGB", output: "rgb(255, 0, 0)"),
                            DocumentationExample(id: "calculator-developer-color-hex", input: "rgb(255, 0, 0) to hex", output: "#FF0000"),
                            DocumentationExample(id: "calculator-developer-transfer", input: "download time for 10 GB at 100 Mbps", output: "800 seconds", detail: "Uses an SI transfer estimate and excludes protocol overhead."),
                            DocumentationExample(id: "calculator-developer-url-encode", input: "URL encode hello world", output: "hello%20world"),
                            DocumentationExample(id: "calculator-developer-url-decode", input: "decode hello%20world", output: "hello world"),
                            DocumentationExample(id: "calculator-developer-base64-encode", input: "base64 encode hello", output: "aGVsbG8="),
                            DocumentationExample(id: "calculator-developer-base64-decode", input: "base64 decode aGVsbG8=", output: "hello"),
                        ]),
                    ]
                ),
                DocumentationSection(
                    id: "calculator-session-memory",
                    title: "Previous answers, variables, and history",
                    blocks: [
                        .paragraph(
                            "calculator-session-memory-summary",
                            "After you copy a successful answer, Commandly retains its typed value for the current process. Named assignments and the most recent copied answer can be reused in later expressions."
                        ),
                        .examples("calculator-session-memory-examples", [
                            DocumentationExample(id: "calculator-memory-ans", input: "ans * 2", detail: "Also accepts answer, previous, and last result."),
                            DocumentationExample(id: "calculator-memory-ans-percent", input: "previous + 15%"),
                            DocumentationExample(id: "calculator-memory-unit", input: "convert ans to meters", detail: "A previous measurement retains its source unit."),
                            DocumentationExample(id: "calculator-memory-variable", input: "x = 25", detail: "Then use x * 4 to get 100."),
                            DocumentationExample(id: "calculator-memory-percentage", input: "tax = 7%", detail: "Then 100 + tax evaluates to 107 because percentage semantics are retained."),
                            DocumentationExample(id: "calculator-memory-save", input: "save 84.50 as subtotal", detail: "Then subtotal + 15% tip evaluates to 97.175."),
                            DocumentationExample(id: "calculator-memory-named-phrase", input: "set hourly rate to 25", detail: "Then hourly rate * 40 evaluates to 1000."),
                        ]),
                        .callout(
                            "calculator-session-memory-lifetime",
                            DocumentationCallout(
                                kind: .privacy,
                                title: "Session scoped",
                                text: "Previous answers, variables, and Calculation History are in memory and are not persisted by CalculatorKit. They reset when Commandly’s process ends."
                            )
                        ),
                    ]
                ),
                DocumentationSection(
                    id: "calculator-live-completion",
                    title: "Live completion and corrections",
                    blocks: [
                        .paragraph(
                            "calculator-live-completion-summary",
                            "When input is incomplete but recoverable, Commandly evaluates a typed completion without changing what you entered. A ghost suffix appears when the completion only appends text; the Tab control can also accept a correction that replaces existing characters."
                        ),
                        .examples("calculator-live-completion-examples", [
                            DocumentationExample(id: "calculator-completion-parenthesis", input: "sqrt(5", output: "sqrt(5)", detail: "Balances the missing parenthesis."),
                            DocumentationExample(id: "calculator-completion-operator", input: "2 +", detail: "Adds a neutral operand for a live preview."),
                            DocumentationExample(id: "calculator-completion-function", input: "sq", output: "sqrt(", detail: "Completes a recognized function prefix."),
                            DocumentationExample(id: "calculator-completion-typo", input: "sqaure root of 25", output: "square root of 25", detail: "Offers a bounded unique correction."),
                            DocumentationExample(id: "calculator-completion-unit-default", input: "5 mph", output: "5 mph in km/h", detail: "Infers a conventional counterpart target."),
                            DocumentationExample(id: "calculator-completion-unit-retarget", input: "5 mph in m", output: "5 mph in m/s", detail: "Recomputes the target as the query changes."),
                            DocumentationExample(id: "calculator-completion-zone", input: "time in ari", output: "time in Arizona", detail: "Accepts a unique geographic correction."),
                        ]),
                        .bullets("calculator-live-completion-safety", [
                            "Suggestions are recomputed for every query and stale asynchronous work is discarded.",
                            "The completed expression is evaluated once with prediction disabled, preventing recursive suggestions.",
                            "Similarity thresholds are bounded by domain and tied matches are rejected.",
                            "Ordinary prose is not turned into a calculator result merely because it contains a number.",
                        ]),
                    ]
                ),
                DocumentationSection(
                    id: "calculator-ambiguities-limitations",
                    title: "Ambiguities and safe failures",
                    blocks: [
                        .bullets("calculator-ambiguities-list", [
                            "Bare m, oz, gal, ton, and similar aliases can represent materially different units, so Commandly asks for clarification instead of guessing.",
                            "A locale-neutral dollar sign and generic currency names such as pesos or kr are ambiguous.",
                            "CST, IST, BST, PST, EST, and similar time-zone abbreviations are not guessed.",
                            "A unit conversion across incompatible dimensions, such as meters to kilograms, fails.",
                            "Invalid dates, division by zero, invalid function domains, and unsafe factorials fail with a user-facing explanation.",
                            "Sunrise, sunset, daylight duration, and golden-hour queries are unsupported because the calculator has no location context.",
                            "Cron support covers the documented five-field forms, not every vendor-specific extension.",
                        ]),
                        .examples("calculator-safe-failure-examples", [
                            DocumentationExample(id: "calculator-failure-unit-ambiguous", input: "5 m", detail: "Specify meters, minutes, or another intended unit."),
                            DocumentationExample(id: "calculator-failure-currency-ambiguous", input: "100 pesos in USD", detail: "Specify MXN, ARS, or another ISO currency code."),
                            DocumentationExample(id: "calculator-failure-zone-ambiguous", input: "5pm CST in London", detail: "Use a city, IANA zone, or UTC offset."),
                            DocumentationExample(id: "calculator-failure-dimension", input: "5 meters in kilograms", detail: "Length and mass are incompatible dimensions."),
                            DocumentationExample(id: "calculator-failure-symbolic", input: "integrate x^2", detail: "Symbolic integration is not supported."),
                            DocumentationExample(id: "calculator-failure-astronomy", input: "sunrise today", detail: "A location-aware astronomy model is not implemented."),
                        ]),
                    ]
                ),
                DocumentationSection(
                    id: "calculator-privacy",
                    title: "Calculator privacy and reliability",
                    blocks: [
                        .bullets("calculator-privacy-list", [
                            "Calculator expressions, assignments, results, partial input, and predictions are not logged.",
                            "Clipboard writes happen only after you explicitly copy a result or choose an action that prepares clipboard text.",
                            "Opening Apple Calculator or Notes happens only after you choose the matching action.",
                            "Prediction and every non-currency evaluator work without network access.",
                            "Currency uses the public Frankfurter provider and never fabricates an unavailable rate.",
                            "Random commands run only after explicit random intent and mark their results as nondeterministic.",
                        ]),
                    ]
                ),
    ]
}

