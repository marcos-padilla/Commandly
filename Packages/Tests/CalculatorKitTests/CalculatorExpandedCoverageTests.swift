import Foundation
import Testing
@testable import CalculatorKit

@Suite("Expanded calculation catalog", .serialized)
struct CalculatorExpandedCoverageTests {
    private let service = CalculatorService()
    private let context = CalculatorEvaluationContext(locale: Locale(identifier: "en_US"))

    @Test("Natural arithmetic transformations compose with expressions", arguments: [
        ("double (14 plus 5)", 38.0),
        ("twice 12.5", 25.0),
        ("triple (8 minus 3)", 15.0),
        ("quadruple (2 plus 4)", 24.0),
        ("half of (50 minus 5)", 22.5),
        ("one third of (60 plus 21)", 27.0),
        ("two thirds of (45 plus 45)", 60.0),
        ("reciprocal of 8", 0.125),
        ("reciprocal of (3 plus 5)", 0.125),
        ("additive inverse of -14", 14.0),
        ("square of (3 plus 4)", 49.0),
        ("cube of (2 plus 1)", 27.0),
    ] as [(String, Double)])
    func naturalTransformations(expression: String, expected: Double) async throws {
        try await expectNumeric(expression, expected)
    }

    @Test("Descriptive statistics and interpolation", arguments: [
        ("weighted average of 80 weight 2, 90 weight 3", 86.0),
        ("weighted sum of 10 weight 0.2, 20 weight 0.8", 18.0),
        ("geometric mean of 4, 16", 8.0),
        ("geometric mean of 1, 4, 16", 4.0),
        ("harmonic mean of 4, 12", 6.0),
        ("root mean square of 3, 4", sqrt(12.5)),
        ("sample variance of 1, 2, 3", 1.0),
        ("sample standard deviation of 1, 2, 3", 1.0),
        ("z score of 85 with mean 70 and standard deviation 10", 1.5),
        ("coefficient of variation for mean 50 and standard deviation 5", 10.0),
        ("standard error for standard deviation 12 and sample size 36", 2.0),
        ("margin of error for standard deviation 10 sample size 100 at 95%", 1.96),
        ("linear interpolation from 10 to 20 at 25%", 12.5),
        ("normalize 75 from range 50 to 100", 0.5),
        ("map 5 from range 0 to 10 into 0 to 100", 50.0),
    ] as [(String, Double)])
    func statistics(expression: String, expected: Double) async throws {
        try await expectNumeric(expression, expected)
    }

    @Test("Sequences, series, and digit properties", arguments: [
        ("fibonacci number 10", 55.0),
        ("12th fibonacci number", 144.0),
        ("sum of first 100 integers", 5_050.0),
        ("sum integers from 20 to 40", 630.0),
        ("arithmetic sequence term 10 first 3 difference 5", 48.0),
        ("arithmetic series sum 10 terms first 3 difference 5", 255.0),
        ("geometric sequence term 8 first 2 ratio 3", 4_374.0),
        ("geometric series sum 6 terms first 2 ratio 3", 728.0),
        ("triangular number 20", 210.0),
        ("pentagonal number 10", 145.0),
        ("hexagonal number 10", 190.0),
        ("sum of squares from 1 to 10", 385.0),
        ("sum of cubes from 1 to 10", 3_025.0),
        ("greatest power of 2 not exceeding 1000", 512.0),
        ("digital root of 987654", 3.0),
        ("digit sum of 123456", 21.0),
        ("number of digits in 1000000", 7.0),
    ] as [(String, Double)])
    func sequences(expression: String, expected: Double) async throws {
        try await expectNumeric(expression, expected)
    }

    @Test("Sequence predicates", arguments: [
        ("is 1024 a power of 2", "true"),
        ("is 1023 a power of 2", "false"),
    ])
    func sequencePredicates(expression: String, expected: String) async throws {
        #expect(try await textValue(expression) == expected)
    }

