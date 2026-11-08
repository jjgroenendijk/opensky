// The static shapes near each body, found once per step instead of once per
// substep. A substep keeps only the shapes its current bounds overlap, which is
// exactly what a fresh query returns. See docs/engine/dynamic-bodies.md.

import OpenSkyFormatsCore
import simd

nonisolated struct DynamicStaticShapes {
    private var reach: [ModelBounds?]
    private var shapes: [[StaticCollisionShape]]

    init(bodyCount: Int) {
        reach = Array(repeating: nil, count: bodyCount)
        shapes = Array(repeating: [], count: bodyCount)
    }

    /// The shapes `body` overlaps now. The first call queries a box widened by
    /// the step's travel; a later call queries again only once the body left it.
    mutating func candidates(
        for body: DynamicBody, index: Int, world: DynamicStepWorld, dt: Float
    ) -> [StaticCollisionShape] {
        let bounds = body.worldBounds
        if reach[index].map({ !$0.encloses(bounds) }) ?? true {
            let margin = simd_length(body.linearVelocity) * dt
                + DynamicBodySolver.substepDistance(of: body)
            let widened = ModelBounds(
                min: bounds.min - SIMD3(repeating: margin),
                max: bounds.max + SIMD3(repeating: margin)
            )
            reach[index] = widened
            shapes[index] = world.staticCandidates(widened)
        }
        return shapes[index].filter { $0.bounds.overlaps(bounds) }
    }
}

nonisolated extension ModelBounds {
    func encloses(_ other: ModelBounds) -> Bool {
        all(min .<= other.min) && all(max .>= other.max)
    }
}
