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
    /// `2048 * (uGridsToLoad - 1)` at the default 5 grids: the farthest a reference's
    /// own end distance reaches before the multiplier.
    public static let gridReach: Float = 2048 * 4
    /// `fLODBoundRadiusMult`: the end distance is at most this many bound radii.
    public static let boundRadiusMultiplier: Float = 10
    /// `fLODFadeOutPercent`: the start distance as a share of the end distance.
    public static let startShare: Float = 0.6
    /// `iFadeNodeMinNearDistance`; the end then stays at least twice as far.
    public static let minimumStart: Float = 500
    /// The game fades a reference out once it passes this share of its start-to-end range,
    /// and back in below `fadeInShare`.
    public static let fadeOutShare: Float = 0.7
    public static let fadeInShare: Float = 0.3
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

    /// Where the dissolve starts and where the reference is gone; nil when it never fades.
    /// docs/engine/graphics-options.md#reference-fade has the rule.
    public func band(_ category: ReferenceFadeCategory, radius: Float) -> ClosedRange<Float>? {
        let multiplier = multiplier(category)
        guard multiplier > 0 else { return nil }
        var end = Self.gridReach - radius
        if radius > 0.0001 {
            end = min(end, Self.boundRadiusMultiplier * radius)
        }
        var start = Self.startShare * end
        if start < Self.minimumStart {
            start = Self.minimumStart
            end = max(2 * Self.minimumStart, end)
        }
        let span = end - start
        return multiplier * (start + Self.fadeInShare * span)
            ... multiplier * (start + Self.fadeOutShare * span)
    }

    /// 0 whole, up to 1 faded; nil when it is past its band and not drawn.
    public func fade(
        _ category: ReferenceFadeCategory,
        lower: SIMD3<Float>,
        upper: SIMD3<Float>,
        viewer: SIMD3<Float>
    ) -> Float? {
        let radius = simd_length(upper - lower) * 0.5
        guard let band = band(category, radius: radius) else { return 0 }
        let distance = simd_distance((lower + upper) * 0.5, viewer)
        guard distance < band.upperBound else { return nil }
        guard distance > band.lowerBound else { return 0 }
        return (distance - band.lowerBound) / (band.upperBound - band.lowerBound)
    }

    /// x actors, y items, z objects: the multipliers; w the grid reach.
    public var shaderScales: SIMD4<Float> {
        SIMD4(actors, items, objects, Self.gridReach)
    }
}
