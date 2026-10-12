import Foundation

// Resource models for the Hue CLIP v2 API (https://developers.meethue.com/develop/hue-api-v2/).
// JSON keys are snake_case on the wire; HueJSON converts them to camelCase.

enum HueJSON {
    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()

    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return encoder
    }()
}

// MARK: - Value types

struct ResourceRef: Codable, Hashable, Sendable {
    let rid: String
    let rtype: String
}

struct OnState: Codable, Equatable, Sendable {
    var on: Bool
}

struct Dimming: Codable, Equatable, Sendable {
    var brightness: Double
    var minDimLevel: Double?
}

struct XY: Codable, Equatable, Sendable {
    var x: Double
    var y: Double
}

struct Gamut: Codable, Equatable, Sendable {
    var red: XY
    var green: XY
    var blue: XY
}

struct ColorState: Codable, Equatable, Sendable {
    var xy: XY
    var gamut: Gamut?
}

struct MirekSchema: Codable, Equatable, Sendable {
    var mirekMinimum: Int
    var mirekMaximum: Int
}

struct ColorTemperature: Codable, Equatable, Sendable {
    /// Nil while the light is in color (xy) mode.
    var mirek: Int?
    // Absent from partial event updates, so it has to stay optional.
    // swiftlint:disable:next discouraged_optional_boolean
    var mirekValid: Bool?
    var mirekSchema: MirekSchema?
}

struct Metadata: Codable, Equatable, Sendable {
    var name: String
    var archetype: String?
}

// MARK: - Resources

struct Light: Codable, Identifiable, Equatable, Sendable {
    let id: String
    var owner: ResourceRef
    var metadata: Metadata?
    var on: OnState
    var dimming: Dimming?
    var colorTemperature: ColorTemperature?
    var color: ColorState?
}

struct Device: Codable, Identifiable, Equatable, Sendable {
    let id: String
    var metadata: Metadata
    var services: [ResourceRef]
}

/// A room (children are devices) or a zone (children are lights).
struct HueGroup: Codable, Identifiable, Equatable, Sendable {
    let id: String
    var type: String
    var metadata: Metadata
    var children: [ResourceRef]
    var services: [ResourceRef]
}

/// The controllable aggregate of a room, a zone, or the whole home (owner rtype "bridge_home").
struct GroupedLight: Codable, Identifiable, Equatable, Sendable {
    let id: String
    var owner: ResourceRef
    var on: OnState?
    var dimming: Dimming?
}

struct HueScene: Codable, Identifiable, Equatable, Sendable {
    let id: String
    var metadata: Metadata
    var group: ResourceRef
    var status: SceneStatus?
}

struct SceneStatus: Codable, Equatable, Sendable {
    /// "inactive", "static" or "dynamic_palette".
    var active: String
}

struct ZigbeeConnectivity: Codable, Identifiable, Equatable, Sendable {
    let id: String
    var owner: ResourceRef
    /// "connected", "disconnected", "connectivity_issue" or "unidirectional_incoming".
    var status: String
}

/// Unauthenticated `GET /api/0/config`, used to identify a bridge before pairing.
struct BridgeConfig: Decodable, Sendable {
    let name: String
    let bridgeid: String
    let modelid: String?
    let swversion: String?
}

// MARK: - Envelopes

struct HueAPIError: Decodable, Sendable {
    let description: String
}

/// `{"errors": [...], "data": [...]}`. Items that fail to decode are skipped rather than failing the whole list.
struct HueEnvelope<T: Decodable>: Decodable {
    let errors: [HueAPIError]
    let data: [T]

    private enum CodingKeys: String, CodingKey { case errors, data }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        errors = (try? container.decode([HueAPIError].self, forKey: .errors)) ?? []
        data = (try container.decodeIfPresent([Lossy<T>].self, forKey: .data) ?? []).compactMap(\.value)
    }
}

struct Lossy<T: Decodable>: Decodable {
    let value: T?

    init(from decoder: Decoder) throws {
        value = try? T(from: decoder)
    }
}

/// One element of the v1 pairing response: `[{"success": {...}}]` or `[{"error": {...}}]`.
struct PairResponseItem: Decodable {
    struct Success: Decodable {
        let username: String
        let clientkey: String?
    }

    struct Failure: Decodable {
        let type: Int
        let description: String
    }

    let success: Success?
    let error: Failure?
}

// MARK: - Event stream

struct HueEvent: Decodable, Sendable {
    /// "update", "add", "delete" or "error".
    let type: String
    let data: [ResourceDelta]

    private enum CodingKeys: String, CodingKey { case type, data }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(String.self, forKey: .type)
        data = ((try? container.decode([Lossy<ResourceDelta>].self, forKey: .data)) ?? []).compactMap(\.value)
    }
}

/// A partial resource from the event stream; only changed fields are present.
struct ResourceDelta: Decodable, Sendable {
    enum Status: Equatable, Sendable {
        case text(String)
        case scene(SceneStatus)
    }

    let id: String
    let type: String
    var owner: ResourceRef?
    var on: OnState?
    var dimming: Dimming?
    var colorTemperature: ColorTemperature?
    var color: ColorState?
    var metadata: Metadata?
    var status: Status?

    private enum CodingKeys: String, CodingKey {
        case id, type, owner, on, dimming, colorTemperature, color, metadata, status
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        type = try container.decode(String.self, forKey: .type)
        // Field shapes differ between resource types, so each one is decoded leniently.
        owner = try? container.decodeIfPresent(ResourceRef.self, forKey: .owner)
        on = try? container.decodeIfPresent(OnState.self, forKey: .on)
        dimming = try? container.decodeIfPresent(Dimming.self, forKey: .dimming)
        colorTemperature = try? container.decodeIfPresent(ColorTemperature.self, forKey: .colorTemperature)
        color = try? container.decodeIfPresent(ColorState.self, forKey: .color)
        metadata = try? container.decodeIfPresent(Metadata.self, forKey: .metadata)
        if let text = try? container.decode(String.self, forKey: .status) {
            status = .text(text)
        } else if let scene = try? container.decode(SceneStatus.self, forKey: .status) {
            status = .scene(scene)
        } else {
            status = nil
        }
    }
}

// MARK: - Display helpers

extension Light {
    var isInColorTemperatureMode: Bool {
        colorTemperature?.mirekValid == true && colorTemperature?.mirek != nil
    }

    /// Approximate sRGB color the light is currently emitting, at full brightness.
    var displayRGB: RGB {
        if isInColorTemperatureMode, let mirek = colorTemperature?.mirek {
            return ColorMath.rgb(mirek: mirek)
        }
        if let xy = color?.xy {
            return ColorMath.rgb(xy: xy)
        }
        if let mirek = colorTemperature?.mirek {
            return ColorMath.rgb(mirek: mirek)
        }
        return ColorMath.rgb(mirek: 366)
    }
}
