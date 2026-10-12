import AppKit
import Observation
import ServiceManagement
import SystemConfiguration

@MainActor
@Observable
final class HueStore {
    enum Phase: Equatable {
        case setup
        case connecting
        case ready
        case failed(String)
    }

    enum PairingState: Equatable {
        case idle
        case contacting
        /// `bridgeId` is the last six characters of the bridge id, as shown in its Bonjour name and on its label.
        case waitingForButton(bridgeId: String, secondsLeft: Int)
        case failed(String)
    }

    private(set) var phase: Phase = .setup
    private(set) var pairing: PairingState = .idle
    private(set) var settings: BridgeSettings?
    private(set) var lastError: String?
    private(set) var launchAtLogin = SMAppService.mainApp.status == .enabled

    private(set) var lights: [String: Light] = [:]
    private(set) var devices: [String: Device] = [:]
    private(set) var rooms: [HueGroup] = []
    private(set) var zones: [HueGroup] = []
    private(set) var groupedLights: [String: GroupedLight] = [:]
    private(set) var scenes: [HueScene] = []
    /// Device id → zigbee status.
    private(set) var connectivity: [String: String] = [:]

    let discovery = BridgeDiscovery()

    private struct WriteKey: Hashable {
        let type: String
        let id: String
    }

    @ObservationIgnored private var client: HueClient?
    @ObservationIgnored private var zigbeeOwners: [String: String] = [:]
    @ObservationIgnored private var streamTask: Task<Void, Never>?
    @ObservationIgnored private var resyncTask: Task<Void, Never>?
    @ObservationIgnored private var pendingWrites: [WriteKey: LightCommand] = [:]
    @ObservationIgnored private var activeWriters: Set<WriteKey> = []
    @ObservationIgnored private var isRelocating = false
    @ObservationIgnored private var wakeObserver: NSObjectProtocol?

    init() {
        if let saved = BridgeSettings.load(), let key = Keychain.read(account: saved.bridgeId) {
            settings = saved
            client = HueClient(host: saved.host, appKey: key, pinnedFingerprint: saved.certificateSHA256)
            phase = .connecting
            Task { await connect() }
        }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                // Give Wi-Fi a moment to come back before reconnecting.
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                self?.reconnect()
            }
        }
    }

    // MARK: - Derived state

    var bridgeName: String { settings?.name ?? "Hue Bridge" }

    var homeGroupedLight: GroupedLight? {
        groupedLights.values.first { $0.owner.rtype == "bridge_home" }
    }

    var anyLightOn: Bool {
        lights.values.contains { $0.on.on && isReachable($0) }
    }

    /// Lights that are on and reachable, sorted by name.
    var litLights: [Light] {
        lights.values
            .filter { $0.on.on && isReachable($0) }
            .sorted { name(of: $0).localizedStandardCompare(name(of: $1)) == .orderedAscending }
    }

    var isConnected: Bool { phase == .ready }

    var summary: String {
        let reachable = lights.values.filter { isReachable($0) }
        let on = reachable.filter(\.on.on).count
        if reachable.isEmpty { return "No lights" }
        if on == 0 { return "All \(reachable.count) lights off" }
        if on == reachable.count { return "All \(on) lights on" }
        return "\(on) of \(reachable.count) lights on"
    }

    func name(of light: Light) -> String {
        // Renaming a light in the Hue app renames its device; prefer that when the device has a single light.
        if let device = devices[light.owner.rid], device.services.filter({ $0.rtype == "light" }).count == 1 {
            return device.metadata.name
        }
        return light.metadata?.name ?? "Light"
    }

    func archetype(of light: Light) -> String? {
        light.metadata?.archetype ?? devices[light.owner.rid]?.metadata.archetype
    }

    func isReachable(_ light: Light) -> Bool {
        switch connectivity[light.owner.rid] {
        case "disconnected"?, "connectivity_issue"?: false
        default: true
        }
    }

    func lights(in group: HueGroup) -> [Light] {
        var ids: [String] = []
        for child in group.children {
            switch child.rtype {
            case "light":
                ids.append(child.rid)
            case "device":
                ids += devices[child.rid]?.services.filter { $0.rtype == "light" }.map(\.rid) ?? []
            default:
                break
            }
        }
        return ids.compactMap { lights[$0] }
            .sorted { name(of: $0).localizedStandardCompare(name(of: $1)) == .orderedAscending }
    }

    func groupedLight(for group: HueGroup) -> GroupedLight? {
        group.services.first { $0.rtype == "grouped_light" }.flatMap { groupedLights[$0.rid] }
    }

    func scenes(for group: HueGroup) -> [HueScene] {
        scenes.filter { $0.group.rid == group.id }
    }

    /// Brightness shown for a light: 0 while it's off.
    func level(of light: Light) -> Double {
        light.on.on ? light.dimming?.brightness ?? 100 : 0
    }

    /// Brightness shown for a room or zone: the average of its lit lights, or 0 when they're all off.
    /// Derived from the lights rather than the grouped_light resource, whose events lag behind group writes.
    func level(of group: HueGroup) -> Double {
        let lit = lights(in: group).filter { $0.on.on && isReachable($0) }
        guard !lit.isEmpty else { return 0 }
        return lit.map { $0.dimming?.brightness ?? 100 }.reduce(0, +) / Double(lit.count)
    }

}

