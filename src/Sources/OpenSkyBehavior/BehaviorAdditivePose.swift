// Additive clips (`m_blendHint` 1) store per-bone changes, not poses. Vanilla uses
// them for the body-weight layers, such as `mt_idle_skinny.hkx` (docs/formats/hka-animation.md).

import Foundation
public import OpenSkyFormatsAnimation
import simd

nonisolated extension BehaviorPoseMath {
    /// A change that moves nothing: the base an additive clip's samples land on.
    public static let unchangedBone = HKABonePose(
        translation: SIMD3<Float>(), rotation: identityRotation, scale: SIMD3<Float>(repeating: 1)
    )

    /// An additive pose with no change on any of `count` bones.
    public static func unchanged(boneCount count: Int) -> BehaviorPose {
        BehaviorPose(bones: Array(repeating: unchangedBone, count: count), isAdditive: true)
    }

    /// `change` applied in the parent's frame on top of `base`, then mixed with `base` at
    /// `weight`: the rotation by a sign-aligned normalised lerp, as the game's Havok does.
    public static func adding(_ change: HKABonePose, to base: HKABonePose, weight: Float)
        -> HKABonePose
    {
        let amount = max(weight, 0)
        let full = HKABonePose(
            translation: change.translation + change.rotation.act(base.translation),
            rotation: change.rotation * base.rotation,
            scale: change.scale * base.scale
        )
        let aligned = simd_dot(base.rotation.vector, full.rotation.vector) < 0 ? -amount : amount
        return HKABonePose(
            translation: base.translation + (full.translation - base.translation) * amount,
            rotation: normalized(simd_quatf(
                vector: base.rotation.vector * (1 - amount) + full.rotation.vector * aligned
            )),
            scale: base.scale + (full.scale - base.scale) * amount
        )
    }

    /// `layer` added to `base` bone by bone, each bone at `weight(bone)`. The result is
    /// additive only when `base` is.
    public static func adding(
        _ layer: BehaviorPose, to base: BehaviorPose, weight: (Int) -> Float
    ) -> BehaviorPose {
        var result = base
        for bone in result.bones.indices where layer.bones.indices.contains(bone) {
            result.bones[bone] = adding(
                layer.bones[bone],
                to: base.bones[bone],
                weight: weight(bone)
            )
        }
        return result
    }
}

nonisolated extension BehaviorSkeleton {
    /// `pose` as a full pose: an additive one is added to the reference pose.
    public func absolute(_ pose: BehaviorPose) -> BehaviorPose {
        guard pose.isAdditive else { return pose }
        var result = BehaviorPoseMath.adding(pose, to: restPose) { _ in 1 }
        result.rootMotion = pose.rootMotion
        return result
    }
}