    @Test("Extended plane and solid geometry", arguments: [
        ("area of a trapezoid bases 8 and 12 height 5", 50.0),
        ("area of a parallelogram base 9 height 4", 36.0),
        ("area of a rhombus diagonals 10 and 6", 30.0),
        ("area of an ellipse radii 5 and 3", 15 * Double.pi),
        ("circumference of an ellipse radii 5 and 3", Double.pi * (24 - sqrt(252))),
        ("interior angle of a regular hexagon", 120.0),
        ("sum interior angles of a 9-gon", 1_260.0),
        ("exterior angle of a regular 12-gon", 30.0),
        ("area of a regular hexagon side 4", 24 * sqrt(3)),
        ("area of a regular polygon 8 sides side 3", 8 * 9 / (4 * tan(Double.pi / 8))),
        ("volume of a sphere radius 3", 36 * Double.pi),
        ("surface area of a cylinder radius 2 height 5", 28 * Double.pi),
        ("surface area of a cone radius 3 slant height 5", 24 * Double.pi),
        ("volume of a pyramid base area 30 height 6", 60.0),
        ("volume of a triangular prism triangle base 4 height 3 length 10", 60.0),
        ("volume of a torus major radius 5 minor radius 2", 40 * Double.pi * Double.pi),
        ("distance between points (1, 2) and (4, 6)", 5.0),
        ("slope between points (1, 2) and (5, 10)", 2.0),
        ("missing angle of triangle 50 and 60 degrees", 70.0),
        ("area of triangle sides 3, 4, 5", 6.0),
        ("arc length radius 10 angle 90 degrees", 5 * Double.pi),
        ("sector area radius 10 angle 90 degrees", 25 * Double.pi),
        ("45 degrees as slope percent", 100.0),
        ("100 slope percent as degrees", 45.0),
    ] as [(String, Double)])
    func geometry(expression: String, expected: Double) async throws {
        try await expectNumeric(expression, expected)
    }

    @Test("Coordinate transformations")
    func coordinateTransformations() async throws {
        #expect(try await textValue("midpoint between (2, 4) and (8, 10)") == "(5, 7)")
    }

    @Test("Mechanics, waves, electricity, and thermodynamics", arguments: [
        ("speed for distance 150 m time 12 s", 12.5),
        ("distance at speed 20 m/s for 15 s", 300.0),
        ("acceleration from 5 m/s to 25 m/s in 4 s", 5.0),
        ("force for mass 10 kg acceleration 3 m/s2", 30.0),
        ("momentum for mass 12 kg velocity 5 m/s", 60.0),
        ("kinetic energy for mass 10 kg velocity 4 m/s", 80.0),
        ("potential energy for mass 10 kg height 5 m", 490.3325),
        ("power for energy 3600 J over 60 s", 60.0),
        ("pressure for force 100 N over area 4 m2", 25.0),
        ("density for mass 50 kg volume 2 m3", 25.0),
        ("mass for density 1000 kg/m3 volume 0.25 m3", 250.0),
        ("work for force 20 N distance 5 m", 100.0),
        ("impulse for force 30 N over 2 s", 60.0),
        ("frequency for period 0.02 s", 50.0),
        ("period for frequency 60 Hz", 1.0 / 60.0),
        ("wavelength at speed 343 m/s frequency 686 Hz", 0.5),
        ("wave speed for frequency 50 Hz wavelength 2 m", 100.0),
        ("current for voltage 12 V resistance 6 ohms", 2.0),
        ("resistance for voltage 12 V current 2 A", 6.0),
        ("electrical power for voltage 12 V current 2 A", 24.0),
        ("electrical energy for power 100 W over 3 hours", 300.0),
        ("charge for current 2 A over 30 s", 60.0),
        ("mass energy for 1 kg", 299_792_458.0 * 299_792_458.0),
        ("photon energy for frequency 5e14 Hz", 6.626_070_15e-34 * 5e14),
        ("free fall distance after 3 s", 0.5 * 9.80665 * 9),
        ("ideal gas pressure for 1 mol at 300 K in 0.024 m3", 8.314_462_618_153_24 * 300 / 0.024),
        ("centripetal force mass 2 kg velocity 10 m/s radius 5 m", 40.0),
        ("centripetal acceleration velocity 10 m/s radius 5 m", 20.0),
        ("spring energy k 200 N/m stretch 0.1 m", 1.0),
        ("hooke force k 200 N/m stretch 0.1 m", 20.0),
        ("gravitational force masses 5 kg and 10 kg distance 2 m", 8.342_875e-10),
    ] as [(String, Double)])
    func physics(expression: String, expected: Double) async throws {
        try await expectNumeric(expression, expected)
    }

