import AppKit
import SwiftUI

/// Hue around the circle, saturation from the white center out to the rim; drag anywhere to pick.
/// Brightness is left to the light's own slider, so the wheel always shows colors at full brightness.
struct ColorWheel: View {
    /// The light's current color, or nil while it shows a white color temperature.
    let color: RGB?
    var size: CGFloat = 150
    let onChange: (RGB) -> Void

    @State private var dragged: RGB?

    private static let hueRing = AngularGradient(
        colors: stride(from: 0.0, through: 1.0, by: 1.0 / 12).map { Color(ColorMath.rgb(hue: $0, saturation: 1)) },
        center: .center,
        startAngle: .degrees(0),
        endAngle: .degrees(360)
    )

    var body: some View {
        let radius = size / 2
        let knob: CGFloat = 22

        let whiteCenter = RadialGradient(
            colors: [.white, .white.opacity(0)],
            center: .center,
            startRadius: 0,
            endRadius: radius
        )

        ZStack {
            Circle()
                .fill(Self.hueRing)
            Circle()
                .fill(whiteCenter)
            Circle()
                .strokeBorder(Color.primary.opacity(0.15), lineWidth: 1)
            if let shown = dragged ?? color {
                let position = ColorMath.hueSaturation(of: shown)
                let angle = position.hue * 2 * .pi
                let saturation = position.saturation
                Circle()
                    .fill(Color(ColorMath.rgb(hue: position.hue, saturation: saturation)))
                    .overlay(Circle().strokeBorder(Color.white, lineWidth: 3))
                    .shadow(color: Color.black.opacity(0.35), radius: 3, y: 1)
                    .frame(width: knob, height: knob)
                    .offset(
                        x: cos(angle) * saturation * (radius - knob / 2),
                        y: sin(angle) * saturation * (radius - knob / 2)
                    )
            }
        }
        .frame(width: size, height: size)
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { drag in
                    let offsetX = drag.location.x - radius
                    let offsetY = drag.location.y - radius
                    // SwiftUI's y axis points down, so atan2 runs clockwise like the angular gradient.
                    var hue = atan2(offsetY, offsetX) / (2 * .pi)
                    if hue < 0 { hue += 1 }
                    let saturation = min(hypot(offsetX, offsetY) / (radius - knob / 2), 1)
                    let picked = ColorMath.rgb(hue: hue, saturation: saturation)
                    guard picked != dragged else { return }
                    dragged = picked
                    onChange(picked)
                }
                .onEnded { _ in dragged = nil }
        )
        .accessibilityElement()
        .accessibilityLabel("Color wheel")
        .accessibilityValue(Text(verbatim: accessibilityDescription))
        .accessibilityAdjustableAction { direction in
            let current = ColorMath.hueSaturation(of: color ?? RGB(r: 1, g: 0, b: 0))
            let step = direction == .increment ? 1.0 / 24 : -1.0 / 24
            onChange(ColorMath.rgb(hue: current.hue + step, saturation: max(current.saturation, 0.6)))
        }
    }

    private var accessibilityDescription: String {
        guard let color else { return "White" }
        let (hue, saturation) = ColorMath.hueSaturation(of: color)
        return "Hue \(Int((hue * 360).rounded())) degrees, saturation \(Int((saturation * 100).rounded())) percent"
    }
}

/// Picks a color from anywhere on screen with the system color sampler.
struct EyedropperButton: View {
    let onPick: (RGB) -> Void

    @State private var sampler: NSColorSampler?

    var body: some View {
        IconButton(icon: .eyedropper, size: 26, isActive: sampler != nil, help: "Pick a color from the screen") {
            let sampler = NSColorSampler()
            self.sampler = sampler
            sampler.show { picked in
                Task { @MainActor in
                    self.sampler = nil
                    guard let rgb = picked?.usingColorSpace(.sRGB) else { return }
                    onPick(RGB(r: rgb.redComponent, g: rgb.greenComponent, b: rgb.blueComponent))
                }
            }
        }
    }
}
