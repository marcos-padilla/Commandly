import Foundation

enum CalculatorGeometryAndPhysics {
    private static let n = CalculatorExpandedSupport.numberPattern
    private static let gravity = 9.80665
    private static let gravitationalConstant = 6.67430e-11
    private static let planckConstant = 6.626_070_15e-34
    private static let gasConstant = 8.314_462_618_153_24

    static func evaluate(_ text: String, original: String) -> CalculatorUtilities.Result? {
        if let result = geometry(text, original: original) {
            return result
        }
        guard let result = physics(text, original: original) else { return nil }
        return CalculatorUtilities.Result(
            kind: .scientific,
            primaryValue: result.primaryValue,
            formattedPrimaryValue: result.formattedPrimaryValue,
            metadata: result.metadata,
            displayExpression: result.displayExpression
        )
    }

    private static func geometry(
        _ text: String,
        original: String
    ) -> CalculatorUtilities.Result? {
        if let values = values(
            #"^area of a trapezoid bases (\#(n)) and (\#(n)) height (\#(n))$"#,
            text
        ), positive(values) {
            return result((values[0] + values[1]) * values[2] / 2, original, " square units")
        }
        if let values = values(
            #"^area of a parallelogram base (\#(n)) height (\#(n))$"#,
            text
        ), positive(values) {
            return result(values[0] * values[1], original, " square units")
        }
        if let values = values(
            #"^area of a rhombus diagonals (\#(n)) and (\#(n))$"#,
            text
        ), positive(values) {
            return result(values[0] * values[1] / 2, original, " square units")
        }
        if let values = values(
            #"^area of an ellipse radii (\#(n)) and (\#(n))$"#,
            text
        ), positive(values) {
            return result(.pi * values[0] * values[1], original, " square units")
        }
        if let values = values(
            #"^circumference of an ellipse radii (\#(n)) and (\#(n))$"#,
            text
        ), positive(values) {
            let a = values[0]
            let b = values[1]
            let approximation = .pi * (3 * (a + b) - sqrt((3 * a + b) * (a + 3 * b)))
            return result(
                approximation,
                original,
                " units",
                notes: ["Uses Ramanujan's first ellipse-circumference approximation."]
            )
        }
        if let groups = CalculatorExpandedSupport.captures(
            #"^interior angle of a regular (triangle|square|pentagon|hexagon|heptagon|octagon|nonagon|decagon)$"#,
            in: text
        ),
        let sides = polygonSides(groups[0]) {
            return result(Double(sides - 2) * 180 / Double(sides), original, "°")
        }
        if let groups = CalculatorExpandedSupport.captures(
            #"^sum interior angles of a (\d+)-gon$"#,
            in: text
        ),
        let sides = Int(groups[0]),
        sides >= 3 {
            return result(Double(sides - 2) * 180, original, "°")
        }
        if let groups = CalculatorExpandedSupport.captures(
            #"^exterior angle of a regular (\d+)-gon$"#,
            in: text
        ),
        let sides = Int(groups[0]),
        sides >= 3 {
            return result(360 / Double(sides), original, "°")
        }
        if let groups = CalculatorExpandedSupport.captures(
            #"^area of a regular (triangle|square|pentagon|hexagon|heptagon|octagon|nonagon|decagon) side (\#(n))$"#,
            in: text
        ),
        let sides = polygonSides(groups[0]),
        let side = Double(groups[1]),
        side > 0 {
            return regularPolygonArea(sides: sides, side: side, original: original)
        }
        if let groups = CalculatorExpandedSupport.captures(
            #"^area of a regular polygon (\d+) sides side (\#(n))$"#,
            in: text
        ),
        let sides = Int(groups[0]),
        let side = Double(groups[1]),
        sides >= 3, side > 0 {
            return regularPolygonArea(sides: sides, side: side, original: original)
        }
        if let values = values(
            #"^volume of a sphere radius (\#(n))$"#,
            text
        ), positive(values) {
            return result(4 * .pi * pow(values[0], 3) / 3, original, " cubic units")
        }
        if let values = values(
            #"^surface area of a cylinder radius (\#(n)) height (\#(n))$"#,
            text
        ), positive(values) {
            return result(
                2 * .pi * values[0] * (values[0] + values[1]),
                original,
                " square units"
            )
        }
        if let values = values(
            #"^surface area of a cone radius (\#(n)) slant height (\#(n))$"#,
            text
        ), positive(values) {
            return result(.pi * values[0] * (values[0] + values[1]), original, " square units")
        }
        if let values = values(
            #"^volume of a pyramid base area (\#(n)) height (\#(n))$"#,
            text
        ), positive(values) {
            return result(values[0] * values[1] / 3, original, " cubic units")
        }
        if let values = values(
            #"^volume of a triangular prism triangle base (\#(n)) height (\#(n)) length (\#(n))$"#,
            text
        ), positive(values) {
            return result(values[0] * values[1] * values[2] / 2, original, " cubic units")
        }
        if let values = values(
            #"^volume of a torus major radius (\#(n)) minor radius (\#(n))$"#,
            text
        ), positive(values), values[0] > values[1] {
            return result(
                2 * .pi * .pi * values[0] * pow(values[1], 2),
                original,
                " cubic units"
            )
        }
        if let values = values(
            #"^distance between points \(\s*(\#(n))\s*,\s*(\#(n))\s*\) and \(\s*(\#(n))\s*,\s*(\#(n))\s*\)$"#,
            text
        ) {
            return result(hypot(values[2] - values[0], values[3] - values[1]), original, " units")
        }
        if let values = values(
            #"^slope between points \(\s*(\#(n))\s*,\s*(\#(n))\s*\) and \(\s*(\#(n))\s*,\s*(\#(n))\s*\)$"#,
            text
        ), values[2] != values[0] {
            return result((values[3] - values[1]) / (values[2] - values[0]), original)
        }
        if let values = values(
            #"^midpoint between \(\s*(\#(n))\s*,\s*(\#(n))\s*\) and \(\s*(\#(n))\s*,\s*(\#(n))\s*\)$"#,
            text
        ) {
            let x = CalculatorExpandedSupport.plain((values[0] + values[2]) / 2)
            let y = CalculatorExpandedSupport.plain((values[1] + values[3]) / 2)
            return CalculatorExpandedSupport.text("(\(x), \(y))", expression: original)
        }
        if let values = values(
            #"^missing angle of triangle (\#(n)) and (\#(n)) degrees$"#,
            text
        ), values.allSatisfy({ $0 > 0 }), values[0] + values[1] < 180 {
            return result(180 - values[0] - values[1], original, "°")
        }
        if let groups = CalculatorExpandedSupport.captures(
            #"^area of triangle sides (\#(n))\s*,\s*(\#(n))\s*,\s*(\#(n))$"#,
            in: text
        ),
        let a = Double(groups[0]),
        let b = Double(groups[1]),
        let c = Double(groups[2]),
        a > 0, b > 0, c > 0,
        a + b > c, a + c > b, b + c > a {
            let semiperimeter = (a + b + c) / 2
            return result(
                sqrt(semiperimeter * (semiperimeter - a)
                    * (semiperimeter - b) * (semiperimeter - c)),
                original,
                " square units",
                notes: ["Uses Heron's formula."]
            )
        }
        if let values = values(
            #"^arc length radius (\#(n)) angle (\#(n)) degrees$"#,
            text
        ), positive(values) {
            return result(values[0] * values[1] * .pi / 180, original, " units")
        }
        if let values = values(
            #"^sector area radius (\#(n)) angle (\#(n)) degrees$"#,
            text
        ), positive(values) {
            return result(.pi * pow(values[0], 2) * values[1] / 360, original, " square units")
        }
        if let values = values(
            #"^(\#(n)) degrees as slope percent$"#,
            text
        ) {
            return result(tan(values[0] * .pi / 180) * 100, original, "%")
        }
        if let values = values(
            #"^(\#(n)) slope percent as degrees$"#,
            text
        ) {
            return result(atan(values[0] / 100) * 180 / .pi, original, "°")
        }
        return nil
    }

