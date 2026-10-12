import SwiftUI

struct LightRow: View {
    @Environment(HueStore.self) private var store
    let light: Light

    @State private var showingColors = false

    var body: some View {
        let reachable = store.isReachable(light)
        let isOn = light.on.on && reachable
        let colors = [Color(light.displayRGB)]
        let name = store.name(of: light)
        let canColor = light.color != nil || light.colorTemperature?.mirekSchema != nil

        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 9) {
                IconTile(icon: Symbols.light(store.archetype(of: light)), colors: colors, isOn: isOn, size: 26)
                VStack(alignment: .leading, spacing: 0) {
                    Text(name)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                    if !reachable {
                        HStack(spacing: 3) {
                            Ph(.wifiSlash, size: 10)
                            Text("Unreachable")
                        }
                        .font(.system(size: 10))
                        .foregroundStyle(.orange)
                    }
                }
                Spacer(minLength: 4)
                if canColor {
                    IconButton(
                        icon: .palette,
                        weight: showingColors ? .fill : .regular,
                        size: 24,
                        isActive: showingColors,
                        help: "Color"
                    ) {
                        withAnimation(.snappy(duration: 0.25)) { showingColors.toggle() }
                    }
                }
                PillToggle(isOn: light.on.on, colors: colors, width: 32, label: name) { on in
                    store.setOn(on, light: light.id)
                }
            }
            if light.dimming != nil {
                LevelSlider(
                    value: store.level(of: light),
                    colors: colors,
                    height: 18,
                    label: "\(name) brightness"
                ) { level in
                    store.setBrightness(level, light: light.id)
                }
                .padding(.leading, 35)
            }
            if showingColors && canColor {
                ColorPanel(light: light)
                    .padding(.leading, 35)
            }
        }
    }
}

private struct ColorPanel: View {
    @Environment(HueStore.self) private var store
    let light: Light

    private struct ColorSwatch: Identifiable {
        let id: String
        let rgb: RGB
    }

    private struct WhiteSwatch: Identifiable {
        let id: String
        let kelvin: Int
    }

    private static let colors = [
        ColorSwatch(id: "Red", rgb: RGB(r: 1, g: 0.12, b: 0.1)),
        ColorSwatch(id: "Orange", rgb: RGB(r: 1, g: 0.5, b: 0)),
        ColorSwatch(id: "Yellow", rgb: RGB(r: 1, g: 0.85, b: 0.1)),
        ColorSwatch(id: "Green", rgb: RGB(r: 0.2, g: 0.9, b: 0.25)),
        ColorSwatch(id: "Cyan", rgb: RGB(r: 0, g: 0.85, b: 0.9)),
        ColorSwatch(id: "Blue", rgb: RGB(r: 0.15, g: 0.3, b: 1)),
        ColorSwatch(id: "Purple", rgb: RGB(r: 0.6, g: 0.2, b: 1)),
        ColorSwatch(id: "Pink", rgb: RGB(r: 1, g: 0.3, b: 0.7)),
    ]

    private static let whites = [
        WhiteSwatch(id: "Candlelight", kelvin: 2200),
        WhiteSwatch(id: "Warm white", kelvin: 2700),
        WhiteSwatch(id: "Neutral", kelvin: 4000),
        WhiteSwatch(id: "Daylight", kelvin: 6500),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let schema = light.colorTemperature?.mirekSchema {
                VStack(alignment: .leading, spacing: 8) {
                    PanelLabel(icon: .sun, title: "White")
                    TemperatureSlider(
                        mirek: light.isInColorTemperatureMode ? light.colorTemperature?.mirek : nil,
                        schema: schema
                    ) { mirek in
                        store.setMirek(mirek, light: light.id)
                    }
                    HStack(spacing: 4) {
                        ForEach(Self.whites) { white in
                            let mirek = ColorMath.mirek(kelvin: white.kelvin)
                            SwatchButton(
                                color: Color(ColorMath.rgb(mirek: mirek)),
                                label: white.id,
                                isSelected: light.isInColorTemperatureMode
                                    && abs((light.colorTemperature?.mirek ?? 0) - mirek) < 8
                            ) {
                                store.setMirek(mirek, light: light.id)
                            }
                        }
                    }
                }
            }
            if let current = light.color {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        PanelLabel(icon: .palette, title: "Color")
                        Spacer()
                        EyedropperButton { picked in
                            store.setColor(picked, light: light.id)
                        }
                    }
                    ColorWheel(color: light.isInColorTemperatureMode ? nil : ColorMath.rgb(xy: current.xy)) { picked in
                        store.setColor(picked, light: light.id)
                    }
                    .frame(maxWidth: .infinity)
                    HStack(spacing: 4) {
                        ForEach(Self.colors) { swatch in
                            SwatchButton(
                                color: Color(swatch.rgb),
                                label: swatch.id,
                                isSelected: !light.isInColorTemperatureMode && matches(swatch.rgb, current)
                            ) {
                                store.setColor(swatch.rgb, light: light.id)
                            }
                        }
                    }
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
    }

