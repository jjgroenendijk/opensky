// Back-to-front order for blended particles: far ones draw first, so a near
// particle blends over a far one and not the other way round.

import simd

nonisolated public enum ParticleDrawOrder: Sendable {
    /// Farthest from `viewer` first. Equal distances keep their input order.
    public static func backToFront<Element>(
        _ elements: [Element],
        viewer: SIMD3<Float>,
        at position: (Element) -> SIMD3<Float>
    ) -> [Element] {
        let keyed = elements.enumerated().map { index, element in
            (distance: simd_distance_squared(position(element), viewer), index: index)
        }
        return keyed.sorted { lhs, rhs in
            lhs.distance != rhs.distance ? lhs.distance > rhs.distance : lhs.index < rhs.index
        }.map { elements[$0.index] }
    }
}
