// The culling box of a posed actor. See docs/engine/actor-resolution.md.

import OpenSkyFormatsCore
import simd

nonisolated enum ActorPoseBounds {
    /// A box around the root that holds every part in any pose. A part's own box is
    /// its bind pose, and a seated actor moves its head and hands out of theirs.
    static func containing(_ parts: [ModelBounds]) -> ModelBounds? {
        guard let first = parts.first else { return nil }
        let local = parts.dropFirst().reduce(first) { $0.union($1) }
        let reach = local.corners.map(simd_length).max() ?? 0
        return ModelBounds(min: SIMD3(repeating: -reach), max: SIMD3(repeating: reach))
    }
}
