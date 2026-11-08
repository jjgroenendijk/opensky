// Pairs of dynamic bodies whose bounding spheres overlap, found by sort and
// sweep along X instead of testing every pair. The pairs come back in the order
// the all-pairs loop visited them, so the solver sees the same contact order.

import simd

nonisolated enum DynamicBodyBroadPhase {
    /// Pairs `(first, second)` with `first < second`, at least one body awake,
    /// and touching bounding spheres, sorted by `first` then `second`.
    static func candidatePairs(
        _ bodies: [DynamicBody],
        admits: (Int, Int) -> Bool
    ) -> [(first: Int, second: Int)] {
        guard bodies.count > 1, bodies.contains(where: { !$0.isSleeping }) else { return [] }
        // A body with a non-finite bound passes no sphere test, so it leaves the sweep.
        let order = bodies.indices.filter { lowerX(bodies[$0]).isFinite }.sorted { lhs, rhs in
            lowerX(bodies[lhs]) < lowerX(bodies[rhs])
        }
        var pairs: [(first: Int, second: Int)] = []
        for (position, index) in order.enumerated() {
            let body = bodies[index]
            let upper = body.position.x + body.definition.boundingRadius
            for other in order[(position + 1)...] {
                let candidate = bodies[other]
                guard lowerX(candidate) <= upper else { break }
                guard !body.isSleeping || !candidate.isSleeping else { continue }
                let reach = body.definition.boundingRadius + candidate.definition.boundingRadius
                guard simd_distance_squared(body.position, candidate.position) <= reach * reach
                else { continue }
                let pair = (first: min(index, other), second: max(index, other))
                if admits(pair.first, pair.second) {
                    pairs.append(pair)
                }
            }
        }
        return pairs.sorted { $0.first == $1.first ? $0.second < $1.second : $0.first < $1.first }
    }

    private static func lowerX(_ body: DynamicBody) -> Float {
        body.position.x - body.definition.boundingRadius
    }
}
