import Foundation
import Testing

@testable import HueBar

struct EventStreamTests {
    private func payloads(in stream: String) -> [String] {
        var lines = LineSplitter()
        var parser = EventStreamParser()
        var result: [String] = []
        for byte in Array(stream.utf8) {
            if let line = lines.push(byte), let payload = parser.feed(line) {
                result.append(payload)
            }
        }
        return result
    }

    @Test func framesEventsAcrossLineEndingsAndComments() {
        let stream = ": hi\n\nid: 1:0\r\ndata: [1]\r\n\r\nid: 2\ndata: [2,\ndata: 3]\n\n"
        #expect(payloads(in: stream) == ["[1]", "[2,\n3]"])
    }

    @Test func decodesDeltasOfDifferentShapes() throws {
        let json = """
            [{"creationtime": "2021-10-18T17:04:55Z", "id": "e1", "type": "update", "data": [
              {"id": "l1", "on": {"on": false}, "owner": {"rid": "d1", "rtype": "device"}, "type": "light"},
              {"id": "l1", "color_temperature": {"mirek": 366, "mirek_valid": true}, "type": "light"},
              {"id": "z1", "status": "connected", "type": "zigbee_connectivity"},
              {"id": "s1", "status": {"active": "inactive"}, "type": "scene"},
              {"id": "g1", "dimming": {"brightness": 12.5}, "type": "grouped_light"},
              {"type": "light"}
            ]}]
            """
        let events = try HueJSON.decoder.decode([HueEvent].self, from: Data(json.utf8))
        let deltas = try #require(events.first).data
        #expect(deltas.count == 5)
        #expect(deltas[0].on?.on == false)
        #expect(deltas[0].owner?.rid == "d1")
        #expect(deltas[1].colorTemperature?.mirek == 366)
        #expect(deltas[2].status == .text("connected"))
        #expect(deltas[3].status == .scene(SceneStatus(active: "inactive")))
        #expect(deltas[4].dimming?.brightness == 12.5)
    }
}