    @Test("Scientific and astronomical constants", arguments: [
        ("speed of light constant", 299_792_458.0),
        ("gravitational constant", 6.67430e-11),
        ("planck constant", 6.626_070_15e-34),
        ("reduced planck constant", 1.054_571_817e-34),
        ("avogadro constant", 6.022_140_76e23),
        ("boltzmann constant", 1.380_649e-23),
        ("elementary charge constant", 1.602_176_634e-19),
        ("standard gravity constant", 9.80665),
        ("molar gas constant", 8.314_462_618_153_24),
        ("vacuum permittivity", 8.854_187_818_8e-12),
        ("vacuum permeability", 1.256_637_061_27e-6),
        ("electron mass constant", 9.109_383_713_9e-31),
        ("proton mass constant", 1.672_621_925_95e-27),
        ("astronomical unit in meters", 149_597_870_700.0),
        ("light year in meters", 9_460_730_472_580_800.0),
        ("parsec in meters", 3.085_677_581_491_367e16),
        ("mean earth radius", 6_371_008.8),
        ("earth mass constant", 5.9722e24),
        ("what is the speed of light", 299_792_458.0),
        ("value of Planck's constant", 6.626_070_15e-34),
        ("Avogadro's number", 6.022_140_76e23),
    ] as [(String, Double)])
    func constants(expression: String, expected: Double) async throws {
        try await expectNumeric(expression, expected)
    }

    @Test("Numeric, notation, media, and developer transformations", arguments: [
        ("22/7 as decimal", 22.0 / 7.0),
        ("12 degrees 30 minutes as decimal degrees", 12.5),
        ("height for 3:2 aspect ratio width 1920", 1_280.0),
        ("pixels in 4k uhd", 8_294_400.0),
        ("megapixels for 6000 by 4000", 24.0),
        ("uncompressed rgb size 1920 by 1080 at 8 bits per channel", 6_220_800.0),
        ("audio size at 320 kbps for 5 minutes", 12.0),
        ("video bitrate for 1 GB over 10 minutes", 13.333_333_333_333_334),
        ("250 basis points as percent", 2.5),
        ("2.5 percent as basis points", 250.0),
    ] as [(String, Double)])
    func numericTransformations(expression: String, expected: Double) async throws {
        try await expectNumeric(expression, expected)
    }

    @Test("Textual numeric transformations", arguments: [
        ("255 to roman numerals", "CCLV"),
        ("roman numeral MCMXCIV to decimal", "1994"),
        ("0.375 as fraction", "3/8"),
        ("2.125 as mixed fraction", "2 1/8"),
        ("1234567 in scientific notation", "1.234567 × 10^6"),
        ("0.00045 in engineering notation", "450 × 10^-6"),
        ("12.5 degrees as degrees minutes seconds", "12° 30′ 0″"),
        ("aspect ratio of 1920 by 1080", "16:9"),
        ("luhn check 4532015112830366", "true"),
        ("luhn check 123456", "false"),
        ("755 as unix permissions", "rwxr-xr-x"),
    ])
    func textTransformations(expression: String, expected: String) async throws {
        #expect(try await textValue(expression) == expected)
    }

