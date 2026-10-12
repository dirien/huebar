import SwiftUI

extension Color {
    init(_ rgb: RGB) {
        self.init(.sRGB, red: rgb.r, green: rgb.g, blue: rgb.b)
    }
}

enum Theme {
    /// Hue's signature warm glow, used when there is no light color to show.
    static let amber = Color(red: 1.0, green: 0.74, blue: 0.3)
    /// Foreground for content drawn on light colors, which are always bright.
    static let onLight = Color.black.opacity(0.72)
    static let cardRadius: CGFloat = 14

    /// The distinct colors of the given lights (at most four), for gradients.
    static func colors(of lights: [Light]) -> [Color] {
        var picked: [RGB] = []
        for rgb in lights.map(\.displayRGB) where picked.count < 4 {
            let isDuplicate = picked.contains { abs($0.r - rgb.r) + abs($0.g - rgb.g) + abs($0.b - rgb.b) < 0.12 }
            if !isDuplicate {
                picked.append(rgb)
            }
        }
        return picked.map { Color($0) }
    }

    /// Gradient stops with at least two colors; a single color fades in from a softer shade of itself.
    static func stops(_ colors: [Color]) -> [Color] {
        switch colors.count {
        case 0: [amber.opacity(0.7), amber]
        case 1: [colors[0].opacity(0.7), colors[0]]
        default: colors
        }
    }

    static func gradient(
        _ colors: [Color],
        from start: UnitPoint = .leading,
        to end: UnitPoint = .trailing
    ) -> LinearGradient {
        LinearGradient(colors: stops(colors), startPoint: start, endPoint: end)
    }
}

/// Phosphor icons for Hue room and light archetypes.
enum Symbols {
    static func room(_ archetype: String?) -> PhosphorIcon {
        switch archetype ?? "" {
        case "living_room", "lounge": .couch
        case "tv": .television
        case "kitchen": .cookingPot
        case "dining": .forkKnife
        case "bedroom", "guest_room": .bed
        case "kids_bedroom", "nursery": .baby
        case "bathroom": .bathtub
        case "toilet": .shower
        case "office", "computer", "studio": .desktop
        case "reading": .bookOpen
        case "hallway", "front_door", "porch": .doorOpen
        case "staircase", "top_floor", "upstairs", "downstairs", "attic": .stairs
        case "garden", "terrace", "balcony", "driveway", "pool", "barbecue": .tree
        case "garage", "carport": .car
        case "gym": .barbell
        case "other": .squaresFour
        default: .house
        }
    }

    static func light(_ archetype: String?) -> PhosphorIcon {
        guard let archetype else { return .lightbulb }
        if archetype.contains("pendant") || archetype.contains("ceiling") || archetype.contains("chandelier") {
            return .lampPendant
        }
        if archetype.contains("table") || archetype.contains("desk") || archetype.contains("floor")
            || archetype.contains("hue_go") || archetype.contains("bloom") || archetype.contains("iris")
        {
            return .lamp
        }
        if archetype.contains("plug") {
            return .plug
        }
        return .lightbulb
    }
}
