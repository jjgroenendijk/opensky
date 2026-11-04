// Distance fades of placed references, from the game's `[LOD] fLODFadeOutMultActors`,
// `fLODFadeOutMultItems`, and `fLODFadeOutMultObjects`. A larger object stays
// visible farther away. docs/engine/graphics-options.md has the rule.

import simd

/// Which fade multiplier a reference follows. Raw values are what the cull shader reads.
nonisolated public enum ReferenceFadeCategory: UInt32, Sendable {
    /// Terrain, LOD, water, and anything else that never fades by distance.
    case none = 0
    case actor = 1
    case item = 2
    case object = 3
}

nonisolated public struct ReferenceFadeDistances: Equatable, Sendable {
    /// World units of reach for each unit of bound radius and of multiplier.
    public static let unitsPerRadius: Float = 16
    /// A tiny item fades as if it were this large, so it does not vanish at once.
    public static let minimumRadius: Float = 32
    /// The dissolve covers this last share of the reach.
    public static let fadeBand: Float = 0.15
    public static let off = Self(actors: 0, items: 0, objects: 0)

    /// The game's multipliers; 0 never fades that category.
    public let actors: Float
    public let items: Float
    public let objects: Float

    public init(actors: Double, items: Double, objects: Double) {
        func multiplier(_ value: Double) -> Float {
            value.isFinite && value > 0 ? Float(min(value, 1000)) : 0
        }
        self.actors = multiplier(actors)
        self.items = multiplier(items)
        self.objects = multiplier(objects)
    }

    public var isOn: Bool {
        actors > 0 || items > 0 || objects > 0
    }

    public func multiplier(_ category: ReferenceFadeCategory) -> Float {
        switch category {
        case .none: 0
        case .actor: actors
        case .item: items
        case .object: objects
        }
    }

    /// The distance where the reference is gone; nil when it never fades.
    public func reach(_ category: ReferenceFadeCategory, radius: Float) -> Float? {
        let multiplier = multiplier(category)
        guard multiplier > 0 else { return nil }
        return multiplier * Self.unitsPerRadius * max(radius, Self.minimumRadius)
    }

    /// 0 whole, up to 1 faded; nil when it is past its reach and not drawn.
    public func fade(
        _ category: ReferenceFadeCategory,
        lower: SIMD3<Float>,
        upper: SIMD3<Float>,
        viewer: SIMD3<Float>
    ) -> Float? {
        let radius = simd_length(upper - lower) * 0.5
        guard let reach = reach(category, radius: radius) else { return 0 }
        let distance = simd_distance((lower + upper) * 0.5, viewer)
        guard distance < reach else { return nil }
        let start = reach * (1 - Self.fadeBand)
        return distance <= start ? 0 : (distance - start) / (reach - start)
    }

    /// x actors, y items, z objects in units per radius; w the minimum radius.
    public var shaderScales: SIMD4<Float> {
        SIMD4(actors, items, objects, 0) * Self.unitsPerRadius
            + SIMD4(0, 0, 0, Self.minimumRadius)
    }
}
