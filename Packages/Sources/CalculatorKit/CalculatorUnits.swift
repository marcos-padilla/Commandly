import Foundation

/// Unit dimension categories supported by CalculatorKit.
public enum CalculatorUnitDimension: String, Sendable, Equatable, CaseIterable {
    case length
    case area
    case volume
    case mass
    case temperature
    case duration
    case speed
    case pressure
    case energy
    case power
    case frequency
    case fuelEfficiency
    case dataStorage
    case angle
    case electricCharge
    case electricCurrent
    case electricPotential
    case resistance
}

struct UnitDefinition: Sendable {
    let id: String
    let dimension: CalculatorUnitDimension
    let symbol: String
    let aliases: [String]
    let unit: Dimension
}

/// Central registry of Foundation `Measurement` units and aliases.
final class CalculatorUnitRegistry: @unchecked Sendable {
    static let shared = CalculatorUnitRegistry()

    private let definitions: [UnitDefinition]
    private let aliasMap: [String: [UnitDefinition]]

    private init() {
        var defs: [UnitDefinition] = []

        func add<U: Dimension>(_ id: String, _ dimension: CalculatorUnitDimension, _ unit: U, _ symbol: String, _ aliases: [String]) {
            defs.append(UnitDefinition(id: id, dimension: dimension, symbol: symbol, aliases: aliases.map { $0.lowercased() }, unit: unit))
        }

        // Length
        add("meter", .length, UnitLength.meters, "m", ["m", "meter", "meters", "metre", "metres"])
        add("kilometer", .length, UnitLength.kilometers, "km", ["km", "kilometer", "kilometers", "kilometre", "kilometres"])
        add("centimeter", .length, UnitLength.centimeters, "cm", ["cm", "centimeter", "centimeters", "centimetre", "centimetres"])
        add("millimeter", .length, UnitLength.millimeters, "mm", ["mm", "millimeter", "millimeters"])
        add("mile", .length, UnitLength.miles, "mi", ["mi", "mile", "miles"])
        add("yard", .length, UnitLength.yards, "yd", ["yd", "yard", "yards"])
        add("foot", .length, UnitLength.feet, "ft", ["ft", "foot", "feet"])
        add("inch", .length, UnitLength.inches, "in", ["inch", "inches", "\""])
        add("nauticalMile", .length, UnitLength.nauticalMiles, "nmi", ["nmi", "nautical mile", "nautical miles"])

        // Area
        add("squareMeter", .area, UnitArea.squareMeters, "m²", ["m2", "m²", "square meter", "square meters", "sq m"])
        add("squareKilometer", .area, UnitArea.squareKilometers, "km²", ["km2", "km²", "square kilometer", "square kilometers"])
        add("squareFoot", .area, UnitArea.squareFeet, "ft²", ["ft2", "ft²", "square foot", "square feet", "sq ft"])
        add("acre", .area, UnitArea.acres, "ac", ["acre", "acres", "ac"])
        add("hectare", .area, UnitArea.hectares, "ha", ["hectare", "hectares", "ha"])

        // Volume
        add("liter", .volume, UnitVolume.liters, "L", ["l", "liter", "liters", "litre", "litres"])
        add("milliliter", .volume, UnitVolume.milliliters, "mL", ["ml", "milliliter", "milliliters"])
        add("gallon", .volume, UnitVolume.gallons, "gal", ["gal", "gallon", "gallons"])
        add("quart", .volume, UnitVolume.quarts, "qt", ["qt", "quart", "quarts"])
        add("pint", .volume, UnitVolume.pints, "pt", ["pt", "pint", "pints"])
        add("cup", .volume, UnitVolume.cups, "cup", ["cup", "cups"])
        add("cubicMeter", .volume, UnitVolume.cubicMeters, "m³", ["m3", "m³", "cubic meter", "cubic meters"])

        // Mass
        add("kilogram", .mass, UnitMass.kilograms, "kg", ["kg", "kilogram", "kilograms"])
        add("gram", .mass, UnitMass.grams, "g", ["g", "gram", "grams"])
        add("milligram", .mass, UnitMass.milligrams, "mg", ["mg", "milligram", "milligrams"])
        add("pound", .mass, UnitMass.pounds, "lb", ["lb", "lbs", "pound", "pounds"])
        add("ounce", .mass, UnitMass.ounces, "oz", ["oz", "ounce", "ounces"])
        add("stone", .mass, UnitMass.stones, "st", ["st", "stone", "stones"])
        add("metricTon", .mass, UnitMass.metricTons, "t", ["tonne", "tonnes", "metric ton", "metric tons"])

        // Temperature
        add("celsius", .temperature, UnitTemperature.celsius, "°C", ["c", "celsius", "centigrade", "°c"])
        add("fahrenheit", .temperature, UnitTemperature.fahrenheit, "°F", ["f", "fahrenheit", "°f"])
        add("kelvin", .temperature, UnitTemperature.kelvin, "K", ["k", "kelvin", "kelvins"])

        // Duration
        add("second", .duration, UnitDuration.seconds, "s", ["s", "sec", "secs", "second", "seconds"])
        add("minute", .duration, UnitDuration.minutes, "min", ["min", "mins", "minute", "minutes"])
        add("hour", .duration, UnitDuration.hours, "hr", ["h", "hr", "hrs", "hour", "hours"])

        // Speed
        add("metersPerSecond", .speed, UnitSpeed.metersPerSecond, "m/s", ["m/s", "mps"])
        add("kilometersPerHour", .speed, UnitSpeed.kilometersPerHour, "km/h", ["km/h", "kph", "kmh"])
        add("milesPerHour", .speed, UnitSpeed.milesPerHour, "mph", ["mph", "mi/h"])
        add("knots", .speed, UnitSpeed.knots, "kn", ["kn", "kt", "knot", "knots"])

        // Pressure
        add("pascal", .pressure, UnitPressure.newtonsPerMetersSquared, "Pa", ["pa", "pascal", "pascals"])
        add("kilopascal", .pressure, UnitPressure.kilopascals, "kPa", ["kpa", "kilopascal", "kilopascals"])
        add("bar", .pressure, UnitPressure.bars, "bar", ["bar", "bars"])
        add("psi", .pressure, UnitPressure.poundsForcePerSquareInch, "psi", ["psi"])
        add("hectopascal", .pressure, UnitPressure.hectopascals, "hPa", ["hpa", "hectopascal", "hectopascals"])

        // Energy
        add("joule", .energy, UnitEnergy.joules, "J", ["j", "joule", "joules"])
        add("kilojoule", .energy, UnitEnergy.kilojoules, "kJ", ["kj", "kilojoule", "kilojoules"])
        add("calorie", .energy, UnitEnergy.calories, "cal", ["cal", "calorie", "calories"])
        add("kilocalorie", .energy, UnitEnergy.kilocalories, "kcal", ["kcal", "kilocalorie", "kilocalories"])
        add("kilowattHour", .energy, UnitEnergy.kilowattHours, "kWh", ["kwh", "kilowatt hour", "kilowatt hours"])

        // Power
        add("watt", .power, UnitPower.watts, "W", ["w", "watt", "watts"])
        add("kilowatt", .power, UnitPower.kilowatts, "kW", ["kw", "kilowatt", "kilowatts"])
        add("horsepower", .power, UnitPower.horsepower, "hp", ["hp", "horsepower"])

        // Frequency
        add("hertz", .frequency, UnitFrequency.hertz, "Hz", ["hz", "hertz"])
        add("kilohertz", .frequency, UnitFrequency.kilohertz, "kHz", ["khz", "kilohertz"])
        add("megahertz", .frequency, UnitFrequency.megahertz, "MHz", ["mhz", "megahertz"])
        add("gigahertz", .frequency, UnitFrequency.gigahertz, "GHz", ["ghz", "gigahertz"])

        // Fuel efficiency
        add("litersPer100Kilometers", .fuelEfficiency, UnitFuelEfficiency.litersPer100Kilometers, "L/100km", ["l/100km", "liters per 100 kilometers"])
        add("milesPerGallon", .fuelEfficiency, UnitFuelEfficiency.milesPerGallon, "mpg", ["mpg", "miles per gallon"])

        // Data storage
        add("byte", .dataStorage, UnitInformationStorage.bytes, "B", ["b", "byte", "bytes"])
        add("kilobyte", .dataStorage, UnitInformationStorage.kilobytes, "KB", ["kb", "kilobyte", "kilobytes"])
        add("megabyte", .dataStorage, UnitInformationStorage.megabytes, "MB", ["mb", "megabyte", "megabytes"])
        add("gigabyte", .dataStorage, UnitInformationStorage.gigabytes, "GB", ["gb", "gigabyte", "gigabytes"])
        add("terabyte", .dataStorage, UnitInformationStorage.terabytes, "TB", ["tb", "terabyte", "terabytes"])

        // Angle
        add("degree", .angle, UnitAngle.degrees, "°", ["deg", "degree", "degrees"])
        add("radian", .angle, UnitAngle.radians, "rad", ["rad", "radian", "radians"])

        // Electric
        add("coulomb", .electricCharge, UnitElectricCharge.coulombs, "C", ["coulomb", "coulombs"])
        add("ampere", .electricCurrent, UnitElectricCurrent.amperes, "A", ["a", "amp", "amps", "ampere", "amperes"])
        add("volt", .electricPotential, UnitElectricPotentialDifference.volts, "V", ["v", "volt", "volts"])
        add("ohm", .resistance, UnitElectricResistance.ohms, "Ω", ["ohm", "ohms"])

        definitions = defs
        var map: [String: [UnitDefinition]] = [:]
        for definition in defs {
            for alias in definition.aliases {
                map[alias, default: []].append(definition)
            }
            map[definition.id.lowercased(), default: []].append(definition)
        }
        aliasMap = map
    }

