// Additive clips (`m_blendHint` 1 or 2) store per-bone changes, not poses. Vanilla uses
// them for the body-weight layers, such as `mt_idle_skinny.hkx` (docs/formats/hka-animation.md).

import Foundation
import OpenSkyFormatsAnimation
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

    /// `change` added to `base` at `weight`: the rotation turns the bone in its own frame,
    /// and the translation adds in the parent's frame.
    public static func adding(_ change: HKABonePose, to base: HKABonePose, weight: Float)
        -> HKABonePose
    {
        let amount = clamped(weight)
        let rotation = slerp(identityRotation, change.rotation, amount)
        return HKABonePose(
            translation: base.translation + change.translation * amount,
            rotation: normalized(base.rotation * rotation),
            scale: base.scale * mix(SIMD3<Float>(repeating: 1), change.scale, amount)
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
