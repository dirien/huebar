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

    @Test(arguments: [0.0, 0.08, 1.0 / 6, 0.33, 0.5, 0.61, 0.75, 0.92])
    func hueSaturationRoundTrips(hue: Double) {
        for saturation in [0.2, 0.55, 1.0] {
            let rgb = ColorMath.rgb(hue: hue, saturation: saturation)
            let back = ColorMath.hueSaturation(of: rgb)
            #expect(abs(back.hue - hue) < 1e-9 || abs(abs(back.hue - hue) - 1) < 1e-9)
            #expect(abs(back.saturation - saturation) < 1e-9)
        }
    }

    @Test func wheelEdgesArePrimariesAndCenterIsWhite() {
        #expect(ColorMath.rgb(hue: 0, saturation: 1) == RGB(r: 1, g: 0, b: 0))
        #expect(ColorMath.rgb(hue: 1.0 / 3, saturation: 1) == RGB(r: 0, g: 1, b: 0))
        #expect(ColorMath.rgb(hue: 2.0 / 3, saturation: 1) == RGB(r: 0, g: 0, b: 1))
        #expect(ColorMath.rgb(hue: 0.4, saturation: 0) == RGB(r: 1, g: 1, b: 1))
        // Brightness doesn't matter, only hue and saturation.
        let dim = ColorMath.hueSaturation(of: RGB(r: 0.5, g: 0.25, b: 0))
        #expect(abs(dim.hue - 1.0 / 12) < 1e-9 && abs(dim.saturation - 1) < 1e-9)
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
