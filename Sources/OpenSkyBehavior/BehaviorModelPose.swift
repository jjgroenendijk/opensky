// A pose composed into model space, for the modifiers that aim, twist, or
// solve IK. Scale is ignored: every vanilla rig has unit bone scale. Model space
// is Havok's: +Y forward, +X right, +Z up.

import Foundation
import OpenSkyFormatsAnimation
import simd

nonisolated public struct BehaviorModelPose: Sendable {
    public private(set) var rotations: [simd_quatf]
    public private(set) var translations: [SIMD3<Float>]
    public let parents: [Int]

    public init(_ pose: BehaviorPose, skeleton: BehaviorSkeleton) {
        let count = pose.bones.count
        parents = (0 ..< count).map { skeleton.parent(of: $0) }
        rotations = [simd_quatf](repeating: BehaviorPoseMath.identityRotation, count: count)
        translations = [SIMD3<Float>](repeating: SIMD3(), count: count)
        compose(pose)
    }

    public func contains(_ bone: Int) -> Bool {
        rotations.indices.contains(bone)
    }

    /// Recomposes every bone. Parents come before children in every Havok
    /// skeleton; a parent index that does not is treated as a root.
    public mutating func compose(_ pose: BehaviorPose) {
        for index in pose.bones.indices where rotations.indices.contains(index) {
            let local = pose.bones[index]
            let parent = parents[index]
            guard parent >= 0, parent < index else {
                rotations[index] = local.rotation
                translations[index] = local.translation
                continue
            }
            rotations[index] = BehaviorPoseMath.normalized(rotations[parent] * local.rotation)
            translations[index] = translations[parent] + rotations[parent].act(local.translation)
        }
    }

    /// Turns `bone` by `delta`, given in model space, and recomposes, so the
    /// bone's children follow it.
    public mutating func rotate(_ bone: Int, by delta: simd_quatf, in pose: inout BehaviorPose) {
        guard contains(bone), pose.bones.indices.contains(bone) else { return }
        let parent = parents[bone]
        let parentRotation = parent >= 0 && parent < bone
            ? rotations[parent] : BehaviorPoseMath.identityRotation
        let model = BehaviorPoseMath.normalized(delta * rotations[bone])
        let local = BehaviorPoseMath.normalized(parentRotation.inverse * model)
        let old = pose.bones[bone]
        pose.bones[bone] = HKABonePose(
            translation: old.translation, rotation: local, scale: old.scale
        )
        compose(pose)
    }

    /// The bones from `start` down to `end`, start first, or empty when `end`
    /// does not descend from `start`.
    public func chain(from start: Int, to end: Int) -> [Int] {
        guard contains(start), contains(end) else { return [] }
        var chain = [end]
        var current = end
        while current != start {
            current = parents[current]
            guard current >= 0, chain.count <= parents.count else { return [] }
            chain.append(current)
        }
        return chain.reversed()
    }

    /// The shortest rotation that turns direction `from` onto `to`.
    public static func rotation(from: SIMD3<Float>, to: SIMD3<Float>) -> simd_quatf {
        let lhs = simd_normalize(from)
        let rhs = simd_normalize(to)
        guard lhs.x.isFinite, rhs.x.isFinite else { return BehaviorPoseMath.identityRotation }
        let dot = simd_dot(lhs, rhs)
        if dot > 0.999_999 {
            return BehaviorPoseMath.identityRotation
        }
        if dot < -0.999_999 {
            let side = abs(lhs.x) < 0.9 ? SIMD3<Float>(1, 0, 0) : SIMD3<Float>(0, 1, 0)
            return simd_quatf(angle: .pi, axis: simd_normalize(simd_cross(lhs, side)))
        }
        return simd_quatf(from: lhs, to: rhs)
    }

    public static func vector3(_ vector: SIMD4<Float>) -> SIMD3<Float> {
        SIMD3(vector.x, vector.y, vector.z)
    }

    /// `rotation` scaled to `fraction` of its angle.
    public static func partial(_ rotation: simd_quatf, _ fraction: Float) -> simd_quatf {
        BehaviorPoseMath.slerp(BehaviorPoseMath.identityRotation, rotation, fraction)
    }
}