// MARK: - Light control

extension HueStore {
    func setOn(_ on: Bool, light id: String) {
        lights[id]?.on.on = on
        send(LightCommand(on: OnState(on: on)), to: WriteKey(type: "light", id: id))
    }

    /// Sets brightness from a slider; dragging to 0 turns the light off.
    func setBrightness(_ brightness: Double, light id: String) {
        guard brightness >= 1 else {
            setOn(false, light: id)
            return
        }
        lights[id]?.on.on = true
        lights[id]?.dimming?.brightness = brightness
        send(
            LightCommand(on: OnState(on: true), dimming: BrightnessValue(brightness: brightness)),
            to: WriteKey(type: "light", id: id)
        )
    }

    func setColor(_ rgb: RGB, light id: String) {
        guard let light = lights[id] else { return }
        var xy = ColorMath.xy(from: rgb)
        if let gamut = light.color?.gamut {
            xy = ColorMath.clamp(xy, to: gamut)
        }
        lights[id]?.on.on = true
        lights[id]?.color?.xy = xy
        lights[id]?.colorTemperature?.mirek = nil
        lights[id]?.colorTemperature?.mirekValid = false
        send(LightCommand(on: OnState(on: true), color: XYValue(xy: xy)), to: WriteKey(type: "light", id: id))
    }

    func setMirek(_ mirek: Int, light id: String) {
        guard let light = lights[id] else { return }
        var value = mirek
        if let schema = light.colorTemperature?.mirekSchema {
            value = min(max(value, schema.mirekMinimum), schema.mirekMaximum)
        }
        lights[id]?.on.on = true
        lights[id]?.colorTemperature?.mirek = value
        lights[id]?.colorTemperature?.mirekValid = true
        send(
            LightCommand(on: OnState(on: true), colorTemperature: MirekValue(mirek: value)),
            to: WriteKey(type: "light", id: id)
        )
    }

    func setOn(_ on: Bool, group: HueGroup) {
        guard let grouped = groupedLight(for: group) else { return }
        groupedLights[grouped.id]?.on = OnState(on: on)
        for light in lights(in: group) {
            lights[light.id]?.on.on = on
        }
        send(LightCommand(on: OnState(on: on)), to: WriteKey(type: "grouped_light", id: grouped.id))
    }

    /// Sets every light in the group to one brightness; dragging to 0 turns the group off.
    func setBrightness(_ brightness: Double, group: HueGroup) {
        guard brightness >= 1 else {
            setOn(false, group: group)
            return
        }
        guard let grouped = groupedLight(for: group) else { return }
        for light in lights(in: group) where isReachable(light) {
            lights[light.id]?.on.on = true
            lights[light.id]?.dimming?.brightness = brightness
        }
        groupedLights[grouped.id]?.on = OnState(on: true)
        groupedLights[grouped.id]?.dimming = Dimming(brightness: brightness, minDimLevel: grouped.dimming?.minDimLevel)
        send(
            LightCommand(on: OnState(on: true), dimming: BrightnessValue(brightness: brightness)),
            to: WriteKey(type: "grouped_light", id: grouped.id)
        )
    }

