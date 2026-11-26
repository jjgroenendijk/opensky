// One collision search over a region, shared by every query inside it. A long body reads
// the floor under each end several times per step, and each read is a thin box inside
// the body's own area, so one search serves them all.

public import OpenSkyFormatsCore
import simd

nonisolated public final class SharedCandidateSearch {
    private let search: CapsuleWorldCollider.CandidateQuery
    private var region: ModelBounds?
    private var shapes: [StaticCollisionShape] = []
    /// Searches made so far: one per `cover`, and one per query outside the region.
    public private(set) var searches = 0

    public init(_ search: @escaping CapsuleWorldCollider.CandidateQuery) {
        self.search = search
    }

    /// Searches `region` once; later queries inside it filter what it found.
    public func cover(_ region: ModelBounds) {
        self.region = region
        shapes = search(region)
        searches += 1
    }

    public func query(_ bounds: ModelBounds) -> [StaticCollisionShape] {
        guard let region, region.encloses(bounds) else {
            searches += 1
            return search(bounds)
        }
        return shapes.filter { $0.bounds.overlaps(bounds) }
    }
}

nonisolated extension LongBodyShape {
    /// Below the feet, the floor a step can reach, with room for a slope under an end.
    static let searchDepth: Float = 256

    /// The area every floor read and push test of one frame stays in, for a body that
    /// moves up to `travel` units from `feet`.
    public func searchRegion(at feet: SIMD3<Float>, yaw: Float, travel: Float) -> ModelBounds {
        let points = endFeet(at: feet, yaw: yaw, lift: 0) + bodyBallFeet(at: feet, yaw: yaw)
        let room = max(endRadius, bodyRadius) * 2 + 1 + max(travel, 0)
        var low = feet
        var high = feet
        for point in points {
            low = simd_min(low, point)
            high = simd_max(high, point)
        }
        return ModelBounds(
            min: low - SIMD3(room, room, Self.searchDepth),
            max: high + SIMD3(room, room, bodyHeight + bodyRadius + stepHeight + room)
        )
    }
}
