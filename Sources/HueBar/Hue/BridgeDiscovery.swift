import Foundation
import Network
import Observation

struct DiscoveredBridge: Identifiable, Hashable, Sendable {
    /// Lowercase bridge id, e.g. "ecb5fafffe11ddf3".
    let id: String
    let name: String
    let host: String
}

/// Finds bridges on the LAN via Bonjour (`_hue._tcp`) and resolves them to IPv4 addresses.
@MainActor
@Observable
final class BridgeDiscovery {
    private(set) var bridges: [DiscoveredBridge] = []
    private(set) var isSearching = false

    @ObservationIgnored private var browser: NWBrowser?
    @ObservationIgnored private var resolvers: [String: NWConnection] = [:]
    @ObservationIgnored private var generation = 0

    func start(timeout: TimeInterval = 8) {
        stop()
        generation += 1
        let current = generation
        bridges = []
        isSearching = true

        let browser = NWBrowser(for: .bonjourWithTXTRecord(type: "_hue._tcp", domain: nil), using: .tcp)
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            Task { @MainActor in self?.handle(results) }
        }
        browser.stateUpdateHandler = { [weak self] state in
            if case .failed = state {
                Task { @MainActor in self?.stop() }
            }
        }
        browser.start(queue: .main)
        self.browser = browser

        Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            guard let self, self.generation == current else { return }
            self.stop()
        }
    }

    func stop() {
        browser?.cancel()
        browser = nil
        for resolver in resolvers.values {
            resolver.cancel()
        }
        resolvers = [:]
        isSearching = false
    }

    /// Browses until the bridge with the given id shows up, e.g. after DHCP handed it a new address.
    func find(bridgeId: String, timeout: TimeInterval = 6) async -> DiscoveredBridge? {
        let id = bridgeId.lowercased()
        start(timeout: timeout)
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline, !Task.isCancelled {
            if let bridge = bridges.first(where: { $0.id == id }) { return bridge }
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
        return nil
    }

    private func handle(_ results: Set<NWBrowser.Result>) {
        for result in results {
            guard case .service(let name, _, _, _) = result.endpoint else { continue }
            var bridgeId = name
            if case .bonjour(let txt) = result.metadata, let id = txt["bridgeid"] {
                bridgeId = id
            }
            let id = bridgeId.lowercased()
            guard resolvers[id] == nil, !bridges.contains(where: { $0.id == id }) else { continue }
            resolve(result.endpoint, id: id, name: name)
        }
    }

    private func resolve(_ endpoint: NWEndpoint, id: String, name: String) {
        let parameters = NWParameters.tcp
        if let ip = parameters.defaultProtocolStack.internetProtocol as? NWProtocolIP.Options {
            ip.version = .v4
        }
        let connection = NWConnection(to: endpoint, using: parameters)
        resolvers[id] = connection
        connection.stateUpdateHandler = { [weak self, weak connection] state in
            guard let connection else { return }
            switch state {
            case .ready:
                let host = connection.currentPath?.remoteEndpoint.flatMap(Self.ipv4String)
                connection.cancel()
                Task { @MainActor in self?.resolved(id: id, name: name, host: host) }
            case .failed, .waiting:
                connection.cancel()
                Task { @MainActor in self?.resolved(id: id, name: name, host: nil) }
            default:
                break
            }
        }
        connection.start(queue: .main)
    }

    private func resolved(id: String, name: String, host: String?) {
        resolvers[id] = nil
        guard let host, !bridges.contains(where: { $0.id == id }) else { return }
        bridges.append(DiscoveredBridge(id: id, name: name, host: host))
    }

    nonisolated private static func ipv4String(_ endpoint: NWEndpoint) -> String? {
        guard case .hostPort(let host, _) = endpoint, case .ipv4(let address) = host else { return nil }
        return address.rawValue.map { String($0) }.joined(separator: ".")
    }
}