    func setAllOn(_ on: Bool) {
        guard let home = homeGroupedLight else { return }
        for id in lights.keys {
            lights[id]?.on.on = on
        }
        for id in groupedLights.keys {
            groupedLights[id]?.on = OnState(on: on)
        }
        send(LightCommand(on: OnState(on: on)), to: WriteKey(type: "grouped_light", id: home.id))
    }

    func recall(_ scene: HueScene) {
        for index in scenes.indices where scenes[index].group == scene.group {
            scenes[index].status = SceneStatus(active: scenes[index].id == scene.id ? "static" : "inactive")
        }
        Task {
            do {
                try await client?.update("scene", id: scene.id, SceneRecall())
                lastError = nil
            } catch {
                lastError = error.localizedDescription
            }
        }
    }

    /// Coalesces writes per resource so slider drags don't flood the bridge
    /// (it handles roughly 10 light commands and 1 group command per second).
    private func send(_ command: LightCommand, to key: WriteKey) {
        if var pending = pendingWrites[key] {
            pending.merge(command)
            pendingWrites[key] = pending
        } else {
            pendingWrites[key] = command
        }
        guard !activeWriters.contains(key) else { return }
        activeWriters.insert(key)
        Task { await drain(key) }
    }

    private func drain(_ key: WriteKey) async {
        let spacing: UInt64 = key.type == "grouped_light" ? 350_000_000 : 120_000_000
        while let command = pendingWrites.removeValue(forKey: key), let client {
            do {
                try await client.update(key.type, id: key.id, command)
                lastError = nil
            } catch {
                lastError = error.localizedDescription
            }
            try? await Task.sleep(nanoseconds: spacing)
        }
        activeWriters.remove(key)
    }

}

// MARK: - Pairing

extension HueStore {
    func pair(host rawHost: String) async {
        let host = rawHost.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty else { return }
        pairing = .contacting

        let probe = HueClient(host: host, appKey: nil, pinnedFingerprint: nil)
        let config: BridgeConfig
        do {
            config = try await probe.config()
        } catch {
            pairing =
                Task.isCancelled ? .idle : .failed("No Hue Bridge answered at \(host). \(error.localizedDescription)")
            return
        }
        guard let fingerprint = probe.pinner.observedFingerprint else {
            pairing = .failed("The bridge at \(host) didn't present a certificate.")
            return
        }
        probe.pinner.pin(fingerprint)

        let shortId = String(config.bridgeid.suffix(6)).uppercased()
        // The bridge accepts pairing for 30 s after its button is pressed; give people time to walk to it first.
        let deadline = Date().addingTimeInterval(90)
        while Date() < deadline {
            if Task.isCancelled {
                pairing = .idle
                return
            }
            pairing = .waitingForButton(
                bridgeId: shortId,
                secondsLeft: max(Int(deadline.timeIntervalSinceNow.rounded()), 0)
            )
            do {
                let appKey = try await probe.register(deviceType: Self.deviceType)
                let paired = BridgeSettings(
                    host: host,
                    bridgeId: config.bridgeid.lowercased(),
                    name: config.name,
                    certificateSHA256: fingerprint
                )
                try Keychain.save(appKey, account: paired.bridgeId)
                paired.save()
                settings = paired
                client = HueClient(host: host, appKey: appKey, pinnedFingerprint: fingerprint)
                pairing = .idle
                await connect()
                return
            } catch HueClientError.linkButtonNotPressed {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            } catch {
                pairing = Task.isCancelled ? .idle : .failed(error.localizedDescription)
                return
            }
        }
        pairing = .failed(
            "Bridge \(shortId) never reported its link button pressed. Make sure you press the button on the bridge "
                + "whose label ends in \(shortId), then click Pair again."
        )
    }

