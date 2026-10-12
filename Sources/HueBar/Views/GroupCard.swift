import SwiftUI

/// A room or zone: on/off and brightness, and when expanded its scenes and individual lights.
struct GroupCard: View {
    @Environment(HueStore.self) private var store
    let group: HueGroup
    @Binding var isExpanded: Bool

    @State private var isHovering = false

    var body: some View {
        let members = store.lights(in: group)
        let lit = members.filter { $0.on.on && store.isReachable($0) }
        let colors = Theme.colors(of: lit)
        let isOn = !lit.isEmpty
        let canControl = store.groupedLight(for: group) != nil
        let isDimmable = members.contains { $0.dimming != nil }

        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                IconTile(icon: Symbols.room(group.metadata.archetype), colors: colors, isOn: isOn)
                VStack(alignment: .leading, spacing: 1) {
                    Text(group.metadata.name)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    Text(subtitle(lit: lit.count, total: members.count))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 6)
                Ph(.caretDown, .bold, size: 10)
                    .foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(isExpanded ? 0 : -90))
                PillToggle(isOn: isOn, colors: colors, label: group.metadata.name) { on in
                    store.setOn(on, group: group)
                }
                .disabled(!canControl)
                .onTapGesture {}  // keep taps on a disabled toggle from expanding the card
            }
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.snappy(duration: 0.25)) { isExpanded.toggle() }
            }

            if canControl && isDimmable {
                LevelSlider(
                    value: store.level(of: group),
                    colors: colors,
                    label: "\(group.metadata.name) brightness"
                ) { level in
                    store.setBrightness(level, group: group)
                }
            }

            if isExpanded {
                let groupScenes = store.scenes(for: group)
                if !groupScenes.isEmpty {
                    FlowLayout(spacing: 6) {
                        ForEach(groupScenes) { scene in
                            SceneChip(scene: scene, colors: colors)
                        }
                    }
                }
                if !members.isEmpty {
                    VStack(spacing: 12) {
                        ForEach(members) { light in
                            LightRow(light: light)
                        }
                    }
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.primary.opacity(0.04))
                    )
                }
            }
        }
        .padding(12)
        .background(CardBackground(colors: colors, isOn: isOn, isHovering: isHovering))
        .onHover { isHovering = $0 }
        .animation(.snappy(duration: 0.3), value: colors)
    }

    private func subtitle(lit: Int, total: Int) -> String {
        if total == 0 { return "No lights" }
        if lit == 0 { return "Off" }
        if lit == total { return total == 1 ? "On" : "All \(total) on" }
        return "\(lit) of \(total) on"
    }
}

/// Card surface that picks up a soft tint and rim from the room's light colors.
private struct CardBackground: View {
    let colors: [Color]
    let isOn: Bool
    let isHovering: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
        let gradient = Theme.gradient(colors, from: .topLeading, to: .bottomTrailing)
        ZStack {
            shape.fill(Color.primary.opacity(isHovering ? 0.075 : 0.05))
            if isOn {
                shape.fill(gradient)
                    .opacity(0.16)
                shape.strokeBorder(gradient, lineWidth: 1)
                    .opacity(0.45)
            } else {
                shape.strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
            }
        }
    }
}

private struct SceneChip: View {
    @Environment(HueStore.self) private var store
    let scene: HueScene
    let colors: [Color]

    @State private var isHovering = false

    var body: some View {
        let isActive = (scene.status?.active ?? "inactive") != "inactive"
        Button {
            store.recall(scene)
        } label: {
            HStack(spacing: 4) {
                Ph(.sparkle, isActive ? .fill : .regular, size: 11)
                Text(scene.metadata.name)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
            }
            .foregroundStyle(isActive ? Theme.onLight : Color.primary)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(
                Capsule().fill(
                    isActive
                        ? AnyShapeStyle(Theme.gradient(colors))
                        : AnyShapeStyle(Color.primary.opacity(isHovering ? 0.12 : 0.07))
                )
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help("Activate \(scene.metadata.name)")
    }
}