    func containsUnitToken(in text: String) -> Bool {
        let lowered = text.lowercased()
        for key in aliasMap.keys {
            if key.count <= 1 {
                // Avoid matching lone letters too aggressively unless spaced.
                if lowered.range(of: #"\b\#(NSRegularExpression.escapedPattern(for: key))\b"#, options: .regularExpression) != nil {
                    return true
                }
            } else if lowered.contains(key) {
                return true
            }
        }
        return false
    }

    func resolve(_ token: String, preferredDimension: CalculatorUnitDimension? = nil) throws -> UnitDefinition {
        let key = token.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard let candidates = aliasMap[key], !candidates.isEmpty else {
            throw CalculatorError.unknownUnit(token)
        }
        if let preferredDimension {
            let filtered = candidates.filter { $0.dimension == preferredDimension }
            if filtered.count == 1, let only = filtered.first {
                return only
            }
        }
        let uniqueByID = Dictionary(grouping: candidates, by: \.id).compactMap(\.value.first)
        if uniqueByID.count == 1, let only = uniqueByID.first {
            return only
        }
        // Prefer longer-form aliases over single-letter when ambiguous and no preference.
        if key.count > 1, let first = uniqueByID.first, uniqueByID.map(\.dimension).allSatisfy({ $0 == first.dimension }) {
            return first
        }
        throw CalculatorError.ambiguousUnit(token)
    }
}