    /// v1 devicetype format: "<app, ≤20 chars>#<device, ≤19 chars>".
    private static var deviceType: String {
        let computer = (SCDynamicStoreCopyComputerName(nil, nil) as String?) ?? "Mac"
        return "HueBar#" + String(computer.prefix(19))
    }

    func forgetBridge(message: String? = nil) {
        streamTask?.cancel()
        resyncTask?.cancel()
        if let settings {
            Keychain.delete(account: settings.bridgeId)
        }
        BridgeSettings.clear()
        settings = nil
        client = nil
        lights = [:]
        devices = [:]
        rooms = []
        zones = []
        groupedLights = [:]
        scenes = []
        connectivity = [:]
        zigbeeOwners = [:]
        pendingWrites = [:]
        lastError = nil
        phase = .setup
        if let message {
            pairing = .failed(message)
        } else {
            pairing = .idle
        }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            lastError = "Couldn't change the login item: \(error.localizedDescription)"
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

}

// MARK: - Connection

extension HueStore {
    func reconnect() {
        streamTask?.cancel()
        Task { await connect() }
    }

    private func connect() async {
        guard client != nil else {
            phase = .setup
            return
        }
        if lights.isEmpty { phase = .connecting }
        if await resync() {
            startEventStream()
        }
    }

    /// Reloads everything. Returns false when retrying is pointless (pairing revoked, certificate changed).
    @discardableResult
    private func resync() async -> Bool {
        do {
            try await loadAll()
            phase = .ready
            return true
        } catch {
            if Task.isCancelled { return false }
            return await recover(from: error)
        }
    }

    private func recover(from error: Error) async -> Bool {
        switch error as? HueClientError {
        case .unauthorized?:
            forgetBridge(message: "The bridge no longer accepts HueBar's app key. Pair again.")
            return false
        case .certificateMismatch?:
            streamTask?.cancel()
            phase = .failed(
                "The bridge presented a different certificate than when it was paired. "
                    + "If you reset or replaced it, forget it in Settings and pair again."
            )
            return false
        default:
            if await relocateBridge() {
                do {
                    try await loadAll()
                    phase = .ready
                    return true
                } catch {}
            }
            phase = .failed("Can't reach the bridge at \(settings?.host ?? "?"). \(error.localizedDescription)")
            return true
        }
    }

    /// If the bridge stopped answering, it may have a new DHCP address; look it up by id via Bonjour.
    private func relocateBridge() async -> Bool {
        guard var current = settings, let appKey = client?.appKey, !isRelocating else { return false }
        isRelocating = true
        defer { isRelocating = false }
        guard let found = await discovery.find(bridgeId: current.bridgeId), found.host != current.host else {
            return false
        }
        current.host = found.host
        current.save()
        settings = current
        client = HueClient(host: found.host, appKey: appKey, pinnedFingerprint: current.certificateSHA256)
        return true
    }

    private func loadAll() async throws {
        guard let client else { return }
        async let fetchedLights = client.resources("light", as: Light.self)
        async let fetchedDevices = client.resources("device", as: Device.self)
        async let fetchedRooms = client.resources("room", as: HueGroup.self)
        async let fetchedZones = client.resources("zone", as: HueGroup.self)
        async let fetchedGrouped = client.resources("grouped_light", as: GroupedLight.self)
        async let fetchedScenes = client.resources("scene", as: HueScene.self)
        async let fetchedZigbee = client.resources("zigbee_connectivity", as: ZigbeeConnectivity.self)
        let result = try await (
            fetchedLights, fetchedDevices, fetchedRooms, fetchedZones, fetchedGrouped, fetchedScenes, fetchedZigbee
        )

        func byName(_ a: HueGroup, _ b: HueGroup) -> Bool {
            a.metadata.name.localizedStandardCompare(b.metadata.name) == .orderedAscending
        }
        lights = Self.index(result.0)
        devices = Self.index(result.1)
        rooms = result.2.sorted(by: byName)
        zones = result.3.sorted(by: byName)
        groupedLights = Self.index(result.4)
        scenes = result.5.sorted { $0.metadata.name.localizedStandardCompare($1.metadata.name) == .orderedAscending }
        connectivity = Dictionary(result.6.map { ($0.owner.rid, $0.status) }, uniquingKeysWith: { first, _ in first })
        zigbeeOwners = Dictionary(result.6.map { ($0.id, $0.owner.rid) }, uniquingKeysWith: { first, _ in first })
        lastError = nil
    }

