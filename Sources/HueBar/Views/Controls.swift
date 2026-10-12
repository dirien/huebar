import SwiftUI

/// A Control Center–style brightness bar: drag anywhere to set the level. 0 means off.
struct LevelSlider: View {
    let value: Double
    let colors: [Color]
    var height: CGFloat = 26
    let label: String
    let onChange: (Double) -> Void

    @State private var dragValue: Double?

    var body: some View {
        let shown = dragValue ?? value
        let percent = Int(shown.rounded())
        let text = percent < 1 ? "Off" : "\(percent)%"

        GeometryReader { proxy in
            let width = max(proxy.size.width, 1)
            let filled = width * shown / 100
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(Color.primary.opacity(0.08))
                Theme.gradient(colors)
                    .mask(alignment: .leading) {
                        Rectangle().frame(width: filled)
                    }
                HStack(spacing: 0) {
                    Ph(.sunDim, .fill, size: height * 0.52)
                        .foregroundStyle(filled > height * 0.9 ? Theme.onLight : Color.secondary)
                    Spacer(minLength: 4)
                    Text(verbatim: text)
                        .font(.system(size: max(height * 0.42, 9), weight: .semibold).monospacedDigit())
                        .foregroundStyle(filled > width - height * 1.5 ? Theme.onLight : Color.secondary)
                }
                .padding(.horizontal, height * 0.32)
            }
            .clipShape(Capsule())
            .contentShape(Capsule())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        let level = (min(max(drag.location.x / width, 0), 1) * 100).rounded()
                        guard level != dragValue else { return }
                        dragValue = level
                        onChange(level)
                    }
                    .onEnded { _ in dragValue = nil }
            )
        }
        .frame(height: height)
        .animation(dragValue == nil ? .snappy(duration: 0.25) : nil, value: value)
        .accessibilityElement()
        .accessibilityLabel(label)
        .accessibilityValue(Text(verbatim: percent < 1 ? "Off" : "\(percent) percent"))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: onChange(min(value + 10, 100))
            case .decrement: onChange(max(value - 10, 0))
            @unknown default: break
            }
        }
    }
}

/// An on/off switch whose track takes on the color of the lights it controls.
struct PillToggle: View {
    let isOn: Bool
    var colors: [Color] = []
    var width: CGFloat = 38
    let label: String
    let action: (Bool) -> Void

    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovering = false

    var body: some View {
        ZStack(alignment: isOn ? .trailing : .leading) {
            Capsule()
                .fill(
                    isOn
                        ? AnyShapeStyle(Theme.gradient(colors))
                        : AnyShapeStyle(Color.primary.opacity(isHovering ? 0.22 : 0.15))
                )
            Circle()
                .fill(Color.white)
                .shadow(color: Color.black.opacity(0.25), radius: 1.5, y: 1)
                .padding(2.5)
        }
        .frame(width: width, height: (width * 0.6).rounded())
        .opacity(isEnabled ? 1 : 0.4)
        .contentShape(Capsule())
        .onTapGesture {
            if isEnabled { action(!isOn) }
        }
        .onHover { isHovering = $0 }
        .animation(.snappy(duration: 0.2), value: isOn)
        .accessibilityElement()
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(label)
        .accessibilityValue(Text(isOn ? "On" : "Off"))
        .accessibilityAction { action(!isOn) }
    }
}

/// A borderless icon button with a hover highlight.
struct IconButton: View {
    let icon: PhosphorIcon
    var weight: PhosphorWeight = .regular
    var size: CGFloat = 28
    var isActive = false
    let help: String
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Ph(icon, weight, size: size * 0.56)
                .frame(width: size, height: size)
                .foregroundStyle(isActive ? Theme.amber : (isHovering ? Color.primary : Color.secondary))
                .background(
                    RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                        .fill(Color.primary.opacity(isHovering || isActive ? 0.1 : 0))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(help)
        .accessibilityLabel(help)
    }
}

/// The primary call-to-action button.
struct AccentButton: View {
    let title: String
    var icon: PhosphorIcon?
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon {
                    Ph(icon, .bold, size: 13)
                }
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(Theme.onLight)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(Capsule().fill(Theme.gradient([], from: .topLeading, to: .bottomTrailing)))
            .brightness(isHovering && isEnabled ? 0.06 : 0)
            .opacity(isEnabled ? 1 : 0.45)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

/// A rounded tile holding an icon, lit with the colors of the lights it represents.
struct IconTile: View {
    let icon: PhosphorIcon
    let colors: [Color]
    let isOn: Bool
    var size: CGFloat = 34

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
                .fill(
                    isOn
                        ? AnyShapeStyle(Theme.gradient(colors, from: .topLeading, to: .bottomTrailing))
                        : AnyShapeStyle(Color.primary.opacity(0.08))
                )
            Ph(icon, .duotone, size: size * 0.56)
                .foregroundStyle(isOn ? Theme.onLight : Color.secondary)
        }
        .frame(width: size, height: size)
        .shadow(color: isOn ? (colors.first ?? Theme.amber).opacity(0.45) : Color.clear, radius: size * 0.2)
        .animation(.snappy(duration: 0.3), value: isOn)
    }
}

/// A glowing orb with a light bulb, used as the hero of the header and setup screen.
struct GlowOrb: View {
    let colors: [Color]
    let isOn: Bool
    var icon: PhosphorIcon = .lightbulb
    var size: CGFloat = 40

    var body: some View {
        let gradient = Theme.gradient(colors, from: .topLeading, to: .bottomTrailing)
        ZStack {
            if isOn {
                Circle()
                    .fill(gradient)
                    .blur(radius: size * 0.3)
                    .opacity(0.75)
            }
            Circle()
                .fill(isOn ? AnyShapeStyle(gradient) : AnyShapeStyle(Color.primary.opacity(0.08)))
            Ph(icon, isOn ? .fill : .duotone, size: size * 0.5)
                .foregroundStyle(isOn ? Theme.onLight : Color.secondary)
        }
        .frame(width: size, height: size)
        .animation(.snappy(duration: 0.3), value: isOn)
    }
}

/// Lays children out left to right, wrapping onto new rows as needed.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var widest: CGFloat = 0
        for subview in subviews {
            let size = Self.size(of: subview, maxWidth: maxWidth)
            if x > 0 && x + size.width > maxWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            widest = max(widest, x - spacing)
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: proposal.width ?? widest, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal _: ProposedViewSize, subviews: Subviews, cache _: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = Self.size(of: subview, maxWidth: bounds.width)
            if x > bounds.minX && x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }

    private static func size(of subview: LayoutSubview, maxWidth: CGFloat) -> CGSize {
        let ideal = subview.sizeThatFits(.unspecified)
        guard ideal.width > maxWidth else { return ideal }
        return subview.sizeThatFits(ProposedViewSize(width: maxWidth, height: nil))
    }
}
