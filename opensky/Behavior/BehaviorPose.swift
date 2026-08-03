// The pose currency of the behavior evaluator (issue #187): what a generator
// returns, and the blend math that mixes two of them.
//
// A pose here is dense — one `HKABonePose` per skeleton bone, seeded from the
// skeleton's reference pose — rather than the sparse
// `[HKABoneTransformSample]` a clip samples into. Dense is what blending needs:
// two children that animate different bone subsets must still mix bone by bone,
// and a bone neither child animates must come out as the reference pose rather
// than as a hole. `SkeletonPoseMath.worldMatrices(skeleton:samples:)` composes
// the same way, starting from the reference pose and overwriting the sampled
// bones, so the two layers agree on what an unanimated bone is.
//
// Root motion is carried beside the pose and never applied to it. The root
// bone of a Skyrim rig is authored with the clip's world travel baked in, so a
// walk clip walks the whole skeleton off the origin if the root is composed
// like any other bone. Item 14.5 hands the delta to the character controller
// and the controller decides where the character ends up; this layer only
// measures it.

import Foundation
import simd

/// The travel one update extracted from the root bone: how far the character
/// moved and how far it turned, in the root bone's own local frame. Never
/// applied to `BehaviorPose.bones`.
nonisolated struct BehaviorRootMotion: Equatable, Sendable {
    var translation: SIMD3<Float>
    var rotation: simd_quatf

    static let identity = BehaviorRootMotion(
        translation: SIMD3<Float>(), rotation: simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)
    )

    static func == (lhs: BehaviorRootMotion, rhs: BehaviorRootMotion) -> Bool {
        lhs.translation == rhs.translation && lhs.rotation.vector == rhs.rotation.vector
    }
}

/// One evaluated pose: local TRS per skeleton bone, plus the root motion the
/// generators under it extracted.
nonisolated struct BehaviorPose: Equatable {
    var bones: [HKABonePose]
    var rootMotion: BehaviorRootMotion

    init(bones: [HKABonePose], rootMotion: BehaviorRootMotion = .identity) {
        self.bones = bones
        self.rootMotion = rootMotion
    }
}

/// The skeleton a behavior graph instance poses. Kept separate from
/// `HKASkeleton` so the evaluator can be unit-tested against a three-bone rig
/// built in code, with no packfile in the way.
nonisolated struct BehaviorSkeleton: Equatable {
    let boneNames: [String]
    let referencePose: [HKABonePose]
    /// The bone whose animated travel is extracted rather than composed. On
    /// every vanilla Skyrim rig this is bone 0, `NPC Root [Root]`.
    let rootBoneIndex: Int

    init(boneNames: [String], referencePose: [HKABonePose], rootBoneIndex: Int = 0) {
        self.boneNames = boneNames
        self.referencePose = referencePose
        self.rootBoneIndex = rootBoneIndex
    }

    init(_ skeleton: HKASkeleton, rootBoneIndex: Int = 0) {
        self.init(
            boneNames: skeleton.boneNames,
            referencePose: skeleton.referencePose,
            rootBoneIndex: rootBoneIndex
        )
    }

    var boneCount: Int {
        referencePose.count
    }

    /// A pose holding nothing but the reference pose. This is what a generator
    /// with no semantics of its own returns, and what a blend of no children
    /// falls back to.
    var restPose: BehaviorPose {
        BehaviorPose(bones: referencePose)
    }
}