    private static func index<T: Identifiable>(_ items: [T]) -> [T.ID: T] {
        Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

}

// MARK: - Event stream

extension HueStore {
    private func startEventStream() {
        streamTask?.cancel()
        streamTask = Task { [weak self] in
            var delay: UInt64 = 2
            while !Task.isCancelled, let client = self?.client {
                do {
                    try await client.streamEvents { events in
                        delay = 2
                        self?.apply(events)
                    }
                } catch {}
                if Task.isCancelled { return }
                // The stream dropped: back off, then reload so nothing missed in between is lost.
                try? await Task.sleep(nanoseconds: delay * 1_000_000_000)
                delay = min(delay * 2, 60)
                guard let store = self, !Task.isCancelled else { return }
                let shouldContinue = await store.resync()
                if !shouldContinue { return }
            }
        }
    }

    private func apply(_ events: [HueEvent]) {
        var needsResync = false
        for event in events {
            switch event.type {
            case "update":
                let needsReload = event.data.map { apply($0) }
                if needsReload.contains(true) { needsResync = true }
            case "add", "delete":
                needsResync = true
            default:
                break
            }
        }
        if needsResync { scheduleResync() }
    }

    /// Applies a partial update. Returns true when the change needs a full reload.
    private func apply(_ delta: ResourceDelta) -> Bool {
        switch delta.type {
        case "light":
            return applyLight(delta)
        case "grouped_light":
            return applyGroupedLight(delta)
        case "scene":
            return applyScene(delta)
        case "zigbee_connectivity":
            if case .text(let status)? = delta.status, let deviceId = zigbeeOwners[delta.id] {
                connectivity[deviceId] = status
            }
            return false
        case "room", "zone":
            return true
        case "device":
            return delta.metadata != nil
        default:
            return false
        }
    }

    private func applyLight(_ delta: ResourceDelta) -> Bool {
        guard var light = lights[delta.id] else { return true }
        // While we're still sending values for this light, our optimistic state is newer.
        guard !activeWriters.contains(WriteKey(type: "light", id: delta.id)) else { return false }
        if let on = delta.on { light.on = on }
        if let dimming = delta.dimming { light.dimming?.brightness = dimming.brightness }
        if let temperature = delta.colorTemperature {
            light.colorTemperature?.mirek = temperature.mirek
            light.colorTemperature?.mirekValid = temperature.mirekValid ?? (temperature.mirek != nil)
        }
        if let color = delta.color { light.color?.xy = color.xy }
        if let name = delta.metadata?.name { light.metadata?.name = name }
        lights[delta.id] = light
        return false
    }

    private func applyGroupedLight(_ delta: ResourceDelta) -> Bool {
        guard var grouped = groupedLights[delta.id] else { return true }
        guard !activeWriters.contains(WriteKey(type: "grouped_light", id: delta.id)) else { return false }
        if let on = delta.on { grouped.on = on }
        if let dimming = delta.dimming {
            grouped.dimming = Dimming(brightness: dimming.brightness, minDimLevel: grouped.dimming?.minDimLevel)
        }
        groupedLights[delta.id] = grouped
        return false
    }

    private func applyScene(_ delta: ResourceDelta) -> Bool {
        guard let index = scenes.firstIndex(where: { $0.id == delta.id }) else { return true }
        if case .scene(let status)? = delta.status { scenes[index].status = status }
        if let name = delta.metadata?.name { scenes[index].metadata.name = name }
        return false
    }

    private func scheduleResync() {
        resyncTask?.cancel()
        resyncTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
            await self?.resync()
        }
    }
}
