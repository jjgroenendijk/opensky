// Mirrored clips (`hkbClipGenerator` flag 4): each sampled bone is written to its
// partner bone, reflected through the plane of `m_mirrorAxis`
// (docs/engine/behavior-runtime.md#mirrored-clips).

import Foundation
import OpenSkyFormatsAnimation
import simd

/// The per-bone rotations that reflect a pose of one skeleton onto its mirror side.
nonisolated public struct BehaviorMirror: Sendable {
    /// A rotation this close to an axis-aligned one is snapped to it.
    static let snapThreshold: Float = 0.9

    private let partners: [Int]
    private let parents: [Int]
    /// `I(b)`: the change of frame from bone b to its partner.
    private let frames: [simd_quatf]
    /// `I(-1)`: the 180 degree turn about the mirror axis.
    private let axisTurn: simd_quatf

    public init(_ info: HKBMirroredSkeletonInfo, skeleton: BehaviorSkeleton) {
        let count = skeleton.referencePose.count
        let axis = SIMD3(info.mirrorAxis.x, info.mirrorAxis.y, info.mirrorAxis.z)
        axisTurn = simd_quatf(ix: axis.x, iy: axis.y, iz: axis.z, r: 0)
        partners = (0 ..< count).map { bone in
            info.bonePairMap.indices.contains(bone) && (0 ..< count)
                .contains(info.bonePairMap[bone]) ? info.bonePairMap[bone] : bone
        }
        parents = (0 ..< count).map(skeleton.parent(of:))
        let model = Self.modelRotations(skeleton)
        let turn = axisTurn
        frames = (0 ..< count).map { [partners] bone in
            Self.snapped(simd_normalize(model[bone].conjugate * turn * model[partners[bone]]))
        }
    }

    /// Writes each sample to its partner bone in the mirrored frame.
    public func mirroring(
        _ samples: [HKABoneTransformSample], isAdditive: Bool
    ) -> [HKABoneTransformSample] {
        samples.map { sample in
            guard partners.indices.contains(sample.boneIndex) else { return sample }
            let bone = partners[sample.boneIndex]
            let parentFrame = frame(of: parents[bone])
            let right = isAdditive ? parentFrame.conjugate : frames[bone].conjugate
            let pose = sample.pose
            return HKABoneTransformSample(
                boneIndex: bone,
                pose: HKABonePose(
                    translation: -parentFrame.act(pose.translation),
                    rotation: simd_normalize(parentFrame * pose.rotation * right),
                    scale: pose.scale
                )
            )
        }
    }

    /// Root travel reflected through the mirror plane.
    public func mirroring(_ motion: BehaviorRootMotion) -> BehaviorRootMotion {
        BehaviorRootMotion(
            translation: -axisTurn.act(motion.translation),
            rotation: simd_normalize(axisTurn * motion.rotation * axisTurn.conjugate),
            isExtracted: motion.isExtracted
        )
    }

    private func frame(of bone: Int) -> simd_quatf {
        frames.indices.contains(bone) ? frames[bone] : axisTurn
    }

    private static func modelRotations(_ skeleton: BehaviorSkeleton) -> [simd_quatf] {
        var model: [simd_quatf] = []
        model.reserveCapacity(skeleton.referencePose.count)
        for (bone, pose) in skeleton.referencePose.enumerated() {
            let parent = skeleton.parent(of: bone)
            let parentRotation = (0 ..< bone).contains(parent)
                ? model[parent]
                : simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)
            model.append(simd_normalize(parentRotation * pose.rotation))
        }
        return model
    }

    /// The axis-aligned rotation within the threshold of `rotation`, else `rotation`.
    static func snapped(_ rotation: simd_quatf) -> simd_quatf {
        axisAligned.first { abs(simd_dot($0.vector, rotation.vector)) >= snapThreshold }
            ?? rotation
    }

    /// The 24 rotations that map each axis onto an axis.
    static let axisAligned: [simd_quatf] = {
        let half: Float = 0.5
        let root = Float(0.5).squareRoot()
        var result: [SIMD4<Float>] = (0 ..< 4).map { axis in
            var unit = SIMD4<Float>()
            unit[axis] = 1
            return unit
        }
        for first in 0 ..< 4 {
            for second in first + 1 ..< 4 {
                for sign: Float in [1, -1] {
                    var pair = SIMD4<Float>()
                    pair[first] = root
                    pair[second] = sign * root
                    result.append(pair)
                }
            }
        }
        for bits in 0 ..< 8 {
            result.append(SIMD4(
                half,
                bits & 1 == 0 ? half : -half,
                bits & 2 == 0 ? half : -half,
                bits & 4 == 0 ? half : -half
            ))
        }
        return result.map { simd_quatf(vector: $0) }
    }()
}
