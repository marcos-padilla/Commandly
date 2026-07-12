import Foundation
import Testing
@testable import CalculatorKit

@Suite("Calculator unit conversion coverage", .serialized)
struct CalculatorUnitCoverageTests {
    private let service = CalculatorService()

    private func context() -> CalculatorEvaluationContext {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return CalculatorEvaluationContext(
            locale: Locale(identifier: "en_US"),
            calendar: calendar,
            timeZone: .gmt,
            now: Date(timeIntervalSince1970: 1_735_689_600)
        )
    }

    private func measurement(_ expression: String) async throws -> CalculatorMeasurementValue {
        let outcome = await service.evaluate(expression, context: context())
        guard case .success(let result) = outcome,
              case .measurement(let measurement) = result.primaryValue
        else {
            Issue.record("Expected measurement success for \(expression), got \(outcome)")
            throw CalculatorUserFacingError(message: "Expected measurement success")
        }
        return measurement
    }

    @Test("Corpus unit conversions", arguments: [
        ("10 km to miles", CalculatorUnitDimension.length, 6.213_711_922_4, 0.000_001),
        ("100 centimeters in inches", .length, 39.370_078_74, 0.000_001),
        ("1 mile in kilometers", .length, 1.609_344, 0.000_001),
        ("2500 mm to meters", .length, 2.5, 0.000_001),
        ("6 ft 2 in to cm", .length, 187.96, 0.000_001),
        ("1 nautical mile in km", .length, 1.852, 0.000_001),
        ("1 acre in square feet", .area, 43_560, 0.001),
        ("2 hectares in acres", .area, 4.942_107_6, 0.000_001),
        ("10 m2 in ft2", .area, 107.639_104, 0.000_1),
        ("100 square meters to square feet", .area, 1_076.391_04, 0.001),
        ("5000 sq ft to acres", .area, 0.114_784_205_7, 0.000_001),
        ("1 gallon in liters", .volume, 3.785_411_784, 0.000_001),
        ("1 imperial gallon in liters", .volume, 4.546_09, 0.000_001),
        ("5 liters to gallons", .volume, 1.320_860_26, 0.000_001),
        ("2 cups in milliliters", .volume, 473.176_473, 0.001),
        ("3 tablespoons in teaspoons", .volume, 9, 0.000_001),
        ("16 fluid ounces in cups", .volume, 2, 0.000_001),
        ("1 cubic meter in cubic feet", .volume, 35.314_666_7, 0.000_1),
        ("150 pounds in kilograms", .mass, 68.038_855_5, 0.000_1),
        ("10 kg to lb", .mass, 22.046_226_2, 0.000_1),
        ("500 grams to ounces", .mass, 17.636_981, 0.000_1),
        ("1 metric ton in pounds", .mass, 2_204.622_62, 0.001),
        ("1 long ton in kilograms", .mass, 1_016.046_908_8, 0.000_1),
        ("16 ounces in pounds", .mass, 1, 0.000_001),
        ("273.15 K to C", .temperature, 0, 0.000_001),
        ("32 F in C", .temperature, 0, 0.000_001),
        ("100 Celsius to Fahrenheit", .temperature, 212, 0.000_001),
        ("-40 C in F", .temperature, -40, 0.000_001),
        ("70 degrees Fahrenheit in Celsius", .temperature, 21.111_111_1, 0.000_1),
        ("350 F in C", .temperature, 176.666_666_7, 0.000_1),
        ("3 days in hours", .duration, 72, 0.000_001),
        ("2 hours in minutes", .duration, 120, 0.000_001),
        ("90 minutes in hours", .duration, 1.5, 0.000_001),
        ("1 week in seconds", .duration, 604_800, 0.001),
        ("1 year in days", .duration, 365.242_5, 0.000_001),
        ("1 year in seconds", .duration, 31_556_952, 0.001),
        ("60 mph in km/h", .speed, 96.560_64, 0.000_1),
        ("100 km/h to mph", .speed, 62.137_119_22, 0.000_1),
        ("10 meters per second in mph", .speed, 22.369_362_9, 0.000_1),
        ("20 knots to mph", .speed, 23.015_589, 0.000_1),
        ("speed of sound in mph", .speed, 767.269_148, 0.001),
        ("9.81 m/s2 in ft/s2", .acceleration, 32.185_039_37, 0.000_1),
        ("1 g in m/s2", .acceleration, 9.806_65, 0.000_001),
        ("30 psi in bar", .pressure, 2.068_427_19, 0.000_001),
        ("1 atmosphere in pascals", .pressure, 101_325, 0.001),
        ("101325 Pa to atm", .pressure, 1, 0.000_001),
        ("760 mmHg to psi", .pressure, 14.695_948_8, 0.000_1),
        ("100 joules in calories", .energy, 23.900_573_6, 0.000_1),
        ("500 calories to kilojoules", .energy, 2.092, 0.000_001),
        ("1 kWh in joules", .energy, 3_600_000, 0.001),
        ("1 BTU in joules", .energy, 1_055.055_852_62, 0.000_1),
        ("1000 watts in horsepower", .power, 1.341_022_09, 0.000_1),
        ("1 horsepower to watts", .power, 745.7, 0.001),
        ("5 kilowatts in watts", .power, 5_000, 0.000_001),
        ("1000 Hz in kHz", .frequency, 1, 0.000_001),
        ("2.4 GHz in MHz", .frequency, 2_400, 0.000_001),
        ("60 cycles per second in hertz", .frequency, 60, 0.000_001),
        ("1 GB in MB", .dataStorage, 1_000, 0.000_001),
        ("1 GiB in MiB", .dataStorage, 1_024, 0.000_001),
        ("500 MB in bytes", .dataStorage, 500_000_000, 0.001),
        ("1 terabyte in gigabytes", .dataStorage, 1_000, 0.000_001),
        ("8 bits in bytes", .dataStorage, 1, 0.000_001),
        ("100 Mbps in MB/s", .dataTransferRate, 12.5, 0.000_001),
        ("1 Gbps in MB/s", .dataTransferRate, 125, 0.000_001),
        ("10 megabytes per second in megabits per second", .dataTransferRate, 80, 0.000_001),
        ("30 mpg in liters per 100 kilometers", .fuelEfficiency, 7.840_486_11, 0.000_1),
        ("30 mpg in liters per 100 km", .fuelEfficiency, 7.840_486_11, 0.000_1),
        ("8 L/100km in mpg", .fuelEfficiency, 29.401_822_5, 0.000_1),
        ("25 imperial mpg in US mpg", .fuelEfficiency, 20.816_833, 0.000_1),
        ("180 degrees in radians", .angle, Double.pi, 0.000_000_001),
        ("pi radians in degrees", .angle, 180, 0.000_000_001),
        ("100 gradians in degrees", .angle, 90, 0.000_001),
        ("1 turn in degrees", .angle, 360, 0.000_001),
        ("100 lb-ft in Nm", .torque, 135.581_794_8, 0.000_1),
        ("50 newton meters in pound feet", .torque, 36.878_107, 0.000_1),
        ("100 newtons in pounds force", .force, 22.480_894_3, 0.000_1),
        ("10 lbf in newtons", .force, 44.482_216_15, 0.000_1),
        ("1 g/cm3 in kg/m3", .density, 1_000, 0.000_001),
        ("62.4 lb/ft3 in kg/m3", .density, 999.552_114_5, 0.001),
        ("10 gallons per minute in liters per second", .volumeFlowRate, 0.630_901_964, 0.000_001),
        ("100 cubic feet per minute in cubic meters per hour", .volumeFlowRate, 169.901_082, 0.001),
        ("1000 milliamps in amps", .electricCurrent, 1, 0.000_001),
        ("2 A in mA", .electricCurrent, 2_000, 0.000_001),
        ("120 volts in millivolts", .electricPotential, 120_000, 0.001),
        ("5 kV in volts", .electricPotential, 5_000, 0.000_001),
        ("2 megaohms in ohms", .resistance, 2_000_000, 0.001),
        ("1000 ohms in kiloohms", .resistance, 1, 0.000_001),
        ("500 lux in foot candles", .illuminance, 46.451_52, 0.000_1),
        ("10 foot candles in lux", .illuminance, 107.639_104_2, 0.000_1),
        ("watts if volts are 120 and amps are 10", .power, 1_200, 0.000_001),
        ("120 volts * 10 amps", .power, 1_200, 0.000_001),
        ("amps for 1500 watts at 120 volts", .electricCurrent, 12.5, 0.000_001),
        ("volts for 500 watts at 5 amps", .electricPotential, 100, 0.000_001),
        ("convert 5 feet to meters", .length, 1.524, 0.000_001),
        ("how many meters are in 5 feet", .length, 1.524, 0.000_001),
        ("convert 10 km mi", .length, 6.213_711_922_4, 0.000_001),
        ("5ft cm", .length, 152.4, 0.000_001),
        ("90min hr", .duration, 1.5, 0.000_001),
    ])
    func conversion(
        expression: String,
        dimension: CalculatorUnitDimension,
        expected: Double,
        tolerance: Double
    ) async throws {
        let result = try await measurement(expression)
        #expect(result.dimension == dimension)
        #expect(abs(result.value - expected) <= tolerance, "Expected \(expected), got \(result.value) for \(expression)")
    }

