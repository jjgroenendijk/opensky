// Immutable per-cell trigger-volume world (issue #173). A REFR whose NIF
// carries SkyrimLayer 12 (trigger) bodies contributes no solid collision, so
// the static collision build drops it; those bodies land here instead, placed
// in world space and indexed by the same `BoundsSpatialIndex` broadphase the
// static set uses. Overlap tests answer "is the player capsule inside this
// volume", which is a boolean question — no contact normal or depth is
// produced, so the narrowphase below is deliberately simpler than
// `CapsuleWorldCollider`.

import simd

nonisolated struct TriggerVolume {
    /// The REFR that authored this volume.
    let reference: ReferenceKey
    let formID: FormID
    let transform: float4x4
    let geometry: NIFCollisionGeometry
    /// World-space AABB.
    let bounds: ModelBounds
}

/// Trigger accounting for one cell, or summed over resident cells. Kept
/// separate from `StaticCollisionStats` rather than folded into it because
/// `filteredBodyCount` there has a pinned meaning the CLI grid acceptance
/// asserts on, and a trigger tally is a different question.
nonisolated struct TriggerVolumeStats: Equatable {
    /// Volumes contributed by SkyrimLayer 12 shapes inside a placed NIF.
    var meshVolumeCount = 0
    /// Volumes contributed by an `XPRM` box or sphere primitive.
    var primitiveVolumeCount = 0
    /// `XPRM` primitives deliberately not made volumes: `none`, `portalBox`
    /// and `line` (see docs/engine/collision-world.md).
    var excludedPrimitiveCount = 0
    /// Trigger sources whose geometry produced no finite world bounds.
    var degenerateVolumeCount = 0
    /// Trigger sources dropped because no runtime index entry supplied a
    /// `ReferenceKey`, so no script instance could ever be addressed.
    var unkeyedReferenceCount = 0

    var volumeCount: Int {
        meshVolumeCount + primitiveVolumeCount
    }

    mutating func add(_ other: TriggerVolumeStats) {
        meshVolumeCount += other.meshVolumeCount
        primitiveVolumeCount += other.primitiveVolumeCount
        excludedPrimitiveCount += other.excludedPrimitiveCount
        degenerateVolumeCount += other.degenerateVolumeCount
        unkeyedReferenceCount += other.unkeyedReferenceCount
    }
}

nonisolated struct TriggerVolumeSet {
    let location: CellSceneLocation?
    let volumes: [TriggerVolume]
    let stats: TriggerVolumeStats
    private let index: BoundsSpatialIndex

    init(
        location: CellSceneLocation?,
        volumes: [TriggerVolume],
        stats: TriggerVolumeStats = TriggerVolumeStats()
    ) {
        self.location = location
        self.volumes = volumes
        self.stats = stats
        index = BoundsSpatialIndex(bounds: volumes.map(\.bounds))
    }

    static let empty = TriggerVolumeSet(location: nil, volumes: [])

    var indexNodeCount: Int {
        index.nodeCount
    }

    /// Broadphase: volumes whose world AABB overlaps `bounds`, in ascending
    /// source order so repeated queries are deterministic.
    func candidates(overlapping bounds: ModelBounds) -> [TriggerVolume] {
        index.query(overlapping: bounds)
            .map { volumes[$0] }
            .filter { $0.bounds.overlaps(bounds) }
    }
}

nonisolated extension TriggerVolume {
    /// Volumes for every shape of a trigger-layer body, placed by `transform`.
    ///
    /// The world AABB is the union of the geometry's broadphase partitions
    /// (`StaticCollisionShape.partitions(for:)`, which already knows every
    /// geometry case's local bounds) pushed through `transform` by 8-corner
    /// reboxing. Nil when the geometry yields no finite bounds — a degenerate
    /// soup with no in-range indices, or a non-finite transform.
    static func placed(
        reference: ReferenceKey,
        formID: FormID,
        transform: float4x4,
        geometry: NIFCollisionGeometry
    ) -> TriggerVolume? {
        let partitions = StaticCollisionShape.partitions(for: geometry).partitions
        guard let first = partitions.first else { return nil }
        let local = partitions.dropFirst().reduce(first.localBounds) {
            $0.union($1.localBounds)
        }
        let world = local.transformed(by: transform)
        let finite = (0 ..< 3).allSatisfy { world.min[$0].isFinite && world.max[$0].isFinite }
        guard finite else { return nil }
        return TriggerVolume(
            reference: reference,
            formID: formID,
            transform: transform,
            geometry: geometry,
            bounds: world
        )
    }
}

