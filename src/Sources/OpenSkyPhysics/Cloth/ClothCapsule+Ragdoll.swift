// The calf capsules a cape collides with, from the actor's ragdoll bodies
// (docs/engine/cape-cloth.md#collision).

public import simd

nonisolated extension ClothCapsule {
    static let calfBones: Set = ["NPC L Calf [LClf]", "NPC R Calf [RClf]"]
    /// The game doubles a calf's physics radius for the cape.
    static let calfRadiusFactor: Float = 2

    /// One capsule per capsule shape on a calf body, in world space. `boneToActor` is the
    /// animated pose by bone name, in the actor space `actorToWorld` places.
    public static func calves(
        ragdoll: RagdollDefinition,
        boneToActor: [String: float4x4],
        actorToWorld: float4x4
    ) -> [Self] {
        ragdoll.bones.filter { calfBones.contains($0.boneName) }.flatMap { bone -> [Self] in
            guard let pose = boneToActor[bone.boneName] else { return [] }
            let bodyToWorld = actorToWorld * pose * bone.bindBoneInverse
            let center = bone.body.centerOfMass
            return bone.body.volumes.compactMap { volume in
                guard case let .radial(first, second, radius) = volume, first != second
                else { return nil }
                return Self(
                    start: transformed(first + center, by: bodyToWorld),
                    end: transformed(second + center, by: bodyToWorld),
                    radius: radius * calfRadiusFactor
                )
            }
        }
    }

    private static func transformed(_ point: SIMD3<Float>, by matrix: float4x4) -> SIMD3<Float> {
        let moved = matrix * SIMD4<Float>(point, 1)
        return SIMD3<Float>(moved.x, moved.y, moved.z)
    }
}
