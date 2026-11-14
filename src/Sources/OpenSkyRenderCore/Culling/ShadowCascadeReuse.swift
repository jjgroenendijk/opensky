// Keeps a far sun-shadow cascade's map for a few frames while it still covers
// its slice of the view, so the frame skips drawing it
// (docs/rendering/shadows.md#far-cascade-reuse).

public import simd

/// The cascades one frame uses, and which of them it draws.
nonisolated public struct ShadowCascadePlan: Sendable {
    /// The fresh fit for a drawn cascade; the kept transform for a reused one.
    public var cascades: [ShadowCascade]
    public var redraws: [Bool]

    public init(cascades: [ShadowCascade], redraws: [Bool]) {
        self.cascades = cascades
        self.redraws = redraws
    }
}

nonisolated public struct ShadowCascadeReuse: Sendable {
    /// The share of its radius each far cascade grows by, so its map keeps
    /// covering the view while the camera moves.
    public static let margin: Float = 0.1
    /// A far cascade is drawn again at least every this many frames, so a
    /// moving actor's far shadow lags by a few frames at most.
    public static let maximumAge = [1, 2, 4, 4]
    /// The sun may turn this far, in radians, before a kept map is drawn again.
    public static let sunTolerance: Float = 0.25 * .pi / 180

    private struct Kept: Sendable {
        var viewProjection: simd_float4x4
        var age: Int
    }

    private var kept: [Kept] = []
    private var sun = SIMD3<Float>(0, 0, 0)
    private var resolution = 0

    public init() {}

    /// Forgets every kept map, so the next frame draws all cascades.
    public mutating func reset() {
        kept = []
    }

    /// Plans this frame's cascades from the fresh fit of `request`. A far cascade
    /// keeps its last map while the map covers the whole new slice, the sun has
    /// not turned, and the map is younger than its maximum age.
    public mutating func plan(
        _ request: ShadowCascadeRequest, fresh: [ShadowCascade]
    ) -> ShadowCascadePlan {
        let newSun = ShadowCascadeMath.normalizedSun(request.sunDirection)
        let sunTurned = simd_dot(sun, newSun) < cosf(Self.sunTolerance)
        if sunTurned || request.shadowMapResolution != resolution || kept.count != fresh.count {
            kept = []
        }
        sun = newSun
        resolution = request.shadowMapResolution
        let tanHalfFovY = tanf(max(request.fovYRadians, 1e-4) * 0.5)
        var plan = ShadowCascadePlan(cascades: fresh, redraws: [])
        var next: [Kept] = []
        for (index, cascade) in fresh.enumerated() {
            if index < kept.count, index > 0 {
                let old = kept[index]
                let corners = ShadowCascadeMath.sliceCorners(
                    cameraToWorld: request.cameraToWorld,
                    tanHalfFovY: tanHalfFovY,
                    aspectRatio: request.aspectRatio,
                    slice: (cascade.splitNear, cascade.splitFar)
                )
                let limit = Self.maximumAge[min(index, Self.maximumAge.count - 1)]
                if old.age + 1 < limit, Self.covers(old.viewProjection, corners) {
                    plan.cascades[index].viewProjection = old.viewProjection
                    plan.redraws.append(false)
                    next.append(Kept(viewProjection: old.viewProjection, age: old.age + 1))
                    continue
                }
            }
            plan.redraws.append(true)
            next.append(Kept(viewProjection: cascade.viewProjection, age: 0))
        }
        kept = next
        return plan
    }

    /// Every corner lands inside the map and its depth range.
    static func covers(_ viewProjection: simd_float4x4, _ corners: [SIMD3<Float>]) -> Bool {
        for corner in corners {
            let clip = viewProjection * SIMD4(corner, 1)
            guard clip.w > .ulpOfOne else { return false }
            let ndc = SIMD3(clip.x, clip.y, clip.z) / clip.w
            guard abs(ndc.x) <= 1, abs(ndc.y) <= 1, ndc.z >= 0, ndc.z <= 1 else {
                return false
            }
        }
        return true
    }
}
