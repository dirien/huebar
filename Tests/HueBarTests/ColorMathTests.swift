import Foundation
import Testing

@testable import HueBar

struct ColorMathTests {
    private let gamutC = Gamut(
        red: XY(x: 0.6915, y: 0.3083),
        green: XY(x: 0.17, y: 0.7),
        blue: XY(x: 0.1532, y: 0.0475)
    )

    @Test func srgbRedRoundTripsThroughXY() {
        let xy = ColorMath.xy(from: RGB(r: 1, g: 0, b: 0))
        #expect(abs(xy.x - 0.64) < 0.005 && abs(xy.y - 0.33) < 0.005)
        let rgb = ColorMath.rgb(xy: xy)
        #expect(rgb.r > 0.99 && rgb.g < 0.02 && rgb.b < 0.02)
    }

    @Test func whiteMapsToD65() {
        let xy = ColorMath.xy(from: RGB(r: 1, g: 1, b: 1))
        #expect(abs(xy.x - ColorMath.white.x) < 0.002 && abs(xy.y - ColorMath.white.y) < 0.002)
    }

    @Test func clampsOnlyOutOfGamutColors() {
        let outside = XY(x: 0.05, y: 0.9)
        let clamped = ColorMath.clamp(outside, to: gamutC)
        #expect(clamped != outside)
        #expect(clamped.y <= 0.7 + 1e-9)

        let inside = XY(x: 0.35, y: 0.35)
        #expect(ColorMath.clamp(inside, to: gamutC) == inside)
    }

    @Test func colorTemperatureRunsFromWarmToCool() {
        let warm = ColorMath.rgb(mirek: 454)
        let cool = ColorMath.rgb(mirek: 153)
        #expect(warm.r == 1 && warm.b < 0.6)
        #expect(cool.b > 0.95)
        #expect(ColorMath.mirek(kelvin: 2700) == 370)
        #expect(ColorMath.mirek(kelvin: 6500) == 154)
    }
}