/// Pure pose math: blending, sample application, and root-motion extraction.
/// No file loading and no graph state, so every rule below is unit-testable
/// against hand-computed values.
nonisolated enum BehaviorPoseMath {
    /// The identity quaternion, spelled once.
    static let identityRotation = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)

    /// Blends `lhs` toward `rhs` by `weight`, clamped to [0, 1]. Translation
    /// and scale interpolate linearly; rotation interpolates along the shortest
    /// arc, which is what makes a 350-degree turn blend through 0 rather than
    /// the long way round.
    ///
    /// Bone counts that disagree are not a fault: the shorter list wins, and
    /// the extra bones of the longer one are kept as they are. A clip bound to
    /// a rig with fewer bones than the character's is ordinary in modded data.
    static func blend(_ lhs: BehaviorPose, _ rhs: BehaviorPose, weight: Float)
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

    static func blend(_ lhs: HKABonePose, _ rhs: HKABonePose, weight: Float)
        -> HKABonePose
    {
        let amount = clamped(weight)
        return HKABonePose(
            translation: mix(lhs.translation, rhs.translation, amount),
            rotation: slerp(lhs.rotation, rhs.rotation, amount),
            scale: mix(lhs.scale, rhs.scale, amount)
        )
    }

    static func blend(
        _ lhs: BehaviorRootMotion,
        _ rhs: BehaviorRootMotion,
        weight: Float
    ) -> BehaviorRootMotion {
        let amount = clamped(weight)
        return BehaviorRootMotion(
            translation: mix(lhs.translation, rhs.translation, amount),
            rotation: slerp(lhs.rotation, rhs.rotation, amount)
        )
    }

    /// Normalized weight blend of any number of children, folded left to right:
    /// after i children of total weight W, the next child of weight w enters at
    /// w / (W + w). For two children of weights a and b this is exactly
    /// `blend(first, second, weight: b / (a + b))`, which is the value the unit
    /// tests hand-compute against.
    ///
    /// Children of non-positive weight are dropped rather than normalized to
    /// zero, because a blender whose weights all fall to zero must produce the
    /// reference pose rather than a divide by zero. `fallback` is that pose.
    static func blend(
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
    nonisolated struct MaskedChild {
        let pose: BehaviorPose
        let weight: Float
        let boneWeights: [Float]?

        /// This child's effective weight on one bone. Bones past the end of the
        /// mask contribute at full weight: a mask shorter than the skeleton is
        /// ordinary in modded data, and treating the tail as zero would silently
        /// drop every bone the author did not reach.
        func weight(ofBone index: Int) -> Float {
            guard let boneWeights, boneWeights.indices.contains(index) else {
                return weight
            }
            return weight * boneWeights[index]
        }
    }

    /// Weight blend of any number of children, each masked per bone.
    ///
    /// This is what a vanilla upper-body blend needs: Skyrim's player graph
    /// blends a full-body locomotion pose with a left-arm pose and a right-arm
    /// pose, and each of the arm children carries an `hkbBoneWeightArray` that
    /// is 1 on its own arm and 0 everywhere else. Blending them without the
    /// mask averages three unrelated poses over the whole skeleton, which pulls
    /// limbs apart rather than layering them (issue #189).
    ///
    /// The fold is the same left-to-right normalized one
    /// `blend(children:fallback:)` performs, run once per bone, so a child with
    /// no mask produces exactly the unmasked result.
    static func blend(masked children: [MaskedChild], fallback: BehaviorPose)
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
    static func applying(
        _ samples: [HKABoneTransformSample],
        to base: [HKABonePose]
    ) -> [HKABonePose] {
        var bones = base
        for sample in samples where bones.indices.contains(sample.boneIndex) {
            bones[sample.boneIndex] = sample.pose
        }
        return bones
    }

    /// The travel between two samples of the same root bone, expressed in the
    /// earlier sample's frame: `rotation` is the turn from `previous` to
    /// `current`, `translation` their difference.
    static func rootMotion(from previous: HKABonePose, to current: HKABonePose)
        -> BehaviorRootMotion
    {
        BehaviorRootMotion(
            translation: current.translation - previous.translation,
            rotation: normalized(previous.rotation.inverse * current.rotation)
        )
    }

    /// Adds `next` after `first`, which is how a clip that looped mid-update
    /// reports its travel: the run to the end of the clip, then the run from
    /// the start.
    static func concatenating(
        _ first: BehaviorRootMotion,
        _ next: BehaviorRootMotion
    ) -> BehaviorRootMotion {
        BehaviorRootMotion(
            translation: first.translation + first.rotation.act(next.translation),
            rotation: normalized(first.rotation * next.rotation)
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
    static func slerp(_ lhs: simd_quatf, _ rhs: simd_quatf, _ amount: Float)
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
    static func normalized(_ rotation: simd_quatf) -> simd_quatf {
        let lengthSquared = simd_length_squared(rotation.vector)
        guard lengthSquared.isFinite, lengthSquared > 1e-12 else {
            return identityRotation
        }
        return simd_quatf(vector: rotation.vector / lengthSquared.squareRoot())
    }
}
