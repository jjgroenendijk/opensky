// The pose type of the behavior evaluator and its blend math. A pose is dense,
// one `HKABonePose` per bone from the reference pose, so children that animate
// different bones still blend bone by bone. Root motion is carried beside the
// pose and never applied to it; the character controller decides where the
// character ends up.

import Foundation
import OpenSkyFormatsAnimation
import simd

/// The travel one update extracted from the root bone: how far the character
/// moved and how far it turned, in the root bone's own local frame. Never
/// applied to `BehaviorPose.bones`.
nonisolated public struct BehaviorRootMotion: Equatable, Sendable {
    public var translation: SIMD3<Float>
    public var rotation: simd_quatf
    /// True when this travel came from a clip with extracted motion, so the graph
    /// moves the character this step. It describes the data, not the magnitude;
    /// `LocomotionBridge` branches on it.
    public var isExtracted: Bool

    public init(
        translation: SIMD3<Float>,
        rotation: simd_quatf,
        isExtracted: Bool = false
    ) {
        self.translation = translation
        self.rotation = rotation
        self.isExtracted = isExtracted
    }

    public static let identity = BehaviorRootMotion(
        translation: SIMD3<Float>(), rotation: simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)
    )

    public static func == (lhs: BehaviorRootMotion, rhs: BehaviorRootMotion) -> Bool {
        lhs.translation == rhs.translation
            && lhs.rotation.vector == rhs.rotation.vector
            && lhs.isExtracted == rhs.isExtracted
    }
}

/// One evaluated pose: local TRS per skeleton bone, plus the root motion the
/// generators under it extracted.
nonisolated public struct BehaviorPose: Equatable, Sendable {
    public var bones: [HKABonePose]
    public var rootMotion: BehaviorRootMotion

    public init(bones: [HKABonePose], rootMotion: BehaviorRootMotion = .identity) {
        self.bones = bones
        self.rootMotion = rootMotion
    }
}

/// The skeleton a behavior graph instance poses. Kept separate from
/// `HKASkeleton` so the evaluator can be unit-tested against a three-bone rig
/// built in code, with no packfile in the way.
nonisolated public struct BehaviorSkeleton: Equatable, Sendable {
    public let referencePose: [HKABonePose]
    /// The bone whose animated travel is extracted rather than composed. On
    /// every vanilla Skyrim rig this is bone 0, `NPC Root [Root]`.
    public let rootBoneIndex: Int

    public init(referencePose: [HKABonePose], rootBoneIndex: Int = 0) {
        self.referencePose = referencePose
        self.rootBoneIndex = rootBoneIndex
    }

    public init(_ skeleton: HKASkeleton, rootBoneIndex: Int = 0) {
        self.init(referencePose: skeleton.referencePose, rootBoneIndex: rootBoneIndex)
    }

    /// A pose holding nothing but the reference pose. This is what a generator
    /// with no semantics of its own returns, and what a blend of no children
    /// falls back to.
    public var restPose: BehaviorPose {
        BehaviorPose(bones: referencePose)
    }
}

