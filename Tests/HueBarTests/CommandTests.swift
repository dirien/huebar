import Foundation
import Testing

@testable import HueBar

struct CommandTests {
    private func json(_ value: some Encodable) throws -> String {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.outputFormatting = .sortedKeys
        return try #require(String(data: try encoder.encode(value), encoding: .utf8))
    }

    @Test func mergeKeepsLatestValuesAndOneColorMode() throws {
        var command = LightCommand(on: OnState(on: true), dimming: BrightnessValue(brightness: 30))
        command.merge(LightCommand(colorTemperature: MirekValue(mirek: 300)))
        command.merge(LightCommand(dimming: BrightnessValue(brightness: 55)))
        command.merge(LightCommand(color: XYValue(xy: XY(x: 0.2, y: 0.3))))
        #expect(
            try json(command) == #"{"color":{"xy":{"x":0.2,"y":0.3}},"dimming":{"brightness":55},"on":{"on":true}}"#)
    }

    @Test func encodesSnakeCaseAndOmitsNilFields() throws {
        #expect(
            try json(LightCommand(colorTemperature: MirekValue(mirek: 250))) == #"{"color_temperature":{"mirek":250}}"#)
        #expect(try json(SceneRecall()) == #"{"recall":{"action":"active"}}"#)
    }
}
