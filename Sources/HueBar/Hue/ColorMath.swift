import Foundation

/// sRGB components in 0...1.
struct RGB: Equatable, Sendable {
    var r: Double
    var g: Double
    var b: Double
}

enum ColorMath {
    /// D65 white point.
    static let white = XY(x: 0.3127, y: 0.3290)

    /// Converts an sRGB color to CIE 1931 xy chromaticity, which is what the bridge expects.
    static func xy(from rgb: RGB) -> XY {
        func linear(_ channel: Double) -> Double {
            channel > 0.04045 ? pow((channel + 0.055) / 1.055, 2.4) : channel / 12.92
        }
        let r = linear(rgb.r)
        let g = linear(rgb.g)
        let b = linear(rgb.b)
        let x = r * 0.4124 + g * 0.3576 + b * 0.1805
        let y = r * 0.2126 + g * 0.7152 + b * 0.0722
        let z = r * 0.0193 + g * 0.1192 + b * 0.9505
        let sum = x + y + z
        guard sum > 0 else { return white }
        return XY(x: x / sum, y: y / sum)
    }

    /// Converts xy chromaticity to sRGB, normalized so the brightest channel is 1.
    static func rgb(xy: XY) -> RGB {
        guard xy.y > 0 else { return RGB(r: 1, g: 1, b: 1) }
        let bigY = 1.0
        let bigX = bigY / xy.y * xy.x
        let bigZ = bigY / xy.y * (1 - xy.x - xy.y)
        var r = max(3.2406 * bigX - 1.5372 * bigY - 0.4986 * bigZ, 0)
        var g = max(-0.9689 * bigX + 1.8758 * bigY + 0.0415 * bigZ, 0)
        var b = max(0.0557 * bigX - 0.2040 * bigY + 1.0570 * bigZ, 0)
        let peak = max(r, g, b)
        if peak > 0 {
            r /= peak
            g /= peak
            b /= peak
        }
        func gamma(_ channel: Double) -> Double {
            channel <= 0.0031308 ? 12.92 * channel : 1.055 * pow(channel, 1 / 2.4) - 0.055
        }
        return RGB(r: gamma(r), g: gamma(g), b: gamma(b))
    }

    /// Approximates the color of a white light at the given mirek (1,000,000 / kelvin).
    static func rgb(mirek: Int) -> RGB {
        let t = 1_000_000 / Double(max(mirek, 1)) / 100
        let r: Double
        let g: Double
        let b: Double
        if t <= 66 {
            r = 255
            g = 99.4708025861 * log(t) - 161.1195681661
        } else {
            r = 329.698727446 * pow(t - 60, -0.1332047592)
            g = 288.1221695283 * pow(t - 60, -0.0755148492)
        }
        if t >= 66 {
            b = 255
        } else if t <= 19 {
            b = 0
        } else {
            b = 138.5177312231 * log(t - 10) - 305.0447927307
        }
        func unit(_ value: Double) -> Double { min(max(value, 0), 255) / 255 }
        return RGB(r: unit(r), g: unit(g), b: unit(b))
    }

    /// sRGB color for a hue (0..<1, red at 0) and saturation (0...1) at full brightness.
    static func rgb(hue: Double, saturation: Double) -> RGB {
        let wrapped = hue - floor(hue)
        let sixths = wrapped * 6
        let sector = min(Int(sixths), 5)
        let fraction = sixths - Double(sector)
        let amount = min(max(saturation, 0), 1)
        let low = 1 - amount
        let falling = 1 - amount * fraction
        let rising = 1 - amount * (1 - fraction)
        switch sector {
        case 0: return RGB(r: 1, g: rising, b: low)
        case 1: return RGB(r: falling, g: 1, b: low)
        case 2: return RGB(r: low, g: 1, b: rising)
        case 3: return RGB(r: low, g: falling, b: 1)
        case 4: return RGB(r: rising, g: low, b: 1)
        default: return RGB(r: 1, g: low, b: falling)
        }
    }

    /// Hue (0..<1) and saturation (0...1) of a color, ignoring its brightness.
    static func hueSaturation(of rgb: RGB) -> (hue: Double, saturation: Double) {
        let brightest = max(rgb.r, rgb.g, rgb.b)
        let delta = brightest - min(rgb.r, rgb.g, rgb.b)
        guard brightest > 0, delta > 0 else { return (0, 0) }
        var sixths: Double
        if brightest == rgb.r {
            sixths = (rgb.g - rgb.b) / delta
        } else if brightest == rgb.g {
            sixths = 2 + (rgb.b - rgb.r) / delta
        } else {
            sixths = 4 + (rgb.r - rgb.g) / delta
        }
        if sixths < 0 { sixths += 6 }
        return (sixths / 6, delta / brightest)
    }

    static func mirek(kelvin: Int) -> Int {
        Int((1_000_000 / Double(kelvin)).rounded())
    }

    /// Moves a point that lies outside the light's color gamut to the closest reproducible color.
    static func clamp(_ point: XY, to gamut: Gamut) -> XY {
        let red = gamut.red
        let green = gamut.green
        let blue = gamut.blue
        if contains(point, red, green, blue) { return point }
        let candidates = [closest(point, red, green), closest(point, green, blue), closest(point, blue, red)]
        return candidates.min { distanceSquared($0, point) < distanceSquared($1, point) } ?? point
    }

    private static func cross(_ origin: XY, _ a: XY, _ b: XY) -> Double {
        (a.x - origin.x) * (b.y - origin.y) - (a.y - origin.y) * (b.x - origin.x)
    }

    private static func contains(_ point: XY, _ red: XY, _ green: XY, _ blue: XY) -> Bool {
        let sides = [cross(point, red, green), cross(point, green, blue), cross(point, blue, red)]
        return !(sides.contains { $0 < 0 } && sides.contains { $0 > 0 })
    }

    private static func closest(_ point: XY, _ a: XY, _ b: XY) -> XY {
        let abx = b.x - a.x
        let aby = b.y - a.y
        let lengthSquared = abx * abx + aby * aby
        guard lengthSquared > 0 else { return a }
        let t = min(max(((point.x - a.x) * abx + (point.y - a.y) * aby) / lengthSquared, 0), 1)
        return XY(x: a.x + t * abx, y: a.y + t * aby)
    }

    private static func distanceSquared(_ a: XY, _ b: XY) -> Double {
        (a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y)
    }
}
