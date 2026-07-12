import Foundation

/// Deterministic geometry, health, business, and developer-oriented calculations.
enum CalculatorUtilities {
    struct Result: Sendable, Equatable {
        let kind: CalculatorResultKind
        let primaryValue: CalculatorValue
        let formattedPrimaryValue: String?
        let metadata: CalculatorResultMetadata
        let displayExpression: String
    }

    static func evaluate(_ input: String, context: CalculatorEvaluationContext) throws -> Result {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowered = text.lowercased()
        if let result = assignment(text, lowered: lowered) { return result }
        if let result = advanced(text, lowered: lowered) { return result }
        if let result = geometry(lowered) { return result }
        if let result = health(lowered) { return result }
        if let result = business(lowered, context: context) { return result }
        if let result = try developer(text, lowered: lowered) { return result }
        throw CalculatorError.unsupportedOperation
    }

    private static func assignment(_ original: String, lowered: String) -> Result? {
        let name: String
        let rawValue: String
        if let g = captures(#"^([a-z][a-z0-9_ ]*)\s*=\s*([\d.]+)(%)?$"#, lowered) {
            name = g[0].trimmingCharacters(in: .whitespaces)
            rawValue = g[1] + g[2]
        } else if let g = captures(#"^save\s+([\d.]+)(%)?\s+as\s+([a-z][a-z0-9_ ]*)$"#, lowered) {
            name = g[2].trimmingCharacters(in: .whitespaces)
            rawValue = g[0] + g[1]
        } else if let g = captures(#"^set\s+([a-z][a-z0-9_ ]*)\s+to\s+([\d.]+)(%)?$"#, lowered) {
            name = g[0].trimmingCharacters(in: .whitespaces)
            rawValue = g[1] + g[2]
        } else {
            return nil
        }
        let isPercentage = rawValue.hasSuffix("%")
        let numberText = isPercentage ? String(rawValue.dropLast()) : rawValue
        guard var value = number(numberText) else { return nil }
        if isPercentage { value /= 100 }
        let variable = CalculatorVariable(value: value, isPercentage: isPercentage)
        let rendered = isPercentage ? NSDecimalNumber(decimal: value * 100).stringValue + "%" : NSDecimalNumber(decimal: value).stringValue
        return Result(
            kind: .arithmetic,
            primaryValue: .decimal(value),
            formattedPrimaryValue: "\(name) = \(rendered)",
            metadata: .init(assignedVariableName: name, assignedVariable: variable, notes: ["Stored only in the host-defined calculator session."]),
            displayExpression: original
        )
    }

