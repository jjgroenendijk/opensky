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

    /// Below the lower end a reference fades in, past the upper end it fades out; nil when
    /// it never fades.
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

    /// Steps `state` by `seconds`; nil when the reference never fades. A reference seen
    /// for the first time takes its side of the band at once.
    public func step(
        _ category: ReferenceFadeCategory,
        bounds: ReferenceFadeBounds,
        state: ReferenceFadeState?,
        seconds: Float
    ) -> ReferenceFadeState? {
        guard let band = band(category, radius: bounds.radius) else { return nil }
        let distance = bounds.distance
        var next = state ?? ReferenceFadeState(distance: distance, band: band)
        next.advance(distance: distance, band: band, seconds: seconds)
        return next
    }

    /// x actors, y items, z objects: the multipliers; w the grid reach.
    public var shaderScales: SIMD4<Float> {
        SIMD4(actors, items, objects, Self.gridReach)
    }
}

/// One reference's timed fade: past its band it fades out over 2 seconds, and back
/// inside it fades in over 1.2 seconds. Between the two ends it keeps its direction.
nonisolated public struct ReferenceFadeState: Equatable, Sendable {
    public static let fadeOutSeconds: Float = 2
    public static let fadeInSeconds: Float = 1.2

    /// 0 whole, up to 1 gone.
    public private(set) var amount: Float
    public private(set) var fadingOut: Bool

    public init(distance: Float, band: ClosedRange<Float>) {
        fadingOut = distance >= (band.lowerBound + band.upperBound) * 0.5
        amount = fadingOut ? 1 : 0
    }

    /// Faded out completely, so not drawn.
    var isGone: Bool {
        fadingOut && amount >= 1
    }

    /// The dissolve the shaders take: 0 whole, up to 1 gone; nil when not drawn.
    public var dissolve: Float? {
        isGone ? nil : amount
    }

    public mutating func advance(distance: Float, band: ClosedRange<Float>, seconds: Float) {
        if distance >= band.upperBound {
            fadingOut = true
        } else if distance <= band.lowerBound {
            fadingOut = false
        }
        let step = seconds.isFinite ? max(0, seconds) : 0
        amount = fadingOut
            ? min(1, amount + step / Self.fadeOutSeconds)
            : max(0, amount - step / Self.fadeInSeconds)
    }
}

/// A reference's bound radius and its centre's distance from the camera.
nonisolated public struct ReferenceFadeBounds: Equatable, Sendable {
    public let radius: Float
    public let distance: Float

    public init(lower: SIMD3<Float>, upper: SIMD3<Float>, viewer: SIMD3<Float>) {
        radius = simd_length(upper - lower) * 0.5
        distance = simd_distance((lower + upper) * 0.5, viewer)
    }
}
