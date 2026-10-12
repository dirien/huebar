import SwiftUI

struct SetupView: View {
    @Environment(HueStore.self) private var store
    @AppStorage("setupHost") private var host = ""
    @State private var pairTask: Task<Void, Never>?

    private var isPairing: Bool {
        switch store.pairing {
        case .contacting, .waitingForButton: true
        case .idle, .failed: false
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                GlowOrb(colors: [], isOn: true, icon: .lightbulbFilament, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Connect your Hue Bridge")
                        .font(.system(size: 14, weight: .semibold))
                    Text("HueBar talks to the bridge directly on your network.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }

            discoveredBridges

            VStack(alignment: .leading, spacing: 6) {
                FieldLabel(title: "IP address")
                TextField("192.168.1.2", text: $host)
                    .textFieldStyle(.roundedBorder)
                    .disabled(isPairing)
                    .onSubmit { startPairing() }
            }

            HStack(spacing: 8) {
                Ph(.lightbulbFilament, .duotone, size: 16)
                    .foregroundStyle(Theme.amber)
                Text("Click **Pair**, then press the round link button on top of the bridge.")
                    .font(.system(size: 12))
                    .fixedSize(horizontal: false, vertical: true)
            }

            pairingStatus

            HStack(spacing: 10) {
                Spacer()
                if isPairing {
                    Button("Cancel") { pairTask?.cancel() }
                        .buttonStyle(.borderless)
                }
                AccentButton(title: "Pair", icon: .link) { startPairing() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(isPairing || host.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(16)
        .onAppear {
            if store.discovery.bridges.isEmpty && !store.discovery.isSearching {
                store.discovery.start()
            }
        }
        .onChange(of: store.discovery.bridges) { _, bridges in
            if bridges.count == 1, !isPairing {
                host = bridges[0].host
            }
        }
    }

    private var discoveredBridges: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                FieldLabel(title: "Bridges on this network")
                Spacer()
                if store.discovery.isSearching {
                    ProgressView()
                        .controlSize(.mini)
                } else {
                    IconButton(icon: .magnifyingGlass, size: 22, help: "Search again") {
                        store.discovery.start()
                    }
                }
            }
            if store.discovery.bridges.isEmpty && !store.discovery.isSearching {
                Text("None found via Bonjour. Enter the bridge's IP address below.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            ForEach(store.discovery.bridges) { bridge in
                BridgeRow(bridge: bridge, isSelected: host == bridge.host) {
                    host = bridge.host
                }
                .disabled(isPairing)
            }
        }
    }

    @ViewBuilder private var pairingStatus: some View {
        switch store.pairing {
        case .idle:
            EmptyView()
        case .contacting:
            StatusLine {
                ProgressView().controlSize(.small)
            } text: {
                Text("Contacting the bridge…")
            }
        case .waitingForButton(let bridgeId, let secondsLeft):
            StatusLine {
                ProgressView().controlSize(.small)
            } text: {
                Text("Now press the link button on bridge **\(bridgeId)**… \(secondsLeft)s")
            }
        case .failed(let message):
            StatusLine {
                Ph(.warning, .fill, size: 14).foregroundStyle(.orange)
            } text: {
                Text(message)
            }
        }
    }

    private func startPairing() {
        // Return can trigger both onSubmit and the default button; only start one pairing attempt.
        guard !isPairing, pairTask == nil else { return }
        let target = host
        pairTask = Task {
            await store.pair(host: target)
            pairTask = nil
        }
    }
}

private struct BridgeRow: View {
    let bridge: DiscoveredBridge
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        Button(action: action) {
            HStack(spacing: 10) {
                Ph(isSelected ? .checkCircle : .circle, isSelected ? .fill : .regular, size: 16)
                    .foregroundStyle(isSelected ? Theme.amber : Color.secondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(bridge.name)
                        .font(.system(size: 12, weight: .medium))
                    Text(bridge.host)
                        .font(.system(size: 11).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(10)
            .background(shape.fill(Color.primary.opacity(isSelected || isHovering ? 0.08 : 0.04)))
            .overlay(shape.strokeBorder(isSelected ? Theme.amber.opacity(0.6) : Color.primary.opacity(0.06)))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

private struct FieldLabel: View {
    let title: String

    var body: some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .bold))
            .tracking(0.8)
            .foregroundStyle(.secondary)
    }
}

private struct StatusLine<Icon: View, Message: View>: View {
    @ViewBuilder let icon: Icon
    @ViewBuilder let text: Message

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            icon
            text
                .font(.system(size: 12))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
    }
}