    private static func geometry(_ text: String) -> Result? {
        if let g = captures(#"^area of a rectangle\s+([\d.]+)\s+by\s+([\d.]+)$"#, text), let a = number(g[0]), let b = number(g[1]) { return numeric(a * b, text, kind: .geometry, suffix: " square units") }
        if let g = captures(#"^perimeter of a\s+([\d.]+)\s+by\s+([\d.]+)\s+rectangle$"#, text), let a = number(g[0]), let b = number(g[1]) { return numeric(2 * (a + b), text, kind: .geometry, suffix: " units") }
        if let g = captures(#"^area of a square with side\s+([\d.]+)$"#, text), let side = number(g[0]) { return numeric(side * side, text, kind: .geometry, suffix: " square units") }
        if let g = captures(#"^diagonal of a\s+([\d.]+)\s+by\s+([\d.]+)\s+rectangle$"#, text), let a = double(g[0]), let b = double(g[1]) { return numericDecimal(sqrt(a * a + b * b), text, kind: .geometry, suffix: " units") }
        if let g = captures(#"^area of a circle radius\s+([\d.]+)$"#, text), let radius = double(g[0]) { return numericDecimal(.pi * radius * radius, text, kind: .geometry, suffix: " square units") }
        if let g = captures(#"^circumference of a circle diameter\s+([\d.]+)$"#, text), let diameter = double(g[0]) { return numericDecimal(.pi * diameter, text, kind: .geometry, suffix: " units") }
        if let g = captures(#"^circle diameter from circumference\s+([\d.]+)$"#, text), let circumference = double(g[0]) { return numericDecimal(circumference / .pi, text, kind: .geometry, suffix: " units") }
        if let g = captures(#"^area of a triangle base\s+([\d.]+)\s+height\s+([\d.]+)$"#, text), let base = number(g[0]), let height = number(g[1]) { return numeric(base * height / 2, text, kind: .geometry, suffix: " square units") }
        if let g = captures(#"^hypotenuse with sides\s+([\d.]+)\s+and\s+([\d.]+)$"#, text), let a = double(g[0]), let b = double(g[1]) { return numericDecimal(hypot(a, b), text, kind: .geometry, suffix: " units") }
        if let g = captures(#"^third side of a right triangle with hypotenuse\s+([\d.]+)\s+and side\s+([\d.]+)$"#, text), let hypotenuse = double(g[0]), let side = double(g[1]), hypotenuse >= side { return numericDecimal(sqrt(hypotenuse * hypotenuse - side * side), text, kind: .geometry, suffix: " units") }
        if let g = captures(#"^volume of a cube side\s+([\d.]+)$"#, text), let side = number(g[0]) { return numeric(side * side * side, text, kind: .geometry, suffix: " cubic units") }
        if let g = captures(#"^volume of a box\s+([\d.]+)\s+by\s+([\d.]+)\s+by\s+([\d.]+)$"#, text), let a = number(g[0]), let b = number(g[1]), let c = number(g[2]) { return numeric(a * b * c, text, kind: .geometry, suffix: " cubic units") }
        if let g = captures(#"^surface area of a sphere radius\s+([\d.]+)$"#, text), let radius = double(g[0]) { return numericDecimal(4 * .pi * radius * radius, text, kind: .geometry, suffix: " square units") }
        if let g = captures(#"^volume of a cylinder radius\s+([\d.]+)\s+height\s+([\d.]+)$"#, text), let radius = double(g[0]), let height = double(g[1]) { return numericDecimal(.pi * radius * radius * height, text, kind: .geometry, suffix: " cubic units") }
        if let g = captures(#"^volume of a cone radius\s+([\d.]+)\s+height\s+([\d.]+)$"#, text), let radius = double(g[0]), let height = double(g[1]) { return numericDecimal(.pi * radius * radius * height / 3, text, kind: .geometry, suffix: " cubic units") }
        return nil
    }

    private static func health(_ text: String) -> Result? {
        if let g = captures(#"^bmi for\s+([\d.]+)\s+lb\s+and\s+(\d+)\s+ft\s+(\d+)\s+in$"#, text), let pounds = double(g[0]), let feet = double(g[1]), let inches = double(g[2]) {
            let kilograms = pounds * 0.453_592_37, meters = (feet * 12 + inches) * 0.0254
            return numericDecimal(kilograms / (meters * meters), text, kind: .health, suffix: " BMI", notes: ["Informational only; BMI is not a diagnosis."])
        }
        if let g = captures(#"^bmi for\s+([\d.]+)\s+kg\s+and\s+([\d.]+)\s+cm$"#, text), let kilograms = double(g[0]), let centimeters = double(g[1]) {
            let meters = centimeters / 100
            return numericDecimal(kilograms / (meters * meters), text, kind: .health, suffix: " BMI", notes: ["Informational only; BMI is not a diagnosis."])
        }
        if let g = captures(#"^running pace for\s+([\d.]+)\s+km\s+in\s+([\d.]+)\s+minutes$"#, text), let distance = double(g[0]), let minutes = double(g[1]), distance > 0 { return pace(minutes * 60 / distance, text, suffix: "/km") }
        if let g = captures(#"^mile pace for\s+([\d.]+)\s+km\s+in\s+([\d.]+)\s+minutes$"#, text), let kilometers = double(g[0]), let minutes = double(g[1]), kilometers > 0 { return pace(minutes * 60 / (kilometers / 1.609_344), text, suffix: "/mi") }
        if let g = captures(#"^time for a marathon at\s+([\d.]+)-minute mile pace$"#, text), let paceMinutes = double(g[0]) { return duration(paceMinutes * 60 * 26.218_75, text, kind: .health) }
        if let g = captures(#"^distance at\s+([\d.]+)\s+mph\s+for\s+([\d.]+)\s+minutes$"#, text), let speed = number(g[0]), let minutes = number(g[1]) { return numeric(speed * minutes / 60, text, kind: .health, suffix: " mi") }
        if let g = captures(#"^time to travel\s+([\d.]+)\s+miles?\s+at\s+([\d.]+)\s+mph$"#, text), let distance = double(g[0]), let speed = double(g[1]), speed > 0 { return duration(distance / speed * 3_600, text, kind: .health) }
        if let g = captures(#"^speed for\s+([\d.]+)\s+km\s+in\s+([\d.]+)\s+hours?$"#, text), let distance = number(g[0]), let hours = number(g[1]), hours != 0 { return numeric(distance / hours, text, kind: .health, suffix: " km/h") }
        if let g = captures(#"^(\d+(?:\.\d+)?)\s+calories per day for\s+(\d+)\s+days$"#, text), let daily = number(g[0]), let days = number(g[1]) { return numeric(daily * days, text, kind: .health, suffix: " calories", notes: ["Arithmetic only; no medical or weight-change claim is implied."]) }
        if let g = captures(#"^(\d+(?:\.\d+)?)\s+calorie surplus per day for\s+(\d+)\s+days$"#, text), let daily = number(g[0]), let days = number(g[1]) { return numeric(daily * days, text, kind: .health, suffix: " calorie surplus", notes: ["Arithmetic only; no weight-change guarantee is implied."]) }
        return nil
    }

    private static func business(_ text: String, context: CalculatorEvaluationContext) -> Result? {
        if let g = captures(#"^hours from\s+(.+?)\s+to\s+(.+?)\s+with a\s+(\d+)-minute lunch$"#, text), let start = clock(g[0]), let end = clock(g[1]), let lunch = Int(g[2]) {
            var elapsed = end - start; if elapsed <= 0 { elapsed += 86_400 }
            return numericDecimal(Double(elapsed - lunch * 60) / 3_600, text, kind: .business, suffix: " h")
        }
        if let g = captures(#"^weekly hours for\s+([\d.]+)\s+hours a day\s+([\d.]+)\s+days a week$"#, text), let hours = number(g[0]), let days = number(g[1]) { return numeric(hours * days, text, kind: .business, suffix: " h/week") }
        if let g = captures(#"^monthly hours at\s+([\d.]+)\s+hours per week$"#, text), let weekly = number(g[0]) { return numeric(weekly * Decimal(52) / 12, text, kind: .business, suffix: " h/month", notes: ["Uses 52 weeks ÷ 12 months."]) }
        if let g = captures(#"^subtotal\s+(.+)$"#, text), let values = decimalList(g[0], separator: "+") { return numeric(values.reduce(0, +), text, kind: .business, suffix: "") }
        if let g = captures(#"^add\s+([\d.]+)%\s+tax to\s+([\d.]+)$"#, text), let rate = number(g[0]), let base = number(g[1]) { return numeric(base * (1 + rate / 100), text, kind: .business, suffix: "", notes: ["Includes tax."]) }
        if let g = captures(#"^([\d.]+)\s+plus\s+([\d.]+)%\s+tax and\s+([\d.]+)%\s+tip$"#, text), let base = number(g[0]), let tax = number(g[1]), let tip = number(g[2]) { return numeric(base * (1 + tax / 100 + tip / 100), text, kind: .business, suffix: "", notes: ["Tax and tip are each calculated from the original base."]) }
        if let g = captures(#"^([\d.]+)%\s+commission on\s+([\d.]+)$"#, text), let rate = number(g[0]), let sales = number(g[1]) { return numeric(sales * rate / 100, text, kind: .business, suffix: "") }
        if let g = captures(#"^commission on\s+([\d.]+)\s+at\s+([\d.]+)%\s+plus\s+([\d.]+)%\s+over\s+([\d.]+)$"#, text), let sales = number(g[0]), let baseRate = number(g[1]), let tierRate = number(g[2]), let threshold = number(g[3]) { return numeric(sales * baseRate / 100 + max(0, sales - threshold) * tierRate / 100, text, kind: .business, suffix: "", notes: ["The additional tier applies only above the stated threshold."]) }
        if let g = captures(#"^(\d+) conversions from\s+(\d+) visits$"#, text), let conversions = number(g[0]), let visits = number(g[1]), visits != 0 { return numeric(conversions / visits * 100, text, kind: .business, suffix: "%") }
        if let g = captures(#"^conversion rate for\s+(\d+) sales from\s+(\d+) leads$"#, text), let sales = number(g[0]), let leads = number(g[1]), leads != 0 { return numeric(sales / leads * 100, text, kind: .business, suffix: "%") }
        if let g = captures(#"^increase conversion rate from\s+([\d.]+)%\s+to\s+([\d.]+)%$"#, text), let old = number(g[0]), let new = number(g[1]), old != 0 { return numeric((new - old) / old * 100, text, kind: .business, suffix: "%", notes: ["Relative increase; the absolute change is \(new - old) percentage point(s)."]) }
        if let g = captures(#"^growth from\s+([\d.]+)\s+to\s+([\d.]+)$"#, text), let old = number(g[0]), let new = number(g[1]), old != 0 { return numeric((new - old) / old * 100, text, kind: .business, suffix: "%") }
        if let g = captures(#"^monthly growth rate from\s+([\d.]+)\s+to\s+([\d.]+)\s+over\s+(\d+)\s+months$"#, text), let old = double(g[0]), let new = double(g[1]), let months = double(g[2]), old > 0, new >= 0, months > 0 { return numericDecimal((pow(new / old, 1 / months) - 1) * 100, text, kind: .business, suffix: "%") }
        if let g = captures(#"^cagr from\s+([\d.]+)\s+to\s+([\d.]+)\s+in\s+(\d+)\s+years$"#, text), let old = double(g[0]), let new = double(g[1]), let years = double(g[2]), old > 0, new >= 0, years > 0 { return numericDecimal((pow(new / old, 1 / years) - 1) * 100, text, kind: .business, suffix: "%") }
        if let g = captures(#"^cpa if spend is\s+([\d.]+)\s+and customers are\s+([\d.]+)$"#, text), let spend = number(g[0]), let customers = number(g[1]), customers != 0 { return numeric(spend / customers, text, kind: .business, suffix: " per acquisition") }
        if let g = captures(#"^roas if revenue is\s+([\d.]+)\s+and ad spend is\s+([\d.]+)$"#, text), let revenue = number(g[0]), let spend = number(g[1]), spend != 0 { return numeric(revenue / spend, text, kind: .business, suffix: "×") }
        if let g = captures(#"^roi if investment is\s+([\d.]+)\s+and profit is\s+([\d.]+)$"#, text), let investment = number(g[0]), let profit = number(g[1]), investment != 0 { return numeric(profit / investment * 100, text, kind: .business, suffix: "%") }
        _ = context
        return nil
    }

    private static func developer(_ original: String, lowered: String) throws -> Result? {
        if let g = captures(#"^(\d+) in binary$"#, lowered), let value = Int(g[0]) { return text(String(value, radix: 2), original) }
        if let g = captures(#"^([01]+) binary to decimal$"#, lowered), let value = Int(g[0], radix: 2) { return numeric(Decimal(value), original, kind: .developerUtility, suffix: "") }
        if let g = captures(#"^([0-9a-f]+) hex to decimal$"#, lowered), let value = Int(g[0], radix: 16) { return numeric(Decimal(value), original, kind: .developerUtility, suffix: "") }
        if let g = captures(#"^(\d+) decimal to hexadecimal$"#, lowered), let value = Int(g[0]) { return text(String(value, radix: 16).uppercased(), original) }
        if let g = captures(#"^0x([0-9a-f]+)\s*\+\s*0x([0-9a-f]+)$"#, lowered), let a = Int(g[0], radix: 16), let b = Int(g[1], radix: 16) { return text("0x" + String(a + b, radix: 16).uppercased(), original, notes: ["Hexadecimal result; decimal \(a + b)."]) }
        if let g = captures(#"^0b([01]+) in (hex|octal|decimal)$"#, lowered), let value = Int(g[0], radix: 2) { return g[1] == "decimal" ? numeric(Decimal(value), original, kind: .developerUtility, suffix: "") : text(g[1] == "hex" ? String(value, radix: 16).uppercased() : String(value, radix: 8), original) }
        if let result = bitwise(lowered, original: original) { return result }
        if let g = captures(#"^ascii code for\s+(.{1})$"#, original), let scalar = g[0].unicodeScalars.first, scalar.value <= 127 { return numeric(Decimal(Int(scalar.value)), original, kind: .developerUtility, suffix: "") }
        if let g = captures(#"^character for ascii\s+(\d+)$"#, lowered), let value = UInt8(g[0]) { return text(String(UnicodeScalar(value)), original) }
        if let g = captures(#"^unicode for\s+(.{1})$"#, original), let scalar = g[0].unicodeScalars.first { return text(String(format: "U+%04X", scalar.value), original) }
        if let g = captures(#"^u\+([0-9a-f]{1,8}) as character$"#, lowered), let value = UInt32(g[0], radix: 16), let scalar = UnicodeScalar(value) { return text(String(scalar), original) }
        if let result = color(lowered, original: original) { return result }
        if let result = transfer(lowered, original: original) { return result }
        if lowered.hasPrefix("url encode ") { return text(String(original.dropFirst("URL encode ".count)).addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "", original) }
        if lowered.hasPrefix("decode ") { return text(String(original.dropFirst("decode ".count)).removingPercentEncoding ?? "", original) }
        if lowered.hasPrefix("base64 encode ") { return text(Data(String(original.dropFirst("base64 encode ".count)).utf8).base64EncodedString(), original) }
        if lowered.hasPrefix("base64 decode ") {
            guard let data = Data(base64Encoded: String(original.dropFirst("base64 decode ".count))), let decoded = String(data: data, encoding: .utf8) else { throw CalculatorError.invalidDomain(function: "Base64 decode") }
            return text(decoded, original)
        }
        return nil
    }

    private static func bitwise(_ lowered: String, original: String) -> Result? {
        if let g = captures(#"^not\s+(\d+)$"#, lowered), let value = Int(g[0]) { return numeric(Decimal(~value), original, kind: .developerUtility, suffix: "") }
        guard let g = captures(#"^(\d+)\s*(and|&|or|\||xor|\^|<<|>>)\s*(\d+)(?:\s+bitwise)?$"#, lowered), let a = Int(g[0]), let b = Int(g[2]) else { return nil }
        let value: Int
        switch g[1] { case "and", "&": value = a & b; case "or", "|": value = a | b; case "xor", "^": value = a ^ b; case "<<": value = a << b; default: value = a >> b }
        return numeric(Decimal(value), original, kind: .developerUtility, suffix: "")
    }

    private static func color(_ lowered: String, original: String) -> Result? {
        if let g = captures(#"^#([0-9a-f]{6}) to rgb$"#, lowered), let value = Int(g[0], radix: 16) { return text("rgb(\((value >> 16) & 255), \((value >> 8) & 255), \(value & 255))", original) }
        if let g = captures(#"^rgb\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*\) to hex$"#, lowered), let r = Int(g[0]), let green = Int(g[1]), let b = Int(g[2]), [r, green, b].allSatisfy({ (0...255).contains($0) }) { return text(String(format: "#%02X%02X%02X", r, green, b), original) }
        if let g = captures(#"^hsl\(\s*([\d.]+)\s*,\s*([\d.]+)%\s*,\s*([\d.]+)%\s*\) to rgb$"#, lowered), let h = double(g[0]), let s = double(g[1]), let l = double(g[2]) {
            let rgb = hslToRGB(h: h, s: s / 100, l: l / 100)
            return text("rgb(\(rgb.0), \(rgb.1), \(rgb.2))", original)
        }
        return nil
    }

    private static func hslToRGB(h: Double, s: Double, l: Double) -> (Int, Int, Int) {
        let chroma = (1 - abs(2 * l - 1)) * s, segment = (h.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360) / 60
        let x = chroma * (1 - abs(segment.truncatingRemainder(dividingBy: 2) - 1)); let base: (Double, Double, Double)
        switch segment { case 0..<1: base = (chroma, x, 0); case 1..<2: base = (x, chroma, 0); case 2..<3: base = (0, chroma, x); case 3..<4: base = (0, x, chroma); case 4..<5: base = (x, 0, chroma); default: base = (chroma, 0, x) }
        let m = l - chroma / 2
        return (Int(((base.0 + m) * 255).rounded()), Int(((base.1 + m) * 255).rounded()), Int(((base.2 + m) * 255).rounded()))
    }

    private static func transfer(_ lowered: String, original: String) -> Result? {
        guard let g = captures(#"^(?:download time for|upload|how long to transfer)\s+([\d.]+)\s+(gb|tb)\s+at\s+([\d.]+)\s+(mbps|gbps)$"#, lowered), let size = double(g[0]), let rate = double(g[2]), rate > 0 else { return nil }
        let bytes = size * (g[1] == "tb" ? 1_000_000_000_000 : 1_000_000_000), bitsPerSecond = rate * (g[3] == "gbps" ? 1_000_000_000 : 1_000_000)
        return duration(bytes * 8 / bitsPerSecond, original, kind: .developerUtility, notes: ["Uses decimal SI file sizes and line rate; protocol overhead is excluded."])
    }

    // MARK: - Helpers

    private static func number(_ text: String) -> Decimal? { Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")) }
    private static func double(_ text: String) -> Double? { Double(text) }
    private static func decimalList(_ text: String, separator: Character) -> [Decimal]? { let values = text.split(separator: separator).map { number(String($0).trimmingCharacters(in: .whitespaces)) }; return values.allSatisfy { $0 != nil } ? values.compactMap { $0 } : nil }

    private static func numeric(_ value: Decimal, _ expression: String, kind: CalculatorResultKind, suffix: String, notes: [String] = []) -> Result {
        Result(kind: kind, primaryValue: .decimal(value), formattedPrimaryValue: NSDecimalNumber(decimal: value).stringValue + suffix, metadata: .init(notes: notes), displayExpression: expression)
    }
    private static func numericDecimal(_ value: Double, _ expression: String, kind: CalculatorResultKind, suffix: String, notes: [String] = []) -> Result { numeric(Decimal(value), expression, kind: kind, suffix: suffix, notes: notes) }
    private static func text(_ value: String, _ expression: String, notes: [String] = []) -> Result { Result(kind: .developerUtility, primaryValue: .text(value), formattedPrimaryValue: value, metadata: .init(notes: notes), displayExpression: expression) }
    private static func duration(_ seconds: Double, _ expression: String, kind: CalculatorResultKind, notes: [String] = []) -> Result { let total = Int(seconds.rounded()); let h = total / 3_600, m = (total % 3_600) / 60, s = total % 60; return Result(kind: kind, primaryValue: .decimal(Decimal(total)), formattedPrimaryValue: s == 0 ? "\(h) h \(m) min" : "\(h) h \(m) min \(s) s", metadata: .init(notes: notes + ["Primary value is total seconds."]), displayExpression: expression) }
    private static func pace(_ seconds: Double, _ expression: String, suffix: String) -> Result { let total = Int(seconds.rounded()); return Result(kind: .health, primaryValue: .decimal(Decimal(total)), formattedPrimaryValue: String(format: "%d:%02d %@", total / 60, total % 60, suffix), metadata: .init(notes: ["Primary value is seconds per distance unit."]), displayExpression: expression) }
    private static func clock(_ raw: String) -> Int? { let text = raw.lowercased().trimmingCharacters(in: .whitespaces); guard let g = captures(#"^(\d{1,2})(?::(\d{2}))?\s*(am|pm)?$"#, text), var h = Int(g[0]), let m = Int(g[1].isEmpty ? "0" : g[1]), m < 60 else { return nil }; if g[2] == "pm", h < 12 { h += 12 }; if g[2] == "am", h == 12 { h = 0 }; return h < 24 ? h * 3_600 + m * 60 : nil }
    private static func captures(_ pattern: String, _ text: String) -> [String]? { guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]), let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text)) else { return nil }; return (1..<match.numberOfRanges).map { index in guard match.range(at: index).location != NSNotFound, let range = Range(match.range(at: index), in: text) else { return "" }; return String(text[range]) } }
}