    @Test("Unqualified US gallon records its assumption")
    func gallonAssumption() async throws {
        let outcome = await service.evaluate("1 gallon in liters", context: context())
        guard case .success(let result) = outcome else {
            Issue.record("Expected gallon conversion success")
            return
        }
        #expect(result.metadata.notes.contains { $0.contains("US liquid gallon") })
    }

    @Test("Mean Gregorian year records its duration assumption")
    func yearAssumption() async throws {
        let outcome = await service.evaluate("1 year in days", context: context())
        guard case .success(let result) = outcome else {
            Issue.record("Expected year conversion success")
            return
        }
        #expect(result.metadata.notes.contains { $0.contains("365.2425") })
    }

    @Test("Ingredient volume-to-mass conversion is not fabricated")
    func ingredientDensityRequired() async {
        for expression in ["2 cups flour in grams", "1 cup sugar in grams", "3 tablespoons butter in grams"] {
            let outcome = await service.evaluate(expression, context: context())
            if case .success = outcome {
                Issue.record("Ingredient-dependent conversion must not succeed without density data: \(expression)")
            }
        }
    }

    @Test("Calendar months are not fabricated as fixed durations")
    func monthDurationRequiresContext() async {
        let outcome = await service.evaluate("1 month in days", context: context())
        if case .success = outcome { Issue.record("A month must not be treated as a fixed duration") }
    }
}
