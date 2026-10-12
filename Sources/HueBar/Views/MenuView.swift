import SwiftUI

struct MenuView: View {
    @Environment(HueStore.self) private var store
    @State private var showingSettings = false
    /// Lives here rather than in LightsView so expanded rooms survive a trip to Settings.
    @State private var expandedGroups: Set<String> = []

    var body: some View {
        VStack(spacing: 0) {
            content
            FooterView(showingSettings: $showingSettings)
        }
        .frame(width: 360)
        .onChange(of: store.phase) { _, phase in
            if phase == .setup {
                showingSettings = false
            }
        }
    }

    @ViewBuilder private var content: some View {
        if store.phase == .setup {
            SetupView()
        } else if showingSettings {
            SettingsView { showingSettings = false }
        } else {
            switch store.phase {
            case .ready:
                LightsView(expanded: $expandedGroups)
            case .failed(let message):
                FailureView(message: message)
            case .connecting, .setup:
                ConnectingView()
            }
        }
    }
}

private struct LightsView: View {
    @Environment(HueStore.self) private var store
    @Binding var expanded: Set<String>
    @State private var contentHeight: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            HeaderView()
            if let error = store.lastError {
                ErrorBanner(message: error)
            }
            Divider().opacity(0.6)
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    if !store.rooms.isEmpty {
                        SectionHeader(title: "Rooms", count: store.rooms.count)
                        ForEach(store.rooms) { room in
                            GroupCard(group: room, isExpanded: expansion(for: room.id))
                        }
                    }
                    if !store.zones.isEmpty {
                        SectionHeader(title: "Zones", count: store.zones.count)
                            .padding(.top, store.rooms.isEmpty ? 0 : 8)
                        ForEach(store.zones) { zone in
                            GroupCard(group: zone, isExpanded: expansion(for: zone.id))
                        }
                    }
                    if store.rooms.isEmpty && store.zones.isEmpty {
                        EmptyRoomsView()
                    }
                }
                .padding(12)
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.size.height
                } action: { height in
                    contentHeight = height
                }
            }
            // Size the scroll view to its content, up to a cap, so the menu is only as tall as it needs to be.
            .frame(height: min(max(contentHeight, 80), 540))
        }
    }

    private func expansion(for id: String) -> Binding<Bool> {
        Binding(
            get: { expanded.contains(id) },
            set: { isExpanded in
                if isExpanded {
                    expanded.insert(id)
                } else {
                    expanded.remove(id)
                }
            }
        )
    }
}

private struct HeaderView: View {
    @Environment(HueStore.self) private var store

    var body: some View {
        let lit = store.litLights
        let colors = Theme.colors(of: lit)

        HStack(spacing: 12) {
            GlowOrb(colors: colors, isOn: !lit.isEmpty)
            VStack(alignment: .leading, spacing: 3) {
                Text(store.bridgeName)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                HStack(spacing: 5) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 6, height: 6)
                    Text(store.summary)
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            PowerButton(isOn: !lit.isEmpty, colors: colors) {
                store.setAllOn(lit.isEmpty)
            }
            .disabled(store.homeGroupedLight == nil)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}

private struct PowerButton: View {
    let isOn: Bool
    let colors: [Color]
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        let title = isOn ? "Turn all lights off" : "Turn all lights on"
        Button(action: action) {
            Ph(.power, .bold, size: 15)
                .foregroundStyle(isOn ? Theme.onLight : (isHovering ? Color.primary : Color.secondary))
                .frame(width: 34, height: 34)
                .background(
                    Circle().fill(
                        isOn
                            ? AnyShapeStyle(Theme.gradient(colors, from: .topLeading, to: .bottomTrailing))
                            : AnyShapeStyle(Color.primary.opacity(isHovering ? 0.14 : 0.08))
                    )
                )
                .shadow(color: isOn ? (colors.first ?? Theme.amber).opacity(0.5) : Color.clear, radius: 8)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .animation(.snappy(duration: 0.2), value: isOn)
        .help(title)
        .accessibilityLabel(title)
    }
}

private struct SectionHeader: View {
    let title: String
    let count: Int

    var body: some View {
        HStack(spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .bold))
                .tracking(0.8)
            Text(verbatim: "\(count)")
                .font(.system(size: 9, weight: .bold).monospacedDigit())
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(Capsule().fill(Color.primary.opacity(0.08)))
        }
        .foregroundStyle(.secondary)
        .padding(.leading, 4)
        .padding(.bottom, 2)
    }
}

private struct ErrorBanner: View {
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Ph(.warning, .fill, size: 14)
                .foregroundStyle(.orange)
            Text(message)
                .font(.system(size: 11))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.orange.opacity(0.12)))
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
    }
}

private struct EmptyRoomsView: View {
    var body: some View {
        VStack(spacing: 8) {
            Ph(.squaresFour, .duotone, size: 30)
                .foregroundStyle(.secondary)
            Text("No rooms yet. Create rooms in the Hue app and they'll show up here.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }
}

private struct ConnectingView: View {
    @Environment(HueStore.self) private var store

    var body: some View {
        VStack(spacing: 14) {
            Ph(.plugsConnected, .duotone, size: 36)
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Connecting to \(store.bridgeName)…")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
    }
}

private struct FailureView: View {
    @Environment(HueStore.self) private var store
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.orange.opacity(0.14))
                Ph(.plugs, .duotone, size: 28)
                    .foregroundStyle(.orange)
            }
            .frame(width: 56, height: 56)
            Text("Can't reach the bridge")
                .font(.system(size: 14, weight: .semibold))
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Text("HueBar keeps retrying in the background.")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
            AccentButton(title: "Retry now", icon: .arrowsClockwise) {
                store.reconnect()
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(20)
    }
}

private struct FooterView: View {
    @Environment(HueStore.self) private var store
    @Binding var showingSettings: Bool

    var body: some View {
        HStack(spacing: 2) {
            if store.settings != nil {
                IconButton(
                    icon: .gearSix,
                    weight: showingSettings ? .duotone : .regular,
                    isActive: showingSettings,
                    help: "Settings"
                ) {
                    withAnimation(.snappy(duration: 0.2)) { showingSettings.toggle() }
                }
                IconButton(icon: .arrowsClockwise, help: "Reload from bridge") {
                    store.reconnect()
                }
            }
            Spacer()
            QuitButton()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color.primary.opacity(0.03))
        .overlay(alignment: .top) {
            Divider().opacity(0.6)
        }
    }
}

private struct QuitButton: View {
    @State private var isHovering = false

    var body: some View {
        Button {
            NSApplication.shared.terminate(nil)
        } label: {
            HStack(spacing: 5) {
                Ph(.signOut, size: 13)
                Text("Quit")
                    .font(.system(size: 12))
            }
            .foregroundStyle(isHovering ? Color.primary : Color.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.primary.opacity(isHovering ? 0.1 : 0))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .keyboardShortcut("q")
        .onHover { isHovering = $0 }
        .help("Quit HueBar")
    }
}