nonisolated extension TriggerVolumeSet {
    /// Volumes whose geometry the capsule at `feetPosition` intersects.
    ///
    /// Broadphase on the capsule's world AABB, then a per-geometry narrowphase.
    /// Source order is preserved from `candidates(overlapping:)`.
    func volumes(
        intersecting capsule: PlayerCapsule,
        at feetPosition: SIMD3<Float>
    ) -> [TriggerVolume] {
        let query = TriggerCapsuleQuery(capsule: capsule, feetPosition: feetPosition)
        return candidates(overlapping: query.bounds).filter { query.intersects($0) }
    }
}

/// One capsule pose resolved into the values every narrowphase case needs.
nonisolated struct TriggerCapsuleQuery {
    /// Matches `CapsuleWorldCollider.contactTolerance`, so a capsule the solid
    /// narrowphase treats as touching a surface also counts as inside a
    /// coincident trigger.
    private static let tolerance: Float = 0.02
    /// Alternating-projection steps for the segment-versus-box solve. The
    /// sequence is monotonically non-increasing over two convex sets, and a
    /// dozen steps is far past the precision a trigger boolean needs.
    private static let boxSolveIterations = 12

    let capsule: PlayerCapsule
    /// Capsule axis segment: the two sphere centers, bottom then top.
    let segment: (first: SIMD3<Float>, second: SIMD3<Float>)
    /// World AABB of the capsule, grown by the contact tolerance.
    let bounds: ModelBounds

    init(capsule: PlayerCapsule, feetPosition: SIMD3<Float>) {
        self.capsule = capsule
        segment = (
            feetPosition + SIMD3<Float>(0, 0, capsule.radius),
            feetPosition + SIMD3<Float>(0, 0, max(capsule.radius, capsule.height - capsule.radius))
        )
        let padding = SIMD3<Float>(repeating: capsule.radius + Self.tolerance)
        let low = simd_min(segment.first, segment.second) - padding
        let high = simd_max(segment.first, segment.second) + padding
        bounds = ModelBounds(min: low, max: high)
    }

    func intersects(_ volume: TriggerVolume) -> Bool {
        switch volume.geometry {
        case let .box(halfExtents):
            return intersectsBox(halfExtents: halfExtents, transform: volume.transform)
        case let .sphere(radius):
            let center = TriggerVolumeMath.transform(.zero, by: volume.transform)
            let scaled = radius * TriggerVolumeMath.maximumScale(of: volume.transform)
            let point = TriggerVolumeMath.closestPoint(on: segment, to: center)
            return simd_distance(point, center) <= capsule.radius + scaled + Self.tolerance
        case let .capsule(first, second, radius):
            let obstacle = (
                TriggerVolumeMath.transform(first, by: volume.transform),
                TriggerVolumeMath.transform(second, by: volume.transform)
            )
            let scaled = radius * TriggerVolumeMath.maximumScale(of: volume.transform)
            let closest = TriggerVolumeMath.closestSegments(segment, obstacle)
            return simd_distance(closest.first, closest.second)
                <= capsule.radius + scaled + Self.tolerance
        case .convexVertices, .triangleSoup:
            // [INFO] Conservative approximation: a convex hull and a triangle
            // soup are tested against their world AABB only, so a capsule in a
            // corner the mesh does not fill still reports as inside. Trigger
            // volumes authored in the Creation Kit are box, sphere, or capsule
            // primitives in practice; a mesh trigger is rare and erring toward
            // firing is the safer failure for OnTriggerEnter. Documented in
            // docs/engine/collision-world.md.
            return volume.bounds.overlaps(bounds)
        }
    }

    /// Exact for a rigid transform with uniform scale, which is what a REFR
    /// matrix (position x rotation x XSCL) composes. The segment is pushed into
    /// box-local space, the closest local point pair is solved there, and both
    /// points are mapped back to world before measuring, so rotation and
    /// uniform scale are handled without distorting the distance. A
    /// non-uniformly scaled body would make the measure approximate.
    private func intersectsBox(halfExtents: SIMD3<Float>, transform: float4x4) -> Bool {
        let inverse = transform.inverse
        let local = (
            TriggerVolumeMath.transform(segment.first, by: inverse),
            TriggerVolumeMath.transform(segment.second, by: inverse)
        )
        let half = simd_abs(halfExtents)
        var onSegment = (local.0 + local.1) * 0.5
        var onBox = simd_clamp(onSegment, -half, half)
        for _ in 0 ..< Self.boxSolveIterations {
            onSegment = TriggerVolumeMath.closestPoint(on: local, to: onBox)
            onBox = simd_clamp(onSegment, -half, half)
        }
        let worldSegment = TriggerVolumeMath.transform(onSegment, by: transform)
        let worldBox = TriggerVolumeMath.transform(onBox, by: transform)
        return simd_distance(worldSegment, worldBox) <= capsule.radius + Self.tolerance
    }
}

