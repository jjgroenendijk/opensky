// Focus shadows, the game's `[Display] iNumFocusShadow`: one small sun-shadow map
// fitted around each of the actors nearest the camera, so their own shadows stay sharp
// where the cascades are coarse. docs/rendering/shadows.md.

import OpenSkyFormatsCore
import simd

/// One actor a focus shadow follows.
nonisolated public struct FocusShadowTarget: Equatable, Sendable {
    public let owner: UInt32
    public let bounds: ModelBounds

    public init(owner: UInt32, bounds: ModelBounds) {
        self.owner = owner
        self.bounds = bounds
    }
}

nonisolated public enum FocusShadowMath {
    /// Actors farther than this from the camera get no focus shadow.
    public static let range: Float = 2048
    /// The view starts this far before the actor toward the sun, so a raised arm still casts.
    public static let casterBackup: Float = 256
    /// The receiver bias in world units.
    public static let receiverBiasUnits: Float = 2

    /// The nearest `count` targets inside `range`, nearest first.
    public static func pick(
        _ targets: [FocusShadowTarget],
        viewer: SIMD3<Float>,
        count: Int
    ) -> [FocusShadowTarget] {
        guard count > 0 else { return [] }
        let ranked = targets.map { target in
            (target, simd_distance(centre(target.bounds), viewer))
        }
        .filter { $0.1 <= range }
        .sorted { ($0.1, $0.0.owner) < ($1.1, $1.0.owner) }
        return ranked.prefix(count).map(\.0)
    }

    /// World to the focus view's clip space, looking along `sunDirection` (sun to scene).
    public static func viewProjection(
        bounds: ModelBounds,
        sunDirection: SIMD3<Float>
    ) -> float4x4 {
        let radius = max(simd_length(bounds.max - bounds.min) * 0.5, 1)
        let direction = simd_normalize(sunDirection)
        let eye = centre(bounds) - direction * (radius + casterBackup)
        let up: SIMD3<Float> = abs(direction.z) > 0.99 ? SIMD3(0, 1, 0) : SIMD3(0, 0, 1)
        let view = MatrixMath.lookAt(eye: eye, target: centre(bounds), up: up)
        let projection = MatrixMath.orthographic(OrthographicBounds(
            left: -radius, right: radius, bottom: -radius, top: radius,
            nearZ: 0, farZ: depthRange(bounds: bounds)
        ))
        return projection * view
    }

    /// The depth the view covers: the actor and the backup in front of it.
    public static func depthRange(bounds: ModelBounds) -> Float {
        max(simd_length(bounds.max - bounds.min), 2) + casterBackup
    }

    static func centre(_ bounds: ModelBounds) -> SIMD3<Float> {
        (bounds.min + bounds.max) * 0.5
    }
}