    private static func physics(
        _ text: String,
        original: String
    ) -> CalculatorUtilities.Result? {
        if let v = values(#"^speed for distance (\#(n)) m time (\#(n)) s$"#, text),
           v[1] != 0 {
            return result(v[0] / v[1], original, " m/s")
        }
        if let v = values(#"^distance at speed (\#(n)) m/s for (\#(n)) s$"#, text) {
            return result(v[0] * v[1], original, " m")
        }
        if let v = values(
            #"^acceleration from (\#(n)) m/s to (\#(n)) m/s in (\#(n)) s$"#,
            text
        ), v[2] != 0 {
            return result((v[1] - v[0]) / v[2], original, " m/s²")
        }
        if let v = values(
            #"^force for mass (\#(n)) kg acceleration (\#(n)) m/s2$"#,
            text
        ), v[0] >= 0 {
            return result(v[0] * v[1], original, " N")
        }
        if let v = values(
            #"^momentum for mass (\#(n)) kg velocity (\#(n)) m/s$"#,
            text
        ), v[0] >= 0 {
            return result(v[0] * v[1], original, " kg·m/s")
        }
        if let v = values(
            #"^kinetic energy for mass (\#(n)) kg velocity (\#(n)) m/s$"#,
            text
        ), v[0] >= 0 {
            return result(v[0] * pow(v[1], 2) / 2, original, " J")
        }
        if let v = values(
            #"^potential energy for mass (\#(n)) kg height (\#(n)) m$"#,
            text
        ), v[0] >= 0 {
            return result(v[0] * gravity * v[1], original, " J")
        }
        if let v = values(#"^power for energy (\#(n)) j over (\#(n)) s$"#, text),
           v[1] != 0 {
            return result(v[0] / v[1], original, " W")
        }
        if let v = values(
            #"^pressure for force (\#(n)) n over area (\#(n)) m2$"#,
            text
        ), v[1] > 0 {
            return result(v[0] / v[1], original, " Pa")
        }
        if let v = values(
            #"^density for mass (\#(n)) kg volume (\#(n)) m3$"#,
            text
        ), v[1] > 0 {
            return result(v[0] / v[1], original, " kg/m³")
        }
        if let v = values(
            #"^mass for density (\#(n)) kg/m3 volume (\#(n)) m3$"#,
            text
        ), positive(v) {
            return result(v[0] * v[1], original, " kg")
        }
        if let v = values(#"^work for force (\#(n)) n distance (\#(n)) m$"#, text) {
            return result(v[0] * v[1], original, " J")
        }
        if let v = values(#"^impulse for force (\#(n)) n over (\#(n)) s$"#, text) {
            return result(v[0] * v[1], original, " N·s")
        }
        if let v = values(#"^frequency for period (\#(n)) s$"#, text), v[0] > 0 {
            return result(1 / v[0], original, " Hz")
        }
        if let v = values(#"^period for frequency (\#(n)) hz$"#, text), v[0] > 0 {
            return result(1 / v[0], original, " s")
        }
        if let v = values(
            #"^wavelength at speed (\#(n)) m/s frequency (\#(n)) hz$"#,
            text
        ), v[1] > 0 {
            return result(v[0] / v[1], original, " m")
        }
        if let v = values(
            #"^wave speed for frequency (\#(n)) hz wavelength (\#(n)) m$"#,
            text
        ) {
            return result(v[0] * v[1], original, " m/s")
        }
        if let v = values(
            #"^current for voltage (\#(n)) v resistance (\#(n)) ohms?$"#,
            text
        ), v[1] != 0 {
            return result(v[0] / v[1], original, " A")
        }
        if let v = values(
            #"^resistance for voltage (\#(n)) v current (\#(n)) a$"#,
            text
        ), v[1] != 0 {
            return result(v[0] / v[1], original, " Ω")
        }
        if let v = values(
            #"^electrical power for voltage (\#(n)) v current (\#(n)) a$"#,
            text
        ) {
            return result(v[0] * v[1], original, " W")
        }
        if let v = values(
            #"^electrical energy for power (\#(n)) w over (\#(n)) hours?$"#,
            text
        ) {
            return result(v[0] * v[1], original, " Wh")
        }
        if let v = values(#"^charge for current (\#(n)) a over (\#(n)) s$"#, text) {
            return result(v[0] * v[1], original, " C")
        }
        if let v = values(#"^mass energy for (\#(n)) kg$"#, text), v[0] >= 0 {
            return result(v[0] * pow(299_792_458, 2), original, " J")
        }
        if let v = values(#"^photon energy for frequency (\#(n)) hz$"#, text),
           v[0] >= 0 {
            return result(planckConstant * v[0], original, " J")
        }
        if let v = values(#"^free fall distance after (\#(n)) s$"#, text), v[0] >= 0 {
            return result(
                gravity * pow(v[0], 2) / 2,
                original,
                " m",
                notes: ["Assumes constant standard gravity and no air resistance."]
            )
        }
        if let v = values(
            #"^ideal gas pressure for (\#(n)) mol at (\#(n)) k in (\#(n)) m3$"#,
            text
        ), v[0] >= 0, v[1] >= 0, v[2] > 0 {
            return result(v[0] * gasConstant * v[1] / v[2], original, " Pa")
        }
        if let v = values(
            #"^centripetal force mass (\#(n)) kg velocity (\#(n)) m/s radius (\#(n)) m$"#,
            text
        ), v[0] >= 0, v[2] > 0 {
            return result(v[0] * pow(v[1], 2) / v[2], original, " N")
        }
        if let v = values(
            #"^centripetal acceleration velocity (\#(n)) m/s radius (\#(n)) m$"#,
            text
        ), v[1] > 0 {
            return result(pow(v[0], 2) / v[1], original, " m/s²")
        }
        if let v = values(
            #"^spring energy k (\#(n)) n/m stretch (\#(n)) m$"#,
            text
        ), v[0] >= 0 {
            return result(v[0] * pow(v[1], 2) / 2, original, " J")
        }
        if let v = values(
            #"^hooke force k (\#(n)) n/m stretch (\#(n)) m$"#,
            text
        ), v[0] >= 0 {
            return result(v[0] * v[1], original, " N")
        }
        if let v = values(
            #"^gravitational force masses (\#(n)) kg and (\#(n)) kg distance (\#(n)) m$"#,
            text
        ), v[0] >= 0, v[1] >= 0, v[2] > 0 {
            return result(gravitationalConstant * v[0] * v[1] / pow(v[2], 2), original, " N")
        }
        return nil
    }

    private static func regularPolygonArea(
        sides: Int,
        side: Double,
        original: String
    ) -> CalculatorUtilities.Result? {
        result(
            Double(sides) * side * side / (4 * tan(.pi / Double(sides))),
            original,
            " square units"
        )
    }

    private static func polygonSides(_ name: String) -> Int? {
        [
            "triangle": 3, "square": 4, "pentagon": 5, "hexagon": 6,
            "heptagon": 7, "octagon": 8, "nonagon": 9, "decagon": 10,
        ][name]
    }

    private static func values(_ pattern: String, _ text: String) -> [Double]? {
        guard let groups = CalculatorExpandedSupport.captures(pattern, in: text) else {
            return nil
        }
        let parsed = groups.map(Double.init)
        return parsed.allSatisfy({ $0 != nil }) ? parsed.compactMap { $0 } : nil
    }

    private static func positive(_ values: [Double]) -> Bool {
        values.allSatisfy { $0 > 0 }
    }

    private static func result(
        _ value: Double,
        _ original: String,
        _ suffix: String = "",
        notes: [String] = []
    ) -> CalculatorUtilities.Result? {
        CalculatorExpandedSupport.numeric(
            value,
            expression: original,
            kind: .geometry,
            suffix: suffix,
            notes: notes
        )
    }
}