/// Pure pose math: blending, sample application, and root-motion extraction.
/// No file loading and no graph state, so every rule below is unit-testable
/// against hand-computed values.
nonisolated public enum BehaviorPoseMath: Sendable {
    /// The identity quaternion, spelled once.
    public static let identityRotation = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)

    /// Blends `lhs` toward `rhs` by `weight`, clamped to [0, 1]. Rotation takes the
    /// shortest arc. When bone counts differ, the extra bones of the longer pose are
    /// kept as they are.
    public static func blend(_ lhs: BehaviorPose, _ rhs: BehaviorPose, weight: Float)
        -> BehaviorPose
    {
        let amount = clamped(weight)
        var bones = lhs.bones
        let shared = min(lhs.bones.count, rhs.bones.count)
        for index in 0 ..< shared {
            bones[index] = blend(lhs.bones[index], rhs.bones[index], weight: amount)
        }
        if rhs.bones.count > lhs.bones.count {
            bones += rhs.bones[shared...]
        }
        return BehaviorPose(
            bones: bones,
            rootMotion: blend(lhs.rootMotion, rhs.rootMotion, weight: amount)
        )
    }

    public static func blend(_ lhs: HKABonePose, _ rhs: HKABonePose, weight: Float)
        -> HKABonePose
    {
        let amount = clamped(weight)
        return HKABonePose(
            translation: mix(lhs.translation, rhs.translation, amount),
            rotation: slerp(lhs.rotation, rhs.rotation, amount),
            scale: mix(lhs.scale, rhs.scale, amount)
        )
    }

    public static func blend(
        _ lhs: BehaviorRootMotion,
        _ rhs: BehaviorRootMotion,
        weight: Float
    ) -> BehaviorRootMotion {
        let amount = clamped(weight)
        return BehaviorRootMotion(
            translation: mix(lhs.translation, rhs.translation, amount),
            rotation: slerp(lhs.rotation, rhs.rotation, amount),
            // Authority survives a blend: a pose mixing an extracted-motion
            // clip with an in-place one is still being driven by the data, at
            // the blended weight, and the in-place side contributes zero.
            isExtracted: lhs.isExtracted || rhs.isExtracted
        )
    }

    /// Normalized weight blend of any number of children, folded left to right: the
    /// next child of weight w enters at w / (W + w). Non-positive weights are dropped;
    /// with no weight left the result is `fallback`.
    public static func blend(
        children: [(pose: BehaviorPose, weight: Float)],
        fallback: BehaviorPose
    ) -> BehaviorPose {
        let contributing = children.filter { $0.weight > 0 && $0.weight.isFinite }
        guard var result = contributing.first?.pose else { return fallback }
        var total = contributing[0].weight
        for child in contributing.dropFirst() {
            let next = total + child.weight
            guard next > 0 else { continue }
            result = blend(result, child.pose, weight: child.weight / next)
            total = next
        }
        return result
    }

    /// One child of a per-bone blend: its pose, its whole-pose weight, and the
    /// per-bone mask that scales that weight bone by bone (`hkbBoneWeightArray`).
    /// A nil mask means the child contributes at full weight everywhere.
    nonisolated public struct MaskedChild: Sendable {
        public let pose: BehaviorPose
        public let weight: Float
        public let boneWeights: [Float]?

        /// This child's effective weight on one bone. Bones past the end of the
        /// mask contribute at full weight: a mask shorter than the skeleton is
        /// ordinary in modded data, and treating the tail as zero would silently
        /// drop every bone the author did not reach.
        public func weight(ofBone index: Int) -> Float {
            guard let boneWeights, boneWeights.indices.contains(index) else {
                return weight
            }
            return weight * boneWeights[index]
        }
    }

    /// Weight blend of any number of children, each masked per bone by its
    /// `hkbBoneWeightArray`. The vanilla upper-body blend needs this. Same fold as
    /// `blend(children:fallback:)`, run per bone.
    public static func blend(masked children: [MaskedChild], fallback: BehaviorPose)
        -> BehaviorPose
    {
        let contributing = children.filter { $0.weight > 0 && $0.weight.isFinite }
        guard !contributing.isEmpty else { return fallback }
        let boneCount = contributing.map(\.pose.bones.count).max() ?? 0
        guard boneCount > 0 else { return fallback }
        var bones = fallback.bones
        if bones.count < boneCount {
            bones += Array(repeating: bones.last ?? identityPose, count: boneCount - bones.count)
        }
        for index in 0 ..< boneCount {
            if let blended = blend(bone: index, of: contributing) {
                bones[index] = blended
            }
        }
        return BehaviorPose(bones: bones, rootMotion: fallback.rootMotion)
    }

    /// One bone folded across the children that reach it, or nil when none do.
    private static func blend(bone index: Int, of children: [MaskedChild]) -> HKABonePose? {
        var result: HKABonePose?
        var total: Float = 0
        for child in children {
            guard child.pose.bones.indices.contains(index) else { continue }
            let weight = child.weight(ofBone: index)
            guard weight > 0, weight.isFinite else { continue }
            guard let current = result else {
                result = child.pose.bones[index]
                total = weight
                continue
            }
            let next = total + weight
            guard next > 0 else { continue }
            result = blend(current, child.pose.bones[index], weight: weight / next)
            total = next
        }
        return result
    }

    /// A bone at rest, used only to pad a fallback pose shorter than the
    /// children being blended over it.
    private static let identityPose = HKABonePose(
        translation: SIMD3<Float>(),
        rotation: identityRotation,
        scale: SIMD3<Float>(repeating: 1)
    )

    /// Overwrites the bones a clip sampled onto a copy of `base`, dropping
    /// samples that name a bone the skeleton does not have.
    public static func applying(
        _ samples: [HKABoneTransformSample],
        to base: [HKABonePose]
    ) -> [HKABonePose] {
        var bones = base
        for sample in samples where bones.indices.contains(sample.boneIndex) {
            bones[sample.boneIndex] = sample.pose
        }
        return bones
    }

    /// The travel between two samples of the same root bone, in the earlier sample's
    /// frame. `isExtracted` is the caller's to state.
    public static func rootMotion(
        from previous: HKABonePose,
        to current: HKABonePose,
        isExtracted: Bool = false
    ) -> BehaviorRootMotion {
        BehaviorRootMotion(
            translation: current.translation - previous.translation,
            rotation: normalized(previous.rotation.inverse * current.rotation),
            isExtracted: isExtracted
        )
    }

    /// Adds `next` after `first`, which is how a clip that looped mid-update
    /// reports its travel: the run to the end of the clip, then the run from
    /// the start.
    public static func concatenating(
        _ first: BehaviorRootMotion,
        _ next: BehaviorRootMotion
    ) -> BehaviorRootMotion {
        BehaviorRootMotion(
            translation: first.translation + first.rotation.act(next.translation),
            rotation: normalized(first.rotation * next.rotation),
            isExtracted: first.isExtracted || next.isExtracted
        )
    }

    // MARK: - Primitives

    private static func clamped(_ weight: Float) -> Float {
        guard weight.isFinite else { return 0 }
        return min(max(weight, 0), 1)
    }

    private static func mix(_ lhs: SIMD3<Float>, _ rhs: SIMD3<Float>, _ amount: Float)
        -> SIMD3<Float>
    {
        lhs + (rhs - lhs) * amount
    }

    /// Shortest-arc slerp that tolerates the degenerate inputs decoded data can
    /// carry: a zero-length quaternion blends as if it were the identity.
    public static func slerp(_ lhs: simd_quatf, _ rhs: simd_quatf, _ amount: Float)
        -> simd_quatf
    {
        let start = normalized(lhs)
        let end = normalized(rhs)
        if amount <= 0 {
            return start
        }
        if amount >= 1 {
            return end
        }
        return normalized(simd_slerp(start, end, amount))
    }

    /// A unit quaternion, falling back to the identity when the input has no
    /// length to normalize. Malformed input must not produce a NaN pose.
    public static func normalized(_ rotation: simd_quatf) -> simd_quatf {
        let lengthSquared = simd_length_squared(rotation.vector)
        guard lengthSquared.isFinite, lengthSquared > 1e-12 else {
            return identityRotation
        }
        return simd_quatf(vector: rotation.vector / lengthSquared.squareRoot())
    }
}
