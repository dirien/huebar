import SwiftUI

struct SettingsView: View {
    @Environment(HueStore.self) private var store
    let close: () -> Void

    @State private var confirmingForget = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                IconButton(icon: .caretLeft, weight: .bold, size: 26, help: "Back", action: close)
                Text("Settings")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
            }

            if let settings = store.settings {
                Card {
                    HStack(spacing: 10) {
                        IconTile(icon: .plugsConnected, colors: [], isOn: store.isConnected, size: 32)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(settings.name)
                                .font(.system(size: 13, weight: .semibold))
                            HStack(spacing: 5) {
                                Circle()
                                    .fill(store.isConnected ? Color.green : Color.orange)
                                    .frame(width: 6, height: 6)
                                Text(store.isConnected ? "Connected" : "Not connected")
                            }
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    Divider().opacity(0.6)
                    InfoRow(label: "IP address", value: settings.host)
                    InfoRow(label: "Bridge ID", value: settings.bridgeId.uppercased())
                }
            }

            Card {
                HStack(spacing: 10) {
                    Ph(.rocketLaunch, size: 16)
                        .foregroundStyle(.secondary)
                    Text("Launch at login")
                        .font(.system(size: 12))
                    Spacer()
                    PillToggle(isOn: store.launchAtLogin, width: 32, label: "Launch at login") { enabled in
                        store.setLaunchAtLogin(enabled)
                    }
                }
            }

            Card {
                if confirmingForget {
                    Text("HueBar will delete its app key. You'll need to press the link button to pair again.")
                        .font(.system(size: 12))
                        .fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Spacer()
                        Button("Cancel") { confirmingForget = false }
                            .buttonStyle(.borderless)
                        Button {
                            store.forgetBridge()
                        } label: {
                            Text("Forget Bridge")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Color.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Capsule().fill(Color.red))
                        }
                        .buttonStyle(.plain)
                    }
                } else {
                    Button {
                        withAnimation(.snappy(duration: 0.2)) { confirmingForget = true }
                    } label: {
                        HStack(spacing: 10) {
                            Ph(.trash, size: 16)
                            Text("Forget this bridge…")
                                .font(.system(size: 12))
                            Spacer()
                        }
                        .foregroundStyle(.red)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(14)
    }
}

private struct Card<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            content
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06))
        )
    }
}

private struct InfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .monospacedDigit()
                .textSelection(.enabled)
        }
        .font(.system(size: 12))
    }
}
