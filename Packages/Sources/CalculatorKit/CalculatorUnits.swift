import AppCore
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
    case acceleration
    case pressure
    case energy
    case power
    case frequency
    case fuelEfficiency
    case dataStorage
    case dataTransferRate
    case angle
    case torque
    case force
    case density
    case volumeFlowRate
    case illuminance
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
    let note: String?
}

/// Central registry of Foundation `Measurement` units and aliases.
///
/// Safety: definitions and their Foundation unit converters are constructed
/// once during initialization and are immutable afterward. Concurrent callers
/// only perform read-only lookup and conversion operations.
final class CalculatorUnitRegistry: @unchecked Sendable {
    static let shared = CalculatorUnitRegistry()

    private let definitions: [UnitDefinition]
    private let aliasMap: [String: [UnitDefinition]]

    private init() {
        var defs: [UnitDefinition] = []

        func add<U: Dimension>(
            _ id: String,
            _ dimension: CalculatorUnitDimension,
            _ unit: U,
            _ symbol: String,
            _ aliases: [String],
            note: String? = nil
        ) {
            defs.append(UnitDefinition(
                id: id,
                dimension: dimension,
                symbol: symbol,
                aliases: aliases.map { $0.lowercased() },
                unit: unit,
                note: note
            ))
        }

        // Custom linear dimensions use a concrete Foundation Dimension subclass
        // so Measurement can resolve a base unit safely. The public dimension
        // enum remains the semantic compatibility boundary.
        func linearUnit(symbol: String, coefficient: Double) -> UnitLength {
            UnitLength(symbol: symbol, converter: UnitConverterLinear(coefficient: coefficient))
        }

        // Length
        add("meter", .length, UnitLength.meters, "m", ["m", "meter", "meters", "metre", "metres"])
        add("kilometer", .length, UnitLength.kilometers, "km", ["km", "kilometer", "kilometers", "kilometre", "kilometres"])
        add("centimeter", .length, UnitLength.centimeters, "cm", ["cm", "centimeter", "centimeters", "centimetre", "centimetres"])
        add("millimeter", .length, UnitLength.millimeters, "mm", ["mm", "millimeter", "millimeters"])
        add("micrometer", .length, UnitLength.micrometers, "µm", ["um", "µm", "micrometer", "micrometers", "micron", "microns"])
        add("nanometer", .length, UnitLength.nanometers, "nm", ["nm", "nanometer", "nanometers"])
        add("mile", .length, UnitLength.miles, "mi", ["mi", "mile", "miles"])
        add("yard", .length, UnitLength.yards, "yd", ["yd", "yard", "yards"])
        add("foot", .length, UnitLength.feet, "ft", ["ft", "foot", "feet"])
        add("inch", .length, UnitLength.inches, "in", ["inch", "inches", "\""])
        add("nauticalMile", .length, UnitLength.nauticalMiles, "nmi", ["nmi", "nautical mile", "nautical miles"])

        // Area
        add("squareMeter", .area, UnitArea.squareMeters, "m²", ["m2", "m²", "square meter", "square meters", "sq m"])
        add("squareMillimeter", .area, UnitArea.squareMillimeters, "mm²", ["mm2", "mm^2", "square millimeter", "square millimeters", "sq mm"])
        add("squareCentimeter", .area, UnitArea.squareCentimeters, "cm²", ["cm2", "cm^2", "square centimeter", "square centimeters", "sq cm"])
        add("squareKilometer", .area, UnitArea.squareKilometers, "km²", ["km2", "km²", "square kilometer", "square kilometers"])
        add("squareInch", .area, UnitArea.squareInches, "in²", ["in2", "in^2", "square inch", "square inches", "sq in"])
        add("squareFoot", .area, UnitArea.squareFeet, "ft²", ["ft2", "ft²", "ft^2", "square foot", "square feet", "sq ft"])
        add("squareYard", .area, UnitArea.squareYards, "yd²", ["yd2", "yd^2", "square yard", "square yards", "sq yd"])
        add("squareMile", .area, UnitArea.squareMiles, "mi²", ["mi2", "mi^2", "square mile", "square miles", "sq mi"])
        add("acre", .area, UnitArea.acres, "ac", ["acre", "acres", "ac"])
        add("hectare", .area, UnitArea.hectares, "ha", ["hectare", "hectares", "ha"])

        // Volume
        add("liter", .volume, UnitVolume.liters, "L", ["l", "liter", "liters", "litre", "litres"])
        add("milliliter", .volume, UnitVolume.milliliters, "mL", ["ml", "milliliter", "milliliters"])
        add("cubicCentimeter", .volume, UnitVolume.cubicCentimeters, "cm³", ["cc", "cm3", "cm^3", "cubic centimeter", "cubic centimeters"])
        add("usGallon", .volume, UnitVolume(symbol: "US gal", converter: UnitConverterLinear(coefficient: 3.785_411_784)), "US gal", ["gal", "gallon", "gallons", "us gal", "us gallon", "us gallons"], note: "Unqualified gallon uses the US liquid gallon")
        add("imperialGallon", .volume, UnitVolume.imperialGallons, "imp gal", ["imperial gal", "imperial gallon", "imperial gallons", "uk gallon", "uk gallons"])
        add("quart", .volume, UnitVolume(symbol: "qt", converter: UnitConverterLinear(coefficient: 0.946_352_946)), "qt", ["qt", "quart", "quarts"])
        add("pint", .volume, UnitVolume(symbol: "pt", converter: UnitConverterLinear(coefficient: 0.473_176_473)), "pt", ["pt", "pint", "pints"])
        add("cup", .volume, UnitVolume(symbol: "cup", converter: UnitConverterLinear(coefficient: 0.236_588_236_5)), "cup", ["cup", "cups"], note: "Unqualified cooking volume uses US customary units")
        add("teaspoon", .volume, UnitVolume(symbol: "tsp", converter: UnitConverterLinear(coefficient: 0.004_928_921_593_75)), "tsp", ["tsp", "teaspoon", "teaspoons"])
        add("tablespoon", .volume, UnitVolume(symbol: "tbsp", converter: UnitConverterLinear(coefficient: 0.014_786_764_781_25)), "tbsp", ["tbsp", "tablespoon", "tablespoons"])
        add("fluidOunce", .volume, UnitVolume(symbol: "fl oz", converter: UnitConverterLinear(coefficient: 0.029_573_529_562_5)), "fl oz", ["fl oz", "fluid ounce", "fluid ounces"])
        add("imperialFluidOunce", .volume, UnitVolume.imperialFluidOunces, "imp fl oz", ["imperial fluid ounce", "imperial fluid ounces", "uk fl oz"])
        add("cubicMeter", .volume, UnitVolume.cubicMeters, "m³", ["m3", "m³", "m^3", "cubic meter", "cubic meters"])
        add("cubicInch", .volume, UnitVolume.cubicInches, "in³", ["in3", "in^3", "cubic inch", "cubic inches"])
        add("cubicFoot", .volume, UnitVolume.cubicFeet, "ft³", ["ft3", "ft^3", "cubic foot", "cubic feet"])
        add("cubicYard", .volume, UnitVolume.cubicYards, "yd³", ["yd3", "yd^3", "cubic yard", "cubic yards"])

        // Mass
        add("kilogram", .mass, UnitMass.kilograms, "kg", ["kg", "kilogram", "kilograms"])
        add("gram", .mass, UnitMass.grams, "g", ["g", "gram", "grams"])
        add("milligram", .mass, UnitMass.milligrams, "mg", ["mg", "milligram", "milligrams"])
        add("pound", .mass, UnitMass(symbol: "lb", converter: UnitConverterLinear(coefficient: 0.453_592_37)), "lb", ["lb", "lbs", "pound", "pounds"])
        add("ounce", .mass, UnitMass(symbol: "oz", converter: UnitConverterLinear(coefficient: 0.028_349_523_125)), "oz", ["oz", "ounce", "ounces"])
        add("stone", .mass, UnitMass(symbol: "st", converter: UnitConverterLinear(coefficient: 6.350_293_18)), "st", ["st", "stone", "stones"])
        add("metricTon", .mass, UnitMass.metricTons, "t", ["tonne", "tonnes", "metric ton", "metric tons"])
        add("shortTon", .mass, UnitMass(symbol: "short ton", converter: UnitConverterLinear(coefficient: 907.184_74)), "short ton", ["short ton", "short tons", "us ton", "us tons"])
        add("longTon", .mass, UnitMass(symbol: "long ton", converter: UnitConverterLinear(coefficient: 1_016.046_908_8)), "long ton", ["long ton", "long tons", "imperial ton", "imperial tons"])

        // Temperature
        add("celsius", .temperature, UnitTemperature.celsius, "°C", ["c", "celsius", "centigrade", "°c", "degree celsius", "degrees celsius"])
        add("fahrenheit", .temperature, UnitTemperature.fahrenheit, "°F", ["f", "fahrenheit", "°f", "degree fahrenheit", "degrees fahrenheit"])
        add("kelvin", .temperature, UnitTemperature.kelvin, "K", ["k", "kelvin", "kelvins"])

        // Duration
        add("second", .duration, UnitDuration.seconds, "s", ["s", "sec", "secs", "second", "seconds"])
        add("minute", .duration, UnitDuration.minutes, "min", ["min", "mins", "minute", "minutes"])
        add("hour", .duration, UnitDuration.hours, "hr", ["h", "hr", "hrs", "hour", "hours"])
        add("day", .duration, UnitDuration(symbol: "day", converter: UnitConverterLinear(coefficient: 86_400)), "day", ["day", "days"])
        add("week", .duration, UnitDuration(symbol: "wk", converter: UnitConverterLinear(coefficient: 604_800)), "wk", ["wk", "week", "weeks"])
        add("year", .duration, UnitDuration(symbol: "yr", converter: UnitConverterLinear(coefficient: 31_556_952)), "yr", ["yr", "year", "years"], note: "Duration years use the mean Gregorian year of 365.2425 days")

        // Speed
        add("metersPerSecond", .speed, UnitSpeed.metersPerSecond, "m/s", ["m/s", "mps", "meter per second", "meters per second"])
        add("kilometersPerHour", .speed, UnitSpeed.kilometersPerHour, "km/h", ["km/h", "kph", "kmh"])
        add("milesPerHour", .speed, UnitSpeed.milesPerHour, "mph", ["mph", "mi/h"])
        add("knots", .speed, UnitSpeed.knots, "kn", ["kn", "kt", "knot", "knots"])
        add("feetPerSecond", .speed, UnitSpeed(symbol: "ft/s", converter: UnitConverterLinear(coefficient: 0.3048)), "ft/s", ["ft/s", "fps", "feet per second", "foot per second"])

        // Acceleration (base: meters per second squared)
        add("metersPerSecondSquared", .acceleration, UnitAcceleration.metersPerSecondSquared, "m/s²", ["m/s2", "m/s^2", "meters per second squared", "meter per second squared"])
        add("feetPerSecondSquared", .acceleration, UnitAcceleration(symbol: "ft/s²", converter: UnitConverterLinear(coefficient: 0.3048)), "ft/s²", ["ft/s2", "ft/s^2", "feet per second squared", "foot per second squared"])
        add("standardGravity", .acceleration, UnitAcceleration(symbol: "g₀", converter: UnitConverterLinear(coefficient: 9.806_65)), "g₀", ["g", "g0", "standard gravity", "gravity"])

        // Pressure
        add("pascal", .pressure, UnitPressure.newtonsPerMetersSquared, "Pa", ["pa", "pascal", "pascals"])
        add("kilopascal", .pressure, UnitPressure.kilopascals, "kPa", ["kpa", "kilopascal", "kilopascals"])
        add("megapascal", .pressure, UnitPressure.megapascals, "MPa", ["mpa", "megapascal", "megapascals"])
        add("bar", .pressure, UnitPressure.bars, "bar", ["bar", "bars"])
        add("millibar", .pressure, UnitPressure.millibars, "mbar", ["mbar", "millibar", "millibars"])
        add("psi", .pressure, UnitPressure.poundsForcePerSquareInch, "psi", ["psi"])
        add("hectopascal", .pressure, UnitPressure.hectopascals, "hPa", ["hpa", "hectopascal", "hectopascals"])
        add("atmosphere", .pressure, UnitPressure(symbol: "atm", converter: UnitConverterLinear(coefficient: 101_325)), "atm", ["atm", "atmosphere", "atmospheres"])
        add("torr", .pressure, UnitPressure(symbol: "Torr", converter: UnitConverterLinear(coefficient: 133.322_368_421_052_63)), "Torr", ["torr"])
        add("millimeterMercury", .pressure, UnitPressure.millimetersOfMercury, "mmHg", ["mmhg", "millimeter of mercury", "millimeters of mercury"])

        // Energy
        add("joule", .energy, UnitEnergy.joules, "J", ["j", "joule", "joules"])
        add("kilojoule", .energy, UnitEnergy.kilojoules, "kJ", ["kj", "kilojoule", "kilojoules"])
        add("calorie", .energy, UnitEnergy.calories, "cal", ["cal", "calorie", "calories"])
        add("kilocalorie", .energy, UnitEnergy.kilocalories, "kcal", ["kcal", "kilocalorie", "kilocalories"])
        add("kilowattHour", .energy, UnitEnergy.kilowattHours, "kWh", ["kwh", "kilowatt hour", "kilowatt hours"])
        add("btu", .energy, UnitEnergy(symbol: "BTU", converter: UnitConverterLinear(coefficient: 1_055.055_852_62)), "BTU", ["btu", "btus", "british thermal unit", "british thermal units"])

        // Power
        add("watt", .power, UnitPower.watts, "W", ["w", "watt", "watts"])
        add("kilowatt", .power, UnitPower.kilowatts, "kW", ["kw", "kilowatt", "kilowatts"])
        add("horsepower", .power, UnitPower.horsepower, "hp", ["hp", "horsepower"])

        // Frequency
        add("hertz", .frequency, UnitFrequency.hertz, "Hz", ["hz", "hertz", "cycle per second", "cycles per second"])
        add("kilohertz", .frequency, UnitFrequency.kilohertz, "kHz", ["khz", "kilohertz"])
        add("megahertz", .frequency, UnitFrequency.megahertz, "MHz", ["mhz", "megahertz"])
        add("gigahertz", .frequency, UnitFrequency.gigahertz, "GHz", ["ghz", "gigahertz"])

        // Fuel efficiency
        add("litersPer100Kilometers", .fuelEfficiency, UnitFuelEfficiency.litersPer100Kilometers, "L/100km", ["l/100km", "liters per 100 kilometers", "liters per 100 km"])
        add("milesPerUSGallon", .fuelEfficiency, UnitFuelEfficiency.milesPerGallon, "US mpg", ["mpg", "us mpg", "miles per gallon", "miles per us gallon"], note: "Unqualified mpg uses US gallons")
        add(
            "milesPerImperialGallon",
            .fuelEfficiency,
            UnitFuelEfficiency.milesPerImperialGallon,
            "imp mpg",
            ["imperial mpg", "imp mpg", "miles per imperial gallon"]
        )

        // Data storage
        add("byte", .dataStorage, UnitInformationStorage.bytes, "B", ["b", "byte", "bytes"])
        add("kilobyte", .dataStorage, UnitInformationStorage.kilobytes, "KB", ["kb", "kilobyte", "kilobytes"])
        add("megabyte", .dataStorage, UnitInformationStorage.megabytes, "MB", ["mb", "megabyte", "megabytes"])
        add("gigabyte", .dataStorage, UnitInformationStorage.gigabytes, "GB", ["gb", "gigabyte", "gigabytes"])
        add("terabyte", .dataStorage, UnitInformationStorage.terabytes, "TB", ["tb", "terabyte", "terabytes"])
        add("bit", .dataStorage, UnitInformationStorage.bits, "bit", ["bit", "bits"])
        add("kibibyte", .dataStorage, UnitInformationStorage.kibibytes, "KiB", ["kib", "kibibyte", "kibibytes"])
        add("mebibyte", .dataStorage, UnitInformationStorage.mebibytes, "MiB", ["mib", "mebibyte", "mebibytes"])
        add("gibibyte", .dataStorage, UnitInformationStorage.gibibytes, "GiB", ["gib", "gibibyte", "gibibytes"])
        add("tebibyte", .dataStorage, UnitInformationStorage.tebibytes, "TiB", ["tib", "tebibyte", "tebibytes"])

        // Data transfer rate (base: bit per second)
        add("bitPerSecond", .dataTransferRate, linearUnit(symbol: "bit/s", coefficient: 1), "bit/s", ["bit/s", "bps", "bits per second"])
        add("kilobitPerSecond", .dataTransferRate, linearUnit(symbol: "kbit/s", coefficient: 1_000), "kbps", ["kbps", "kilobits per second"])
        add("megabitPerSecond", .dataTransferRate, linearUnit(symbol: "Mbit/s", coefficient: 1_000_000), "Mbps", ["mbps", "megabits per second"])
        add("gigabitPerSecond", .dataTransferRate, linearUnit(symbol: "Gbit/s", coefficient: 1_000_000_000), "Gbps", ["gbps", "gigabits per second"])
        add("megabytePerSecond", .dataTransferRate, linearUnit(symbol: "MB/s", coefficient: 8_000_000), "MB/s", ["mb/s", "megabytes per second"])

        // Angle
        add("degree", .angle, UnitAngle.degrees, "°", ["deg", "degree", "degrees"])
        add("radian", .angle, UnitAngle.radians, "rad", ["rad", "radian", "radians"])
        add("gradian", .angle, UnitAngle.gradians, "grad", ["grad", "gradian", "gradians", "gon"])
        add("turn", .angle, UnitAngle.revolutions, "turn", ["turn", "turns", "revolution", "revolutions"])

        // Mechanical compound dimensions use SI base units.
        add("newtonMeter", .torque, linearUnit(symbol: "N·m", coefficient: 1), "N·m", ["nm", "n m", "newton meter", "newton meters", "newton-meters"])
        add("poundFoot", .torque, linearUnit(symbol: "lb·ft", coefficient: 1.355_817_948_331_4), "lb·ft", ["lb-ft", "lb ft", "pound foot", "pound feet"])
        add("newton", .force, linearUnit(symbol: "N", coefficient: 1), "N", ["n", "newton", "newtons"])
        add("poundForce", .force, linearUnit(symbol: "lbf", coefficient: 4.448_221_615_260_5), "lbf", ["lbf", "pound force", "pounds force"])
        add("kilogramPerCubicMeter", .density, linearUnit(symbol: "kg/m³", coefficient: 1), "kg/m³", ["kg/m3", "kg/m^3", "kilograms per cubic meter"])
        add("gramPerCubicCentimeter", .density, linearUnit(symbol: "g/cm³", coefficient: 1_000), "g/cm³", ["g/cm3", "g/cm^3", "grams per cubic centimeter"])
        add("poundPerCubicFoot", .density, linearUnit(symbol: "lb/ft³", coefficient: 16.018_463_373_96), "lb/ft³", ["lb/ft3", "lb/ft^3", "pounds per cubic foot"])
        add("literPerSecond", .volumeFlowRate, linearUnit(symbol: "L/s", coefficient: 1), "L/s", ["l/s", "liters per second"])
        add("usGallonPerMinute", .volumeFlowRate, linearUnit(symbol: "US gal/min", coefficient: 0.063_090_196_4), "US gal/min", ["gpm", "gallons per minute", "us gallons per minute"])
        add("cubicFootPerMinute", .volumeFlowRate, linearUnit(symbol: "ft³/min", coefficient: 0.471_947_45), "ft³/min", ["cfm", "cubic feet per minute"])
        add("cubicMeterPerHour", .volumeFlowRate, linearUnit(symbol: "m³/h", coefficient: 0.277_777_777_777_8), "m³/h", ["m3/h", "m^3/h", "cubic meters per hour"])

        // Illuminance. Lumens are luminous flux and intentionally not convertible here.
        add("lux", .illuminance, UnitIlluminance.lux, "lx", ["lx", "lux"])
        add("footCandle", .illuminance, UnitIlluminance(symbol: "fc", converter: UnitConverterLinear(coefficient: 10.763_910_416_71)), "fc", ["fc", "foot candle", "foot candles"])

        // Electric
        add("coulomb", .electricCharge, UnitElectricCharge.coulombs, "C", ["coulomb", "coulombs"])
        add("ampere", .electricCurrent, UnitElectricCurrent.amperes, "A", ["a", "amp", "amps", "ampere", "amperes"])
        add("milliampere", .electricCurrent, UnitElectricCurrent.milliamperes, "mA", ["ma", "milliamp", "milliamps", "milliampere", "milliamperes"])
        add("volt", .electricPotential, UnitElectricPotentialDifference.volts, "V", ["v", "volt", "volts"])
        add("millivolt", .electricPotential, UnitElectricPotentialDifference.millivolts, "mV", ["mv", "millivolt", "millivolts"])
        add("kilovolt", .electricPotential, UnitElectricPotentialDifference.kilovolts, "kV", ["kv", "kilovolt", "kilovolts"])
        add("ohm", .resistance, UnitElectricResistance.ohms, "Ω", ["ohm", "ohms"])
        add("kiloohm", .resistance, UnitElectricResistance.kiloohms, "kΩ", ["kohm", "kiloohm", "kiloohms"])
        add("megaohm", .resistance, UnitElectricResistance.megaohms, "MΩ", ["mohm", "megaohm", "megaohms"])

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

    /// Immutable registry snapshot used by exhaustive validation.
    var registeredDefinitions: [UnitDefinition] { definitions }

    func containsUnitToken(in text: String) -> Bool {
        let lowered = text.lowercased()
        for key in aliasMap.keys {
            let escaped = NSRegularExpression.escapedPattern(for: key)
            let pattern = "(?<![\\p{L}\\p{N}])\(escaped)(?![\\p{L}\\p{N}])"
            if lowered.range(of: pattern, options: .regularExpression) != nil {
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
            if filtered.isEmpty {
                throw CalculatorError.incompatibleUnits
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

    /// Infers a complete conversion from a bare or partially completed quantity.
    func inferredConversion(for input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let match = captures(#"^([-+]?\d+(?:[.,]\d+)?)\s*([^\d].*)$"#, in: trimmed) else { return nil }
        let number = match[0]
        let remainder = match[1].lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if ["m", "oz", "gal", "ton", "c"].contains(remainder) { return nil }

        let aliases = aliasMap.keys.sorted { $0.count > $1.count }
        let exactSourceAlias = aliases.first { remainder == $0 || remainder.hasPrefix($0 + " ") }
        let sourceAlias = exactSourceAlias ?? fuzzyAlias(for: remainder)
        guard let sourceAlias,
              let sources = aliasMap[sourceAlias] else { return nil }
        let uniqueSources = Dictionary(grouping: sources, by: \.id).compactMap(\.value.first)
        guard uniqueSources.count == 1,
              let source = uniqueSources.first,
              let defaultDestination = preferredDestination(for: source) else { return nil }

        let typedSource = sourceAlias
        let defaultCompletion = "\(number) \(typedSource) in \(defaultDestination.symbol)"
        if defaultCompletion.lowercased().hasPrefix(trimmed.lowercased()) { return defaultCompletion }

        guard let connector = remainder.range(of: #"\s+(?:in|to|into)\s*"#, options: .regularExpression) else {
            return exactSourceAlias == nil || remainder == sourceAlias ? defaultCompletion : nil
        }
        let typedSourceOnly = remainder[..<connector.lowerBound].trimmingCharacters(in: .whitespaces)
        let targetFragment = remainder[connector.upperBound...].trimmingCharacters(in: .whitespaces)
        if targetFragment.isEmpty == false,
           (try? resolve(targetFragment, preferredDimension: source.dimension)) != nil {
            return nil
        }
        let destinationAliases = definitions
            .filter { $0.dimension == source.dimension && $0.id != source.id }
            .flatMap(\.aliases)
        let targetAlias = destinationAliases
            .filter { $0.hasPrefix(targetFragment) }
            .sorted { $0.count < $1.count }
            .first
            ?? StringDistance.uniqueBestMatch(for: targetFragment, in: destinationAliases, minimumSimilarity: 0.76)
        guard let targetAlias,
              let target = try? resolve(targetAlias, preferredDimension: source.dimension) else {
            return targetFragment.isEmpty ? defaultCompletion : nil
        }
        return "\(number) \(typedSourceOnly) in \(target.symbol)"
    }

    private func preferredDestination(for source: UnitDefinition) -> UnitDefinition? {
        let destinationID: String
        switch source.dimension {
        case .length:
            destinationID = ["mile", "yard", "foot", "inch", "nauticalMile"].contains(source.id) ? "meter" : "foot"
        case .area:
            destinationID = ["squareFoot", "squareInch", "squareYard", "squareMile", "acre"].contains(source.id) ? "squareMeter" : "squareFoot"
        case .volume:
            destinationID = source.id == "liter" || source.id == "milliliter" || source.id.hasPrefix("cubic") ? "usGallon" : "liter"
        case .mass:
            destinationID = ["pound", "ounce", "stone", "shortTon", "longTon"].contains(source.id) ? "kilogram" : "pound"
        case .temperature:
            destinationID = source.id == "fahrenheit" ? "celsius" : "fahrenheit"
        case .duration:
            destinationID = ["second", "minute"].contains(source.id) ? "hour" : "minute"
        case .speed:
            destinationID = ["milesPerHour", "feetPerSecond", "knots"].contains(source.id) ? "kilometersPerHour" : "milesPerHour"
        case .acceleration: destinationID = source.id == "feetPerSecondSquared" ? "metersPerSecondSquared" : "feetPerSecondSquared"
        case .pressure: destinationID = source.id == "psi" ? "bar" : "psi"
        case .energy: destinationID = source.id == "calorie" || source.id == "kilocalorie" ? "kilojoule" : "calorie"
        case .power: destinationID = source.id == "horsepower" ? "watt" : "horsepower"
        case .frequency: destinationID = source.id == "hertz" ? "kilohertz" : "hertz"
        case .fuelEfficiency: destinationID = source.id == "litersPer100Kilometers" ? "milesPerUSGallon" : "litersPer100Kilometers"
        case .dataStorage: destinationID = source.id == "byte" ? "megabyte" : "byte"
        case .dataTransferRate: destinationID = source.id == "megabytePerSecond" ? "megabitPerSecond" : "megabytePerSecond"
        case .angle: destinationID = source.id == "degree" ? "radian" : "degree"
        case .torque: destinationID = source.id == "poundFoot" ? "newtonMeter" : "poundFoot"
        case .force: destinationID = source.id == "poundForce" ? "newton" : "poundForce"
        case .density: destinationID = source.id == "kilogramPerCubicMeter" ? "poundPerCubicFoot" : "kilogramPerCubicMeter"
        case .volumeFlowRate: destinationID = source.id == "literPerSecond" ? "usGallonPerMinute" : "literPerSecond"
        case .electricCharge: return nil
        case .electricCurrent: destinationID = source.id == "ampere" ? "milliampere" : "ampere"
        case .electricPotential: destinationID = source.id == "volt" ? "millivolt" : "volt"
        case .resistance: destinationID = source.id == "ohm" ? "kiloohm" : "ohm"
        case .illuminance: destinationID = source.id == "lux" ? "footCandle" : "lux"
        }
        return definitions.first { $0.id == destinationID }
    }

    private func fuzzyAlias(for input: String) -> String? {
        let scored = aliasMap.keys.map { alias in
            (alias: alias, distance: StringDistance.damerauLevenshtein(input, alias))
        }
        guard let minimum = scored.map(\.distance).min() else { return nil }
        let nearest = scored.filter { $0.distance == minimum }
        let definitionIDs = Set(nearest.flatMap { aliasMap[$0.alias] ?? [] }.map(\.id))
        guard definitionIDs.count == 1,
              let alias = nearest.sorted(by: { $0.alias.count > $1.alias.count }).first?.alias,
              StringDistance.similarity(input, alias) >= 0.78 else { return nil }
        return alias
    }

    private func captures(_ pattern: String, in text: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text)) else { return nil }
        return (1..<match.numberOfRanges).compactMap { index in
            guard let range = Range(match.range(at: index), in: text) else { return nil }
            return String(text[range])
        }
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

        if let relationship = try evaluateElectricalRelationship(lowered, locale: locale) {
            return relationship
        }
        if let named = try evaluateNamedConstant(lowered, locale: locale) {
            return named
        }

        // Compound duration: "2 hours 30 minutes in minutes"
        if let compound = try evaluateCompoundDuration(lowered, locale: locale) {
            return compound
        }
        if let compound = try evaluateCompoundLength(lowered, locale: locale) {
            return compound
        }

        guard let parsed = parseConversion(lowered) else {
            throw CalculatorError.unsupportedOperation
        }

        let resolved: (from: UnitDefinition, to: UnitDefinition)
        do {
            let from = try CalculatorUnitRegistry.shared.resolve(parsed.fromUnit)
            let to = try CalculatorUnitRegistry.shared.resolve(parsed.toUnit, preferredDimension: from.dimension)
            resolved = (from, to)
        } catch CalculatorError.ambiguousUnit {
            // A target such as `m/s2` can disambiguate a source such as `g`
            // (gram versus standard gravity) without silently guessing.
            let to = try CalculatorUnitRegistry.shared.resolve(parsed.toUnit)
            let from = try CalculatorUnitRegistry.shared.resolve(parsed.fromUnit, preferredDimension: to.dimension)
            resolved = (from, to)
        }
        let fromDef = resolved.from
        let toDef = resolved.to
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
        for note in [fromDef.note, toDef.note].compactMap({ $0 }) where !metadata.notes.contains(note) {
            metadata.notes.append(note)
        }

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
        let pattern = #"^([-+]?(?:\d+(?:[.,]\d+)?|pi|tau))\s*(.+?)\s+(?:in|to|into|as)\s+(.+)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              match.numberOfRanges == 4,
              let valueRange = Range(match.range(at: 1), in: text),
              let fromRange = Range(match.range(at: 2), in: text),
              let toRange = Range(match.range(at: 3), in: text)
        else { return parseShortConversion(text) }
        let valueText = String(text[valueRange]).replacingOccurrences(of: ",", with: ".")
        let value: Double?
        switch valueText {
        case "pi", "+pi": value = .pi
        case "-pi": value = -.pi
        case "tau", "+tau": value = 2 * .pi
        case "-tau": value = -2 * .pi
        default: value = Double(valueText)
        }
        guard let value else { return nil }
        return ParsedConversion(
            value: value,
            fromUnit: String(text[fromRange]).trimmingCharacters(in: .whitespacesAndNewlines),
            toUnit: String(text[toRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    private static func parseShortConversion(_ text: String) -> ParsedConversion? {
        let pattern = #"^([-+]?\d+(?:[.,]\d+)?)\s*([^\s]+)\s+([^\s]+)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text)),
              let valueRange = Range(match.range(at: 1), in: text),
              let fromRange = Range(match.range(at: 2), in: text),
              let toRange = Range(match.range(at: 3), in: text),
              let value = Double(String(text[valueRange]).replacingOccurrences(of: ",", with: "."))
        else { return nil }
        return ParsedConversion(
            value: value,
            fromUnit: String(text[fromRange]),
            toUnit: String(text[toRange])
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

    private static func evaluateCompoundLength(_ text: String, locale: Locale) throws -> ConversionResult? {
        let pattern = #"^([-+]?\d+(?:\.\d+)?)\s*(?:ft|feet|foot)\s*(\d+(?:\.\d+)?)\s*(?:in|inches|inch)\s+(?:in|to|into)\s+(.+)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              let feetRange = Range(match.range(at: 1), in: text),
              let inchesRange = Range(match.range(at: 2), in: text),
              let toRange = Range(match.range(at: 3), in: text),
              let feet = Double(text[feetRange]),
              let inches = Double(text[inchesRange])
        else { return nil }

        let totalInches = feet * 12 + inches
        let fromDef = try CalculatorUnitRegistry.shared.resolve("inch")
        let toUnitName = String(text[toRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        let toDef = try CalculatorUnitRegistry.shared.resolve(toUnitName, preferredDimension: .length)
        let converted = Measurement(value: totalInches, unit: fromDef.unit).converted(to: toDef.unit)
        let value = CalculatorMeasurementValue(
            value: converted.value,
            unitIdentifier: toDef.id,
            unitSymbol: toDef.symbol,
            dimension: .length
        )
        return ConversionResult(
            value: value,
            metadata: CalculatorResultMetadata(fromUnit: "foot+inch", toUnit: toDef.id),
            displayExpression: "\(formatNumber(feet, locale: locale)) ft \(formatNumber(inches, locale: locale)) in → \(toDef.symbol)"
        )
    }

    private static func evaluateElectricalRelationship(_ text: String, locale: Locale) throws -> ConversionResult? {
        let number = #"([-+]?\d+(?:\.\d+)?)"#
        let patterns: [(String, String, String, (Double, Double) throws -> Double)] = [
            (#"^watts\s+if\s+volts\s+are\s+"# + number + #"\s+and\s+amps\s+are\s+"# + number + #"$"#, "watt", "P = V × I", { $0 * $1 }),
            (#"^"# + number + #"\s+volts\s*\*\s*"# + number + #"\s+amps$"#, "watt", "P = V × I", { $0 * $1 }),
            (#"^amps\s+for\s+"# + number + #"\s+watts\s+at\s+"# + number + #"\s+volts$"#, "ampere", "I = P ÷ V", {
                guard $1 != 0 else { throw CalculatorError.divisionByZero }
                return $0 / $1
            }),
            (#"^volts\s+for\s+"# + number + #"\s+watts\s+at\s+"# + number + #"\s+amps$"#, "volt", "V = P ÷ I", {
                guard $1 != 0 else { throw CalculatorError.divisionByZero }
                return $0 / $1
            }),
        ]

        for (pattern, outputUnit, formula, operation) in patterns {
            guard let values = captureTwoNumbers(pattern, in: text) else { continue }
            let result = try operation(values.0, values.1)
            let definition = try CalculatorUnitRegistry.shared.resolve(outputUnit)
            let measurement = CalculatorMeasurementValue(
                value: result,
                unitIdentifier: definition.id,
                unitSymbol: definition.symbol,
                dimension: definition.dimension
            )
            var metadata = CalculatorResultMetadata(toUnit: definition.id)
            metadata.notes.append(formula)
            return ConversionResult(
                value: measurement,
                metadata: metadata,
                displayExpression: "\(text) → \(formatNumber(result, locale: locale)) \(definition.symbol)"
            )
        }
        return nil
    }

    private static func evaluateNamedConstant(_ text: String, locale: Locale) throws -> ConversionResult? {
        let prefix = "speed of sound "
        guard text.hasPrefix(prefix) else { return nil }
        let remainder = String(text.dropFirst(prefix.count))
        let target: String
        if remainder.hasPrefix("in ") {
            target = String(remainder.dropFirst(3))
        } else if remainder.hasPrefix("to ") {
            target = String(remainder.dropFirst(3))
        } else {
            return nil
        }

        let source = try CalculatorUnitRegistry.shared.resolve("meters per second")
        let destination = try CalculatorUnitRegistry.shared.resolve(target, preferredDimension: .speed)
        let converted = Measurement(value: 343, unit: source.unit).converted(to: destination.unit)
        let value = CalculatorMeasurementValue(
            value: converted.value,
            unitIdentifier: destination.id,
            unitSymbol: destination.symbol,
            dimension: .speed
        )
        var metadata = CalculatorResultMetadata(fromUnit: source.id, toUnit: destination.id)
        metadata.notes.append("Assumes 343 m/s for dry air at 20 °C")
        return ConversionResult(
            value: value,
            metadata: metadata,
            displayExpression: "speed of sound (343 m/s) → \(destination.symbol)"
        )
    }

    private static func captureTwoNumbers(_ pattern: String, in text: String) -> (Double, Double)? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              match.numberOfRanges == 3,
              let firstRange = Range(match.range(at: 1), in: text),
              let secondRange = Range(match.range(at: 2), in: text),
              let first = Double(text[firstRange]),
              let second = Double(text[secondRange])
        else { return nil }
        return (first, second)
    }

    private static func formatNumber(_ value: Double, locale: Locale) -> String {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 6
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }
}