/// Boolean-only segment math. `CapsuleWorldCollider` owns the equivalent
/// contact-producing routines for solid collision; these stay separate because
/// they answer a distance question and never build a normal or a depth.
nonisolated enum TriggerVolumeMath {
    static func transform(_ point: SIMD3<Float>, by matrix: float4x4) -> SIMD3<Float> {
        let transformed = matrix * SIMD4<Float>(point, 1)
        return SIMD3(transformed.x, transformed.y, transformed.z)
    }

    static func maximumScale(of matrix: float4x4) -> Float {
        max(
            simd_length(SIMD3(matrix.columns.0.x, matrix.columns.0.y, matrix.columns.0.z)),
            simd_length(SIMD3(matrix.columns.1.x, matrix.columns.1.y, matrix.columns.1.z)),
            simd_length(SIMD3(matrix.columns.2.x, matrix.columns.2.y, matrix.columns.2.z))
        )
    }

    static func closestPoint(
        on segment: (SIMD3<Float>, SIMD3<Float>),
        to point: SIMD3<Float>
    ) -> SIMD3<Float> {
        let delta = segment.1 - segment.0
        let lengthSquared = simd_length_squared(delta)
        guard lengthSquared > Float.ulpOfOne else { return segment.0 }
        let time = max(0, min(1, simd_dot(point - segment.0, delta) / lengthSquared))
        return segment.0 + delta * time
    }

    /// Closest point pair between two segments, clamped to both endpoints.
    /// Closed form over the two parameters, with the degenerate zero-length
    /// cases handled before the divide.
    static func closestSegments(
        _ first: (SIMD3<Float>, SIMD3<Float>),
        _ second: (SIMD3<Float>, SIMD3<Float>)
    ) -> (first: SIMD3<Float>, second: SIMD3<Float>) {
        let firstDelta = first.1 - first.0
        let secondDelta = second.1 - second.0
        let firstLengthSquared = simd_length_squared(firstDelta)
        let secondLengthSquared = simd_length_squared(secondDelta)
        guard firstLengthSquared > Float.ulpOfOne else {
            return (first.0, closestPoint(on: second, to: first.0))
        }
        guard secondLengthSquared > Float.ulpOfOne else {
            return (closestPoint(on: first, to: second.0), second.0)
        }
        let times = segmentTimes(
            firstDelta: firstDelta,
            secondDelta: secondDelta,
            offset: first.0 - second.0
        )
        return (
            first.0 + firstDelta * times.first,
            second.0 + secondDelta * times.second
        )
    }

    /// Parameter pair for `closestSegments`, both already clamped to `0...1`.
    private static func segmentTimes(
        firstDelta: SIMD3<Float>,
        secondDelta: SIMD3<Float>,
        offset: SIMD3<Float>
    ) -> (first: Float, second: Float) {
        let firstLengthSquared = simd_length_squared(firstDelta)
        let secondLengthSquared = simd_length_squared(secondDelta)
        let firstOffsetDot = simd_dot(firstDelta, offset)
        let secondOffsetDot = simd_dot(secondDelta, offset)
        let directionsDot = simd_dot(firstDelta, secondDelta)
        let denominator = firstLengthSquared * secondLengthSquared
            - directionsDot * directionsDot
        var firstTime: Float = 0
        if abs(denominator) > Float.ulpOfOne {
            firstTime = clampUnit((
                directionsDot * secondOffsetDot - firstOffsetDot * secondLengthSquared
            ) / denominator)
        }
        var secondTime = (directionsDot * firstTime + secondOffsetDot) / secondLengthSquared
        if secondTime < 0 {
            secondTime = 0
            firstTime = clampUnit(-firstOffsetDot / firstLengthSquared)
        } else if secondTime > 1 {
            secondTime = 1
            firstTime = clampUnit((directionsDot - firstOffsetDot) / firstLengthSquared)
        }
        return (firstTime, secondTime)
    }

    private static func clampUnit(_ value: Float) -> Float {
        max(0, min(1, value))
    }
}