    @Test("Everyday planning and proportional calculations", arguments: [
        ("scale 2.5 cups from 4 servings to 10 servings", 6.25),
        ("unit price for 18 dollars and 12 items", 1.5),
        ("fuel cost for 300 miles at 30 mpg and 3.50 per gallon", 35.0),
        ("fuel cost per mile at 3.50 per gallon and 28 mpg", 0.125),
        ("paint needed for 500 square feet at 350 square feet per gallon", 500.0 / 350.0),
        ("paint cans needed for 500 square feet at 350 square feet per can", 2.0),
        ("tiles needed for 120 square feet with 10% waste and 1.5 square feet per tile", 88.0),
        ("battery runtime for 60 Wh at 15 W", 4.0),
        ("battery charge time for 60 Wh at 30 W with 90% efficiency", 60.0 / 27.0),
        ("grade for 42 points out of 50", 84.0),
        ("weighted grade current 80 worth 60% final 90 worth 40%", 84.0),
        ("needed final score for target 85 current 80 worth 60% final worth 40%", 92.5),
        ("average speed for 60 miles at 30 mph and 60 miles at 60 mph", 40.0),
        ("ppi for 2560 by 1600 at 13.3 inches", hypot(2560, 1600) / 13.3),
        ("map distance for 4 cm at scale 1:50000 in km", 2.0),
        ("probability percent from odds 3 to 2", 60.0),
        ("split 120 with 8.25% tax and 20% tip among 4 people", 38.475),
    ] as [(String, Double)])
    func everyday(expression: String, expected: Double) async throws {
        try await expectNumeric(expression, expected)
    }

    @Test("Everyday text decisions", arguments: [
        ("better unit price between 12 for 18 and 20 for 28", "20 for 28"),
        ("odds from probability 75%", "3:1"),
    ])
    func everydayText(expression: String, expected: String) async throws {
        #expect(try await textValue(expression) == expected)
    }

    @Test("Expanded formulas reject undefined or unsafe domains", arguments: [
        "sample variance of 5",
        "harmonic mean of 4, 0",
        "map 5 from range 1 to 1 into 0 to 100",
        "fibonacci number 1000000",
        "area of triangle sides 1, 2, 10",
        "period for frequency 0 Hz",
        "roman numeral IIII to decimal",
        "battery charge time for 60 Wh at 0 W with 90% efficiency",
    ])
    func invalidDomains(expression: String) async {
        let outcome = await service.evaluate(expression, context: context)
        if case .success = outcome {
            Issue.record("Expected \(expression) to fail")
        }
    }

    @Test("Structured formulas do not steal unrelated launcher or scheduling phrases")
    func classifierBoundaries() async throws {
        #expect(await service.evaluate("map downtown", context: context) == .notCalculator)
        try await expectNumeric("split 8 hours into 30-minute blocks", 16)
    }

    private func expectNumeric(_ expression: String, _ expected: Double) async throws {
        let actual = try await numericValue(expression)
        let tolerance = expected == 0 ? 1e-12 : max(abs(expected) * 1e-9, 1e-300)
        #expect(abs(actual - expected) <= tolerance, "\(expression) produced \(actual), expected \(expected)")
    }

    private func numericValue(_ expression: String) async throws -> Double {
        let outcome = await service.evaluate(expression, context: context)
        guard case .success(let result) = outcome else {
            Issue.record("Expected success for \(expression), got \(outcome)")
            throw ExpandedCoverageError.failed(expression)
        }
        switch result.primaryValue {
        case .decimal(let value):
            return NSDecimalNumber(decimal: value).doubleValue
        case .double(let value):
            return value
        default:
            Issue.record("Expected numeric result for \(expression), got \(result.primaryValue)")
            throw ExpandedCoverageError.failed(expression)
        }
    }

    private func textValue(_ expression: String) async throws -> String {
        let outcome = await service.evaluate(expression, context: context)
        guard case .success(let result) = outcome, case .text(let value) = result.primaryValue else {
            Issue.record("Expected text success for \(expression), got \(outcome)")
            throw ExpandedCoverageError.failed(expression)
        }
        return value
    }

    private enum ExpandedCoverageError: Error {
        case failed(String)
    }
}
