import Foundation
import Testing

@testable import HueBar

/// Fixtures follow the Hue CLIP v2 response shapes.
struct ModelDecodingTests {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> [T] {
        try HueJSON.decoder.decode(HueEnvelope<T>.self, from: Data(json.utf8)).data
    }

    @Test func lightsDecodeAndSkipMalformedItems() throws {
        let lights = try decode(
            Light.self,
            """
            {"errors": [], "data": [
              {"id": "l1", "id_v1": "/lights/1", "owner": {"rid": "d1", "rtype": "device"},
               "metadata": {"name": "Desk", "archetype": "sultan_bulb"}, "on": {"on": true},
               "dimming": {"brightness": 63.5, "min_dim_level": 0.2},
               "color_temperature": {"mirek": null, "mirek_valid": false,
                                     "mirek_schema": {"mirek_minimum": 153, "mirek_maximum": 500}},
               "color": {"xy": {"x": 0.6915, "y": 0.3083},
                         "gamut": {"red": {"x": 0.6915, "y": 0.3083}, "green": {"x": 0.17, "y": 0.7},
                                   "blue": {"x": 0.1532, "y": 0.0475}}, "gamut_type": "C"},
               "mode": "normal", "type": "light"},
              {"id": "l2", "owner": {"rid": "d2", "rtype": "device"},
               "metadata": {"name": "Plug", "archetype": "plug"}, "on": {"on": false}, "type": "light"},
              {"id": "broken", "type": "light"}
            ]}
            """
        )
        #expect(lights.map(\.id) == ["l1", "l2"])
        let desk = try #require(lights.first)
        #expect(desk.dimming?.minDimLevel == 0.2)
        #expect(desk.colorTemperature?.mirekSchema?.mirekMaximum == 500)
        #expect(!desk.isInColorTemperatureMode)
        #expect(desk.displayRGB.r > 0.95 && desk.displayRGB.g < 0.3)
        #expect(lights[1].dimming == nil)
    }

    @Test func groupsScenesAndConnectivityDecode() throws {
        let rooms = try decode(
            HueGroup.self,
            """
            {"errors": [], "data": [{"id": "r1", "type": "room",
              "children": [{"rid": "d1", "rtype": "device"}],
              "services": [{"rid": "g1", "rtype": "grouped_light"}],
              "metadata": {"name": "Office", "archetype": "office"}}]}
            """
        )
        #expect(rooms.first?.services.first?.rtype == "grouped_light")

        let grouped = try decode(
            GroupedLight.self,
            """
            {"errors": [], "data": [{"id": "g0", "type": "grouped_light",
              "owner": {"rid": "b", "rtype": "bridge_home"}, "on": {"on": true}}]}
            """
        )
        #expect(grouped.first?.owner.rtype == "bridge_home")

        let scenes = try decode(
            HueScene.self,
            """
            {"errors": [], "data": [{"id": "s1", "type": "scene", "actions": [],
              "metadata": {"name": "Concentrate", "image": {"rid": "x", "rtype": "public_image"}},
              "group": {"rid": "r1", "rtype": "room"}, "status": {"active": "static"}}]}
            """
        )
        #expect(scenes.first?.status?.active == "static")

        let zigbee = try decode(
            ZigbeeConnectivity.self,
            """
            {"errors": [], "data": [{"id": "z1", "type": "zigbee_connectivity",
              "owner": {"rid": "d1", "rtype": "device"}, "status": "connectivity_issue"}]}
            """
        )
        #expect(zigbee.first?.status == "connectivity_issue")
    }

    @Test func bridgeConfigDecodes() throws {
        let json = #"{"name":"Philips hue","swversion":"1967054020","bridgeid":"ECB5FAFFFE11DDF3","modelid":"BSB002"}"#
        let config = try JSONDecoder().decode(BridgeConfig.self, from: Data(json.utf8))
        #expect(config.bridgeid == "ECB5FAFFFE11DDF3")
    }

    @Test func errorEnvelopeKeepsErrorsAndData() throws {
        let json = """
            {"errors": [{"description": "device (light) has communication issues"}],
             "data": [{"rid": "l1", "rtype": "light"}]}
            """
        let envelope = try HueJSON.decoder.decode(HueEnvelope<ResourceRef>.self, from: Data(json.utf8))
        #expect(envelope.errors.count == 1)
        #expect(envelope.data.count == 1)
    }

    @Test func pairingResponsesDecode() throws {
        let success = try JSONDecoder().decode(
            [PairResponseItem].self,
            from: Data(#"[{"success":{"username":"abc","clientkey":"DEF"}}]"#.utf8)
        )
        #expect(success.first?.success?.username == "abc")

        let notPressed = try JSONDecoder().decode(
            [PairResponseItem].self,
            from: Data(#"[{"error":{"type":101,"address":"","description":"link button not pressed"}}]"#.utf8)
        )
        #expect(notPressed.first?.error?.type == 101)
    }
}
