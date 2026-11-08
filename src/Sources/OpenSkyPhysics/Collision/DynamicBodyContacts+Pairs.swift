// Contacts between two dynamic bodies, one volume pair at a time: two hulls meet
// by face clipping, two radial volumes at their closest points, and a hull and a
// radial volume by samples. See docs/engine/dynamic-narrowphase.md#body-against-body.

import simd

nonisolated extension DynamicBodyContacts {
    /// Friction is the geometric mean of the pair and restitution the larger one, the
    /// usual pairing rules.
    public static func pairContacts(
        first: DynamicPairBody,
        second: DynamicPairBody
    ) -> [DynamicContact] {
        let material = DynamicContactMaterial(
            friction: (first.body.definition.friction * second.body.definition.friction)
                .squareRoot(),
            restitution: max(
                first.body.definition.restitution, second.body.definition.restitution
            )
        )
        let pair = DynamicBodyPair(first: first, second: second, material: material)
        var contacts: [DynamicContact] = []
        for firstVolume in first.body.definition.volumes.indices {
            for secondVolume in second.body.definition.volumes.indices {
                contacts += pair.contacts(firstVolume, secondVolume)
            }
        }
        return contacts
    }
}

/// Two bodies and the material their contacts share.
nonisolated struct DynamicBodyPair {
    let first: DynamicPairBody
    let second: DynamicPairBody
    let material: DynamicContactMaterial

    private var margin: Float {
        DynamicBodyContacts.contactMargin
    }

    func contacts(_ firstVolume: Int, _ secondVolume: Int) -> [DynamicContact] {
        let firstDefinition = first.body.definition
        let secondDefinition = second.body.definition
        switch (firstDefinition.volumes[firstVolume], secondDefinition.volumes[secondVolume]) {
        case let (.hull(firstPoints, firstPlanes), .hull(secondPoints, secondPlanes)):
            guard
                let firstTopology = firstDefinition.hullTopologies[firstVolume],
                let secondTopology = secondDefinition.hullTopologies[secondVolume]
            else { return sampled(firstVolume, secondVolume) }
            let firstHull = DynamicPosedHull(
                points: firstPoints, planes: firstPlanes, topology: firstTopology,
                position: first.body.position, orientation: first.body.orientation
            )
            let secondHull = DynamicPosedHull(
                points: secondPoints, planes: secondPlanes, topology: secondTopology,
                position: second.body.position, orientation: second.body.orientation
            )
            return DynamicConvexManifold.manifold(
                first: firstHull, second: secondHull, margin: margin
            ).map(contacts(of:)) ?? []
        case let (
            .radial(firstStart, firstEnd, firstRadius),
            .radial(secondStart, secondEnd, secondRadius)
        ):
            let firstSegment = posed(first.body, firstStart, firstEnd)
            let secondSegment = posed(second.body, secondStart, secondEnd)
            return segmentContact(
                firstSegment, secondSegment, radii: (firstRadius, secondRadius)
            ).map { [$0] } ?? []
        default:
            return sampled(firstVolume, secondVolume)
        }
    }

    private func contacts(of manifold: DynamicHullManifold) -> [DynamicContact] {
        let reference = manifold.firstIsReference ? first : second
        let incident = manifold.firstIsReference ? second : first
        return manifold.points.map { point in
            DynamicContact(
                body: incident.index,
                other: reference.index,
                point: point.position,
                normal: manifold.normal,
                depth: margin - point.separation,
                friction: material.friction,
                restitution: material.restitution,
                surfaceMaterial: reference.body.definition.material
            )
        }
    }

    private func posed(
        _ body: DynamicBody, _ start: SIMD3<Float>, _ end: SIMD3<Float>
    ) -> (SIMD3<Float>, SIMD3<Float>) {
        (body.position + body.orientation.act(start), body.position + body.orientation.act(end))
    }

    private func segmentContact(
        _ firstSegment: (SIMD3<Float>, SIMD3<Float>),
        _ secondSegment: (SIMD3<Float>, SIMD3<Float>),
        radii: (Float, Float)
    ) -> DynamicContact? {
        let (onFirst, onSecond) = DynamicCollisionMath.closestPoints(firstSegment, secondSegment)
        let delta = onFirst - onSecond
        let distance = simd_length(delta)
        let reach = radii.0 + radii.1 + margin
        guard distance < reach else { return nil }
        let normal = distance > Float.ulpOfOne
            ? delta / distance
            : DynamicCollisionMath.fallbackNormal
        return DynamicContact(
            body: first.index,
            other: second.index,
            point: onSecond + normal * radii.1,
            normal: normal,
            depth: reach - distance,
            friction: material.friction,
            restitution: material.restitution,
            surfaceMaterial: second.body.definition.material
        )
    }

    /// A hull and a radial volume: each one's samples against the other's volume.
    private func sampled(_ firstVolume: Int, _ secondVolume: Int) -> [DynamicContact] {
        directional(first, volume: firstVolume, against: second, volume: secondVolume)
            + directional(second, volume: secondVolume, against: first, volume: firstVolume)
    }

    private func directional(
        _ sampling: DynamicPairBody, volume samplingVolume: Int,
        against obstacle: DynamicPairBody, volume obstacleVolume: Int
    ) -> [DynamicContact] {
        let sampled = sampling.body.definition.volumes[samplingVolume]
        let target = obstacle.body.definition.volumes[obstacleVolume]
        let inverse = obstacle.body.orientation.inverse
        let radius = sampled.skinRadius + margin
        let points = sampled.contactSamples(
            position: sampling.body.position, orientation: sampling.body.orientation
        )
        return points.compactMap { point in
            let local = inverse.act(point - obstacle.body.position)
            guard let hit = target.penetration(of: local, radius: radius) else { return nil }
            let normal = obstacle.body.orientation.act(hit.normal)
            return DynamicContact(
                body: sampling.index,
                other: obstacle.index,
                point: point - normal * (radius - hit.depth),
                normal: normal,
                depth: hit.depth,
                friction: material.friction,
                restitution: material.restitution,
                surfaceMaterial: obstacle.body.definition.material
            )
        }
    }
}