    private func matches(_ rgb: RGB, _ current: ColorState) -> Bool {
        var target = ColorMath.xy(from: rgb)
        if let gamut = current.gamut {
            target = ColorMath.clamp(target, to: gamut)
        }
        return abs(target.x - current.xy.x) + abs(target.y - current.xy.y) < 0.02
    }
}

private struct PanelLabel: View {
    let icon: PhosphorIcon
    let title: String

    var body: some View {
        HStack(spacing: 4) {
            Ph(icon, .fill, size: 10)
            Text(title.uppercased())
                .font(.system(size: 9, weight: .bold))
                .tracking(0.6)
        }
        .foregroundStyle(.secondary)
    }
}

/// Warm-to-cool track for white lights. The knob is hidden while the light is in color mode.
private struct TemperatureSlider: View {
    let mirek: Int?
    let schema: MirekSchema
    let onChange: (Int) -> Void

    @State private var dragMirek: Int?

    var body: some View {
        let range = Double(max(schema.mirekMaximum - schema.mirekMinimum, 1))
        let step = max(1, Int(range) / 6)
        let stops = stride(from: schema.mirekMaximum, through: schema.mirekMinimum, by: -step)
            .map { Color(ColorMath.rgb(mirek: $0)) }
        let knob: CGFloat = 16

        GeometryReader { proxy in
            let travel = max(proxy.size.width - knob, 1)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(LinearGradient(colors: stops, startPoint: .leading, endPoint: .trailing))
                    .overlay(Capsule().strokeBorder(Color.primary.opacity(0.12)))
                    .frame(height: 8)
                    .padding(.horizontal, knob / 2)
                if let current = dragMirek ?? mirek {
                    let fraction = Double(schema.mirekMaximum - current) / range
                    Circle()
                        .fill(Color(ColorMath.rgb(mirek: current)))
                        .overlay(Circle().strokeBorder(Color.white, lineWidth: 2))
                        .shadow(color: Color.black.opacity(0.3), radius: 2, y: 1)
                        .frame(width: knob, height: knob)
                        .offset(x: min(max(fraction, 0), 1) * travel)
                }
            }
            .frame(height: knob)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        let fraction = min(max((drag.location.x - knob / 2) / travel, 0), 1)
                        let value = schema.mirekMaximum - Int((fraction * range).rounded())
                        guard value != dragMirek else { return }
                        dragMirek = value
                        onChange(value)
                    }
                    .onEnded { _ in dragMirek = nil }
            )
        }
        .frame(height: knob)
        .accessibilityElement()
        .accessibilityLabel("Color temperature")
        .accessibilityValue(Text(verbatim: mirek.map { "\(1_000_000 / max($0, 1)) kelvin" } ?? "Color mode"))
        .accessibilityAdjustableAction { direction in
            let current = mirek ?? schema.mirekMaximum
            switch direction {
            case .increment: onChange(max(current - 25, schema.mirekMinimum))
            case .decrement: onChange(min(current + 25, schema.mirekMaximum))
            @unknown default: break
            }
        }
    }
}

private struct SwatchButton: View {
    let color: Color
    let label: String
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(color)
                .overlay(Circle().strokeBorder(Color.primary.opacity(0.15), lineWidth: 1))
                .frame(width: 20, height: 20)
                .padding(2)
                .overlay(Circle().strokeBorder(isSelected ? Color.primary.opacity(0.8) : Color.clear, lineWidth: 1.5))
                .scaleEffect(isHovering ? 1.12 : 1)
                .animation(.snappy(duration: 0.15), value: isHovering)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(label)
        .accessibilityLabel(label)
    }
}
