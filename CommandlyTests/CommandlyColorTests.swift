import Foundation
import Testing
@testable import Commandly

struct CommandlyColorTests {
    @Test(arguments: ["#F00", "#FF0000", "rgb(255, 0, 0)", "RGBA(100%, 0%, 0%, 100%)", "rgb(100% 0 0 / 1)", "hsl(0, 100%, 50%)", "hsla(360deg 100 50 / 100%)", "hsl(-1turn 100% 50%)", "hsl(400grad 100% 50%)", "hsl(6.283185307179586rad 100% 50%)", "rgb(+2.55e2 0 0)"])
    func recognizesRedAcrossBothSyntaxes(_ input: String) throws {
        let value = try #require(CommandlyColor(string: input))
        #expect(abs(value.red - 1) < 0.000001)
        #expect(value.green < 0.000001)
        #expect(value.blue < 0.000001)
        #expect(value.alpha == 1)
    }

    @Test(arguments: ["", "red", "#12", "#12345", "#1234567", "#123456789", "#12x", "rgbjunk(1,2,3)", "rgbaWhatever(1,2,3)", "rgb(1,2,3)junk", "rgb (1,2,3)", "rgb(1 2)", "rgb(1 2 3 4)", "rgb(1, 2 3)", "rgb(1,2,3 / .5)", "rgb(1 2 3,.5)", "rgb(1%,2,3)", "rgb(1,2,3,none)", "rgb(none,2,3)", "rgb(1..0 2 3)", "rgb(1. 2 3)", "rgb(1e 2 3)", "rgb(1e999 2 3)", "rgb(nan 2 3)", "rgb(inf 2 3)", "rgb(1 2 3 / NaN)", "rgb(1 2 3 / .5garbage)", "rgb(1 2 3 / 1deg)", "rgb(1 2 3 /)", "rgb(1 2 3 //1)", "rgb(1/**/2 3)", "rgb(calc(1) 2 3)", "rgb(1 2 3))", "hsl(0%, 100%, 50%)", "hsl(0,100,50)", "hsl(0rad 100deg 50%)", "hsl(none, 100%, 50%)", "hsl(0 100% 50% / 1turn)", "hsl(0 1e308% 1e308%)", "#ＦＦＦ", "rgb(1\u{00A0}2 3)"])
    func rejectsInvalidAndUnsupportedLiterals(_ input: String) {
        #expect(CommandlyColor(string: input) == nil)
    }

    @Test func finiteBoundsAndInputLength() throws {
        #expect(CommandlyColor(red: .nan, green: 0, blue: 0) == nil)
        #expect(CommandlyColor(red: 0, green: .infinity, blue: 0) == nil)
        #expect(CommandlyColor(red: 0, green: 0, blue: -.infinity) == nil)
        #expect(CommandlyColor(red: 0, green: 0, blue: 0, alpha: .nan) == nil)
        let value = try #require(CommandlyColor(string: "rgb(1e308 -1e308 50% / 200%)"))
        #expect(value == CommandlyColor(red: 1, green: 0, blue: 0.5))
        #expect(CommandlyColor(string: "\t\n #123 \r\u{000C}")?.hex == "#112233")
        #expect(CommandlyColor(string: String(repeating: " ", count: 252) + "#123") != nil)
        #expect(CommandlyColor(string: String(repeating: " ", count: 253) + "#123") == nil)
        #expect(CommandlyColor(string: String(repeating: "x", count: 100_000)) == nil)
    }

    @Test func knownVectorsAlphaAndAllSixOutputs() throws {
        let value = try #require(CommandlyColor(string: "#966A5E"))
        #expect(CommandlyColorFormat.allCases.map(\.title) == ["Hex", "Hex with Alpha", "RGBA", "RGBA (Percentage)", "RGB (CSS4)", "HSL"])
        #expect(value.formatted(.hex) == "#966A5E")
        #expect(value.formatted(.hexWithAlpha) == "#966A5EFF")
        #expect(value.formatted(.rgba) == "rgba(150, 106, 94, 1)")
        #expect(value.formatted(.rgbaPercentage) == "rgba(58.823529%, 41.568627%, 36.862745%, 100%)")
        #expect(value.formatted(.rgbCSS4) == "rgb(150 106 94 / 1)")
        #expect(value.formatted(.hsl) == "hsl(12.857143 22.95082% 47.843137% / 1)")
        let alpha = try #require(CommandlyColor(string: "hsl(.333333333333turn 100% 50% / 25%)"))
        #expect(alpha.formatted(.hexWithAlpha) == "#00FF0040")
        #expect(alpha.formatted(.hsl).hasSuffix("/ 0.25)"))
        #expect(alpha.defaultFormat == .hexWithAlpha)
        #expect(CommandlyColor(string: "#1234")?.hex == "#11223344")
        #expect(CommandlyColor(string: "rgb(0 0 0 / .9999)")?.defaultFormat == .hexWithAlpha)
        #expect(CommandlyColor(string: "rgb(none 50% none / none)") == CommandlyColor(red: 0, green: 0.5, blue: 0, alpha: 0))
    }

    @Test func extremeFiniteColorsNeverSerializeNonFiniteComponents() throws {
        for tiny in [Double.leastNonzeroMagnitude, Double.leastNormalMagnitude, 1e-16] {
            for color in [CommandlyColor(red: tiny, green: 0, blue: 0), CommandlyColor(red: 1, green: 1 - tiny, blue: 1)] {
                let value = try #require(color)
                for format in CommandlyColorFormat.allCases {
                    #expect(CommandlyColor(string: value.formatted(format)) != nil)
                }
            }
        }
    }

    @Test func normalizedHSLAndAchromaticVectors() {
        #expect(CommandlyColor(string: "hsl(120 -100% 50%)")?.hex == "#808080")
        #expect(CommandlyColor(string: "hsl(720 100% 0%)")?.hex == "#000000")
        #expect(CommandlyColor(string: "hsl(120 100% 100%)")?.hex == "#FFFFFF")
        #expect(CommandlyColor(string: "hsl(-240 100% 50%)")?.hex == "#00FF00")
        #expect(CommandlyColor(string: "hsl(1e308deg 100% 50%)") != nil)
    }

    @Test func allFormatsRoundTripDeterministicChannelGrid() throws {
        for red in [0.0, 0.01, 0.125, 0.5, 0.999999, 1] {
            for green in [0.0, 0.25, 1] {
                for blue in [0.0, 0.75, 1] {
                    for alpha in [0.0, 0.123456, 0.5, 1] {
                        let original = try #require(CommandlyColor(red: red, green: green, blue: blue, alpha: alpha))
                        for format in CommandlyColorFormat.allCases {
                            let decoded = try #require(CommandlyColor(string: original.formatted(format)))
                            let tolerance = format == .hex || format == .hexWithAlpha ? 0.5 / 255 + 1e-10 : 0.000002
                            #expect(abs(decoded.red - red) <= tolerance)
                            #expect(abs(decoded.green - green) <= tolerance)
                            #expect(abs(decoded.blue - blue) <= tolerance)
                            #expect(abs(decoded.alpha - (format.preservesAlpha ? alpha : 1)) <= tolerance)
                        }
                    }
                }
            }
        }
    }
}
