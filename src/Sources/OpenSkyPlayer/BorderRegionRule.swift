// The edge of the playable world: a border region's outline keeps the player inside.
// See docs/engine/walk-mode.md#border-regions.

import simd

nonisolated public enum BorderRegionRule {
    /// False when a step from `from` to `to` leaves every border outline it was inside.
    /// A worldspace without border regions, or a player already outside, moves freely.
    public static func allows(
        from: SIMD2<Float>, to: SIMD2<Float>, outlines: [[SIMD2<Float>]]
    ) -> Bool {
        guard !outlines.isEmpty else { return true }
        let inside = { (point: SIMD2<Float>) in outlines.contains { contains(point, outline: $0) } }
        return !inside(from) || inside(to)
    }

    /// Even-odd test: a ray towards +x crosses the outline an odd number of times.
    static func contains(_ point: SIMD2<Float>, outline: [SIMD2<Float>]) -> Bool {
        var inside = false
        var previous = outline.last ?? point
        for current in outline {
            if (current.y > point.y) != (previous.y > point.y) {
                let crossX = current.x + (point.y - current.y) / (previous.y - current.y)
                    * (previous.x - current.x)
                if point.x < crossX {
                    inside.toggle()
                }
            }
            previous = current
        }
        return inside
    }
}
