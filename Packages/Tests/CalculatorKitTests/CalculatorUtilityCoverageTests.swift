import Foundation
import Testing
@testable import CalculatorKit

@Suite("Calculator geometry, health, business, and developer coverage", .serialized)
struct CalculatorUtilityCoverageTests {
    private let service = CalculatorService()

    private func context() -> CalculatorEvaluationContext {
        CalculatorEvaluationContext(locale: Locale(identifier: "en_US"), calendar: Calendar(identifier: .gregorian), timeZone: .gmt)
    }

    private func result(_ expression: String) async throws -> CalculatorResult {
        let outcome = await service.evaluate(expression, context: context())
        guard case .success(let result) = outcome else {
            Issue.record("Expected utility success for \(expression), got \(outcome)")
            throw CalculatorUserFacingError(message: "Expected utility success")
        }
        return result
    }

    private func value(_ expression: String) async throws -> Double {
        let result = try await result(expression)
        guard case .decimal(let decimal) = result.primaryValue, let value = DecimalMath.toDouble(decimal) else {
            Issue.record("Expected decimal for \(expression)")
            throw CalculatorUserFacingError(message: "Expected decimal")
        }
        return value
    }

    private func text(_ expression: String) async throws -> String {
        let result = try await result(expression)
        guard case .text(let value) = result.primaryValue else {
            Issue.record("Expected text for \(expression)")
            throw CalculatorUserFacingError(message: "Expected text")
        }
        return value
    }

    @Test("Geometry formulas", arguments: [
        ("area of a rectangle 10 by 5", 50.0, 0.000_001),
        ("perimeter of a 10 by 5 rectangle", 30.0, 0.000_001),
        ("area of a square with side 8", 64.0, 0.000_001),
        ("diagonal of a 10 by 5 rectangle", 11.180_339_887, 0.000_001),
        ("area of a circle radius 5", 78.539_816_34, 0.000_001),
        ("circumference of a circle diameter 10", 31.415_926_536, 0.000_001),
        ("circle diameter from circumference 31.4159", 9.999_991_55, 0.000_01),
        ("area of a triangle base 10 height 5", 25.0, 0.000_001),
        ("hypotenuse with sides 3 and 4", 5.0, 0.000_001),
        ("third side of a right triangle with hypotenuse 13 and side 5", 12.0, 0.000_001),
        ("volume of a cube side 5", 125.0, 0.000_001),
        ("volume of a box 10 by 5 by 3", 150.0, 0.000_001),
        ("surface area of a sphere radius 4", 201.061_929_83, 0.000_001),
        ("volume of a cylinder radius 3 height 10", 282.743_338_82, 0.000_001),
        ("volume of a cone radius 5 height 12", 314.159_265_36, 0.000_001),
    ])
    func geometry(expression: String, expected: Double, tolerance: Double) async throws {
        let actual = try await value(expression)
        #expect(abs(actual - expected) <= tolerance, "Expected \(expected), got \(actual) for \(expression)")
    }

    @Test("Health and fitness arithmetic")
    func health() async throws {
        #expect(abs(try await value("BMI for 150 lb and 5 ft 7 in") - 23.493) < 0.001)
        #expect(abs(try await value("BMI for 68 kg and 170 cm") - 23.529) < 0.001)
        #expect(try await value("running pace for 5 km in 25 minutes") == 300)
        #expect(try await value("mile pace for 10 km in 50 minutes") == 483)
        #expect(try await value("time for a marathon at 8-minute mile pace") == 12_585)
        #expect(try await value("distance at 6 mph for 30 minutes") == 3)
        #expect(try await value("time to travel 10 miles at 50 mph") == 720)
        #expect(try await value("speed for 100 km in 2 hours") == 50)
        #expect(try await value("2500 calories per day for 7 days") == 17_500)
        let surplus = try await result("500 calorie surplus per day for 30 days")
        #expect(surplus.primaryValue == .decimal(15_000))
        #expect(surplus.metadata.notes.contains { $0.contains("no weight-change guarantee") })
    }

    @Test("Business and productivity formulas")
    func business() async throws {
        #expect(try await value("hours from 8:30am to 5pm with a 30-minute lunch") == 8)
        #expect(try await value("weekly hours for 8 hours a day 5 days a week") == 40)
        #expect(abs(try await value("monthly hours at 40 hours per week") - 173.333_333) < 0.000_01)
        #expect(try await value("subtotal 125 + 250 + 75") == 450)
        #expect(try await value("add 7% tax to 450") == 481.5)
        #expect(try await value("450 plus 7% tax and 20% tip") == 571.5)
        #expect(try await value("5% commission on 50000") == 2_500)
        #expect(try await value("commission on 100000 at 3% plus 10% over 75000") == 5_500)
        #expect(try await value("50 conversions from 1000 visits") == 5)
        #expect(try await value("conversion rate for 25 sales from 500 leads") == 5)
        #expect(try await value("increase conversion rate from 2% to 3%") == 50)
        #expect(try await value("growth from 1000 to 1350") == 35)
        #expect(abs(try await value("monthly growth rate from 1000 to 2000 over 12 months") - 5.946_309) < 0.000_01)
        #expect(abs(try await value("CAGR from 50000 to 100000 in 4 years") - 18.920_712) < 0.000_01)
        #expect(try await value("CPA if spend is 5000 and customers are 50") == 100)
        #expect(try await value("ROAS if revenue is 20000 and ad spend is 5000") == 4)
        #expect(try await value("ROI if investment is 10000 and profit is 2500") == 25)
    }

    @Test("Number bases and bitwise operations")
    func basesAndBits() async throws {
        #expect(try await text("255 in binary") == "11111111")
        #expect(try await value("1010 binary to decimal") == 10)
        #expect(try await value("FF hex to decimal") == 255)
        #expect(try await text("42 decimal to hexadecimal") == "2A")
        #expect(try await text("0xFF + 0x10") == "0x10F")
        #expect(try await text("0b1010 in hex") == "A")
        #expect(try await value("5 AND 3") == 1)
        #expect(try await value("5 & 3") == 1)
        #expect(try await value("5 OR 2") == 7)
        #expect(try await value("5 | 2") == 7)
        #expect(try await value("5 XOR 3") == 6)
        #expect(try await value("5 ^ 3 bitwise") == 6)
        #expect(try await value("NOT 5") == -6)
        #expect(try await value("5 << 2") == 20)
        #expect(try await value("20 >> 2") == 5)
    }

    @Test("Character, color, transfer, and URL utilities")
    func developerUtilities() async throws {
        #expect(try await value("ASCII code for A") == 65)
        #expect(try await text("character for ASCII 65") == "A")
        #expect(try await text("Unicode for €") == "U+20AC")
        #expect(try await text("U+1F600 as character") == "😀")
        #expect(try await text("#FF0000 to RGB") == "rgb(255, 0, 0)")
        #expect(try await text("rgb(255, 0, 0) to hex") == "#FF0000")
        #expect(try await text("hsl(120, 100%, 50%) to rgb") == "rgb(0, 255, 0)")
        #expect(try await value("download time for 10 GB at 100 Mbps") == 800)
        #expect(try await value("upload 5 GB at 20 Mbps") == 2_000)
        #expect(try await value("how long to transfer 1 TB at 1 Gbps") == 8_000)
        #expect(try await text("URL encode hello world") == "hello%20world")
        #expect(try await text("decode hello%20world") == "hello world")
        #expect(try await text("base64 encode hello") == "aGVsbG8=")
        #expect(try await text("base64 decode aGVsbG8=") == "hello")
    }
}