/// Parses and evaluates unit conversion queries such as `5 feet in meters`.
enum CalculatorUnits {
    struct ConversionResult: Sendable, Equatable {
        let value: CalculatorMeasurementValue
        let metadata: CalculatorResultMetadata
        let displayExpression: String
    }

    static func evaluate(_ text: String, locale: Locale) throws -> ConversionResult {
        let lowered = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        // Compound duration: "2 hours 30 minutes in minutes"
        if let compound = try evaluateCompoundDuration(lowered, locale: locale) {
            return compound
        }

        guard let parsed = parseConversion(lowered) else {
            throw CalculatorError.unsupportedOperation
        }

        let fromDef = try CalculatorUnitRegistry.shared.resolve(parsed.fromUnit)
        let toDef = try CalculatorUnitRegistry.shared.resolve(parsed.toUnit, preferredDimension: fromDef.dimension)
        guard fromDef.dimension == toDef.dimension else {
            throw CalculatorError.incompatibleUnits
        }

        let measurement = Measurement(value: parsed.value, unit: fromDef.unit)
        let converted = measurement.converted(to: toDef.unit)

        let measurementValue = CalculatorMeasurementValue(
            value: converted.value,
            unitIdentifier: toDef.id,
            unitSymbol: toDef.symbol,
            dimension: toDef.dimension
        )
        var metadata = CalculatorResultMetadata(
            fromUnit: fromDef.id,
            toUnit: toDef.id
        )
        metadata.notes.append("Converted via Foundation Measurement")

        return ConversionResult(
            value: measurementValue,
            metadata: metadata,
            displayExpression: "\(formatNumber(parsed.value, locale: locale)) \(fromDef.symbol) → \(toDef.symbol)"
        )
    }

