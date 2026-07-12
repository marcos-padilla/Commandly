import Foundation
import Testing
@testable import CalculatorKit

@Suite("Calculator live prediction coverage", .serialized)
struct CalculatorPredictionCoverageTests {
    private let service = CalculatorService()
    private var context: CalculatorEvaluationContext {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = .gmt
        return CalculatorEvaluationContext(
            locale: Locale(identifier: "en_US"),
            calendar: calendar,
            timeZone: .gmt,
            now: Date(timeIntervalSince1970: 1_784_116_800)
        )
    }

    @Test("Unclosed arithmetic and function calls produce live values", arguments: [
        ("sqrt(5", "sqrt(5)", sqrt(5.0)),
        ("((2 + 3)", "((2 + 3))", 5.0),
        ("abs(-12", "abs(-12)", 12.0),
        ("2 +", "2 +0", 2.0),
        ("10 *", "10 *1", 10.0),
    ] as [(String, String, Double)])
    func arithmeticPrefix(input: String, completion: String, expected: Double) async {
        let result = await success(input)
        #expect(result?.suggestion?.completedInput == completion)
        #expect(abs((result.flatMap(decimalValue) ?? .nan) - expected) < 1e-10)
    }

    @Test("Bare quantities infer conventional counterpart units", arguments: [
        ("5 mph", "5 mph in km/h", CalculatorUnitDimension.speed, 8.046_713_56),
        ("5 feet", "5 feet in m", .length, 1.524),
        ("100 celsius", "100 celsius in °F", .temperature, 212),
        ("2 kilograms", "2 kilograms in lb", .mass, 4.409_245_24),
        ("90 minutes", "90 minutes in hr", .duration, 1.5),
    ])
    func defaultConversion(input: String, completion: String, dimension: CalculatorUnitDimension, expected: Double) async {
        let registryCompletion = CalculatorUnitRegistry.shared.inferredConversion(for: input)
        #expect(registryCompletion == completion, "Registry did not infer \(input): \(String(describing: registryCompletion))")
        let suggestion = await service.suggestion(for: input, context: context)
        #expect(suggestion?.completedInput == completion, "Unexpected suggestion for \(input): \(String(describing: suggestion))")
        let result = await success(input)
        #expect(result?.suggestion?.completedInput == completion)
        guard case .measurement(let value) = result?.primaryValue else { Issue.record("Expected measurement for \(input)"); return }
        #expect(value.dimension == dimension)
        #expect(abs(value.value - expected) < 0.000_001)
    }

    @Test("Typing beyond a default conversion recomputes the target")
    func conversionTargetChanges() async {
        let metric = await service.suggestion(for: "5 mph", context: context)
        #expect(metric?.completedInput == "5 mph in km/h")
        let metersPerSecond = await service.suggestion(for: "5 mph in m", context: context)
        #expect(metersPerSecond?.completedInput == "5 mph in m/s")
        let completed = await service.suggestion(for: "5 mph in km/h", context: context)
        #expect(completed == nil)
    }

    @Test("Function and natural-language typos are corrected")
    func typoRecovery() async {
        let function = await success("sqart(25")
        #expect(function?.formattedPrimaryValue == "5")
        #expect(function?.suggestion?.completedInput == "sqrt(25)")

        let phrase = await success("sqaure root of 25")
        #expect(phrase?.formattedPrimaryValue == "5")
        #expect(phrase?.suggestion?.completedInput == "square root of 25")

        #expect(await service.suggestion(for: "sq", context: context)?.completedInput == "sqrt(")
    }

    @Test("IANA zones, derived cities, Arizona, and fuzzy zone input")
    func zoneVariables() async {
        for input in ["time in Arizona", "time in Reykjavik", "time in America/Phoenix", "time in arizna"] {
            let result = await success(input)
            guard case .timeZoneInstant = result?.primaryValue else { Issue.record("Expected time-zone result for \(input)"); continue }
        }
        #expect(await service.suggestion(for: "time in ari", context: context)?.completedInput == "time in Arizona")
    }

    @Test("Every Foundation IANA time zone is a valid variable")
    func everyIANATimeZone() async {
        for identifier in TimeZone.knownTimeZoneIdentifiers {
            let outcome = await service.evaluate("time in \(identifier)", context: context)
            guard case .success(let result) = outcome, case .timeZoneInstant(let value) = result.primaryValue else {
                Issue.record("IANA time zone was not accepted: \(identifier)")
                continue
            }
            #expect(value.timeZoneIdentifier == identifier)
        }
    }

    @Test("Every registered unit alias resolves within its declared dimension")
    func everyUnitAlias() throws {
        let registry = CalculatorUnitRegistry.shared
        for definition in registry.registeredDefinitions {
            for alias in definition.aliases {
                let resolved = try registry.resolve(alias, preferredDimension: definition.dimension)
                #expect(resolved.id == definition.id, "\(alias) resolved as \(resolved.id), expected \(definition.id)")
            }
        }
    }

    @Test("Every canonical unit executes a same-dimension conversion")
    func everyCanonicalUnit() async {
        let registry = CalculatorUnitRegistry.shared
        for definition in registry.registeredDefinitions {
            guard let source = definition.aliases.min(by: { $0.count < $1.count }) else { continue }
            let outcome = await service.evaluate("1 \(source) in \(definition.id)", context: context)
            guard case .success(let result) = outcome, case .measurement(let value) = result.primaryValue else {
                Issue.record("Canonical unit failed: \(definition.id) using \(source), got \(outcome)")
                continue
            }
            #expect(value.dimension == definition.dimension)
        }
    }

    @Test("Fuzzy matching covers common typo families", arguments: [
        ("10 plsu 5", "10 plus 5"),
        ("10 divded by 2", "10 divided by 2"),
        ("sqaure root of 25", "square root of 25"),
        ("20 percetnage of 50", "20 percentage of 50"),
        ("squrt(9", "sqrt(9)"),
        ("5 kilomters", "5 kilometers in ft"),
        ("time in arizna", "time in Arizona"),
    ])
    func typoFamilies(input: String, expected: String) async {
        let suggestion = await service.suggestion(for: input, context: context)
        #expect(suggestion?.completedInput == expected, "Unexpected correction for \(input): \(String(describing: suggestion))")
    }

    @Test("Predictions preserve material ambiguity and ignore prose")
    func safeBoundaries() async {
        for input in ["5 m", "10 oz", "1 gal", "20 C"] {
            let outcome = await service.evaluate(input, context: context)
            if case .success = outcome { Issue.record("Must not guess ambiguous input \(input)") }
        }
        #expect(await service.suggestion(for: "open quarterly report", context: context) == nil)
        #expect(await service.suggestion(for: "2 + 2", context: context) == nil)
    }

    @Test("Suggestion latency remains suitable for per-keystroke use")
    func predictionPerformance() async {
        let clock = ContinuousClock()
        let start = clock.now
        for _ in 0..<500 {
            _ = await service.suggestion(for: "time in ariz", context: context)
            _ = await service.suggestion(for: "5 mph i", context: context)
            _ = await service.suggestion(for: "sqart(25", context: context)
        }
        #expect(start.duration(to: clock.now) < .seconds(1))
    }

    private func success(_ input: String) async -> CalculatorResult? {
        let outcome = await service.evaluate(input, context: context)
        guard case .success(let result) = outcome else { Issue.record("Expected predicted success for \(input), got \(outcome)"); return nil }
        return result
    }

    private func decimalValue(_ result: CalculatorResult) -> Double? {
        guard case .decimal(let value) = result.primaryValue else { return nil }
        return NSDecimalNumber(decimal: value).doubleValue
    }
}
