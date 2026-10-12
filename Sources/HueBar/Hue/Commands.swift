import Foundation

struct BrightnessValue: Encodable, Equatable, Sendable {
    var brightness: Double
}

struct MirekValue: Encodable, Equatable, Sendable {
    var mirek: Int
}

struct XYValue: Encodable, Equatable, Sendable {
    var xy: XY
}

/// Body for `PUT /clip/v2/resource/light/{id}` and `.../grouped_light/{id}`. Nil fields are omitted.
struct LightCommand: Encodable, Equatable, Sendable {
    var on: OnState?
    var dimming: BrightnessValue?
    var colorTemperature: MirekValue?
    var color: XYValue?

    /// Folds a newer command into this one so rapid slider changes collapse into a single request.
    mutating func merge(_ newer: LightCommand) {
        if let on = newer.on { self.on = on }
        if let dimming = newer.dimming { self.dimming = dimming }
        if let colorTemperature = newer.colorTemperature {
            self.colorTemperature = colorTemperature
            color = nil
        }
        if let color = newer.color {
            self.color = color
            colorTemperature = nil
        }
    }
}

/// Body for `PUT /clip/v2/resource/scene/{id}`.
struct SceneRecall: Encodable, Sendable {
    struct Recall: Encodable, Sendable {
        var action = "active"
    }

    var recall = Recall()
}
