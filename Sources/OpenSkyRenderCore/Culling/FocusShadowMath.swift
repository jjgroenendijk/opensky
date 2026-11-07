// Focus shadows, the game's `[Display] iNumFocusShadow`: one small sun-shadow map
// fitted around each of the actors nearest the camera, so their own shadows stay sharp
// where the cascades are coarse. docs/rendering/shadows.md.

public import OpenSkyFormatsCore
public import simd

/// One actor a focus shadow follows.
nonisolated public struct FocusShadowTarget: Equatable, Sendable {
    public let owner: UInt32
    public let bounds: ModelBounds

    public init(owner: UInt32, bounds: ModelBounds) {
        self.owner = owner
        self.bounds = bounds
    }
}

/// One focus shadow this frame: whom it follows, how strong it is, and its map size.
nonisolated public struct FocusShadowPick: Equatable, Sendable {
    public let target: FocusShadowTarget
    public let strength: Float
    public let size: Int
}

/// docs/rendering/shadows.md#focus-shadows has the game's rules.
nonisolated public enum FocusShadowMath {
    /// Actors farther than this from the camera get no focus shadow.
    public static let range: Float = 450
    /// The share of `range` squared inside which the shadow is at full strength.
    public static let fullStrengthShare: Float = 0.25
    /// The map doubles in size for each step this much closer to the camera.
    public static let doublingStep: Float = 450
    public static let smallestSize: Float = 50
    /// The receiver bias in world units.
    public static let receiverBiasUnits: Float = 2

    /// The nearest `count` targets inside `range`, nearest first.
    public static func pick(
        _ targets: [FocusShadowTarget],
        viewer: SIMD3<Float>,
        count: Int,
        resolution: Int = Int.max
    ) -> [FocusShadowPick] {
        guard count > 0 else { return [] }
        let ranked = targets.map { target in
            (target, simd_distance(centre(target.bounds), viewer))
        }
        .filter { $0.1 <= range }
        .sorted { ($0.1, $0.0.owner) < ($1.1, $1.0.owner) }
        return ranked.prefix(count).map { target, distance in
            FocusShadowPick(
                target: target,
                strength: strength(distance: distance),
                size: size(distance: distance, resolution: resolution)
            )
        }
    }

    /// 1 out to half of `range`, then falling in a straight line with the squared distance.
    public static func strength(distance: Float) -> Float {
        let reach = range * range
        let full = fullStrengthShare * reach
        let squared = distance * distance
        guard squared >= full else { return 1 }
        return max((reach - squared) / (reach - full), 0)
    }

    /// 800 texels at the camera, halving every `doublingStep`, never below 50.
    public static func size(distance: Float, resolution: Int) -> Int {
        let doublings = max((4 * doublingStep - distance) / doublingStep, 0)
        return min(resolution, Int(smallestSize * pow(2, doublings)))
    }

    /// World to the focus view's clip space, looking along `sunDirection` (sun to scene).
    public static func viewProjection(
        bounds: ModelBounds,
        sunDirection: SIMD3<Float>
    ) -> float4x4 {
        let radius = radius(bounds)
        let direction = simd_normalize(sunDirection)
        let eye = centre(bounds) - direction * (1.1 * radius)
        let up: SIMD3<Float> = abs(direction.z) > 0.99 ? SIMD3(0, 1, 0) : SIMD3(0, 0, 1)
        let view = MatrixMath.lookAt(eye: eye, target: centre(bounds), up: up)
        let projection = MatrixMath.orthographic(OrthographicBounds(
            left: -radius, right: radius, bottom: -radius, top: radius,
            nearZ: 0.1 * radius, farZ: 2.2 * radius
        ))
        return projection * view
    }

    /// The depth the view covers, in world units.
    public static func depthRange(bounds: ModelBounds) -> Float {
        2.1 * radius(bounds)
    }

    static func radius(_ bounds: ModelBounds) -> Float {
        max(simd_length(bounds.max - bounds.min) * 0.5, 1)
    }

    static func centre(_ bounds: ModelBounds) -> SIMD3<Float> {
        (bounds.min + bounds.max) * 0.5
    }
}
