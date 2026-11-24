// A living actor's ragdoll bodies where its animation holds them, which the camera sweep
// touches (docs/engine/actor-camera-fade.md#which-actor-fades).

public import simd

/// One ragdoll body as a world capsule; a sphere when `start == end`.
nonisolated public struct RagdollWorldCapsule: Equatable, Sendable {
    public let start: SIMD3<Float>
    public let end: SIMD3<Float>
    public let radius: Float
}

nonisolated extension RagdollDefinition {
    /// Every posed bone's bodies in world space. A hull becomes the sphere around its
    /// points. `boneToActor` is the animated pose by bone name, in the actor space
    /// `actorToWorld` places, and `scale` is the scale that space carries.
    public func worldCapsules(
        boneToActor: [String: float4x4], actorToWorld: float4x4, scale: Float
    ) -> [RagdollWorldCapsule] {
        bones.flatMap { bone -> [RagdollWorldCapsule] in
            guard let pose = boneToActor[bone.boneName] else { return [] }
            let bodyToWorld = actorToWorld * pose * bone.bindBoneInverse
            let center = bone.body.centerOfMass
            func world(_ point: SIMD3<Float>) -> SIMD3<Float> {
                let moved = bodyToWorld * SIMD4<Float>(point + center, 1)
                return SIMD3(moved.x, moved.y, moved.z)
            }
            return bone.body.volumes.compactMap { volume in
                switch volume {
                case let .radial(first, second, radius):
                    return RagdollWorldCapsule(
                        start: world(first), end: world(second), radius: radius * scale
                    )
                case let .hull(points, _):
                    guard !points.isEmpty else { return nil }
                    let middle = points.reduce(SIMD3<Float>.zero, +) / Float(points.count)
                    let reach = points.map { simd_distance($0, middle) }.max() ?? 0
                    let centre = world(middle)
                    return RagdollWorldCapsule(start: centre, end: centre, radius: reach * scale)
                }
            }
        }
    }
}