    private struct ParsedConversion {
        let value: Double
        let fromUnit: String
        let toUnit: String
    }

    private static func parseConversion(_ text: String) -> ParsedConversion? {
        let pattern = #"^([-+]?\d+(?:[.,]\d+)?)\s*(.+?)\s+(?:in|to|into|as)\s+(.+)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              match.numberOfRanges == 4,
              let valueRange = Range(match.range(at: 1), in: text),
              let fromRange = Range(match.range(at: 2), in: text),
              let toRange = Range(match.range(at: 3), in: text)
        else {
            return nil
        }
        let valueText = String(text[valueRange]).replacingOccurrences(of: ",", with: ".")
        guard let value = Double(valueText) else { return nil }
        return ParsedConversion(
            value: value,
            fromUnit: String(text[fromRange]).trimmingCharacters(in: .whitespacesAndNewlines),
            toUnit: String(text[toRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    private static func evaluateCompoundDuration(_ text: String, locale: Locale) throws -> ConversionResult? {
        let pattern = #"^(\d+)\s*hours?\s*(\d+)\s*minutes?\s+(?:in|to|into)\s+(.+)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              match.numberOfRanges == 4,
              let hoursRange = Range(match.range(at: 1), in: text),
              let minutesRange = Range(match.range(at: 2), in: text),
              let toRange = Range(match.range(at: 3), in: text)
        else {
            return nil
        }
        let hours = Double(String(text[hoursRange])) ?? 0
        let minutes = Double(String(text[minutesRange])) ?? 0
        let totalMinutes = hours * 60 + minutes
        let toUnitName = String(text[toRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        let fromDef = try CalculatorUnitRegistry.shared.resolve("minute")
        let toDef = try CalculatorUnitRegistry.shared.resolve(toUnitName, preferredDimension: .duration)
        let measurement = Measurement(value: totalMinutes, unit: fromDef.unit)
        let converted = measurement.converted(to: toDef.unit)
        let value = CalculatorMeasurementValue(
            value: converted.value,
            unitIdentifier: toDef.id,
            unitSymbol: toDef.symbol,
            dimension: .duration
        )
        return ConversionResult(
            value: value,
            metadata: CalculatorResultMetadata(fromUnit: "hour+minute", toUnit: toDef.id),
            displayExpression: "\(formatNumber(hours, locale: locale)) h \(formatNumber(minutes, locale: locale)) min → \(toDef.symbol)"
        )
    }

    private static func formatNumber(_ value: Double, locale: Locale) -> String {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 6
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }
}
