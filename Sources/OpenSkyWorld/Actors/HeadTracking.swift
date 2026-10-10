// Turns an actor's neck and head toward what it looks at, on top of the clip it plays.
// The angles are measured from the body's forward axis, so they do not depend on how
// each bone's own axes point. Limits, shares, and speed are OpenSky's own.
// See docs/engine/head-tracking.md.

import OpenSkyFormatsCore
import simd

/// How far the head turns from the body's forward axis, in radians. Positive yaw
/// turns left, positive pitch looks up.
nonisolated public struct HeadLook: Equatable, Sendable {
    public var yaw: Float
    public var pitch: Float

    public static let forward = HeadLook(yaw: 0, pitch: 0)

    public init(yaw: Float, pitch: Float) {
        self.yaw = yaw
        self.pitch = pitch
    }
}

nonisolated public enum HeadTrackingCore {
    public static let neckBone = "NPC Neck [Neck]"
    public static let headBone = "NPC Head [Head]"
    public static let maximumYaw: Float = .pi / 3
    public static let maximumPitch: Float = .pi / 6
    /// A target further round than this is behind the actor, which looks ahead.
    public static let giveUpYaw: Float = .pi * 0.6
    /// The neck takes this part of the turn, and the head the rest.
    public static let neckShare: Float = 0.4
    /// Radians per second.
    public static let turnSpeed: Float = .pi

    /// The look from `eye` toward `target`, both in the actor's own frame: +Y forward,
    /// +Z up, as the skeleton is authored. Nil when the target is behind.
    public static func look(from eye: SIMD3<Float>, at target: SIMD3<Float>) -> HeadLook? {
        let offset = target - eye
        let flat = simd_length(SIMD2(offset.x, offset.y))
        guard flat > 0.001, offset.x.isFinite, offset.y.isFinite, offset.z.isFinite else {
            return nil
        }
        let yaw = atan2f(-offset.x, offset.y)
        guard abs(yaw) <= giveUpYaw else { return nil }
        return HeadLook(
            yaw: min(max(yaw, -maximumYaw), maximumYaw),
            pitch: min(max(atan2f(offset.z, flat), -maximumPitch), maximumPitch)
        )
    }

    /// `current` moved toward `goal` by at most `step` radians on each axis.
    public static func approach(_ current: HeadLook, _ goal: HeadLook, step: Float) -> HeadLook {
        func move(_ from: Float, _ to: Float) -> Float {
            from + min(max(to - from, -step), step)
        }
        return HeadLook(yaw: move(current.yaw, goal.yaw), pitch: move(current.pitch, goal.pitch))
    }

    /// `pose` with the neck and head turned by `look`. `parents` is the skeleton's
    /// parent index list in the pose's bone order. A skeleton without the bones is
    /// returned as is.
    public static func apply(
        _ look: HeadLook,
        to pose: SkeletonPose,
        parents: [Int]
    ) -> SkeletonPose {
        guard look != .forward, parents.count == pose.matrices.count else { return pose }
        var matrices = pose.matrices
        for (bone, share) in [(neckBone, neckShare), (headBone, 1 - neckShare)] {
            guard let root = pose.bones.index(of: bone), root < matrices.count else { continue }
            let pivot = SIMD3(
                matrices[root].columns.3.x,
                matrices[root].columns.3.y,
                matrices[root].columns.3.z
            )
            let turn = translation(pivot) * rotation(look, share: share) * translation(-pivot)
            for index in matrices.indices where isInside(index, root: root, parents: parents) {
                matrices[index] = turn * matrices[index]
            }
        }
        return SkeletonPose(bones: pose.bones, matrices: matrices)
    }

    private static func isInside(_ bone: Int, root: Int, parents: [Int]) -> Bool {
        var current = bone
        for _ in 0 ... parents.count {
            if current == root {
                return true
            }
            guard parents.indices.contains(current) else { return false }
            current = parents[current]
        }
        return false
    }

    private static func rotation(_ look: HeadLook, share: Float) -> float4x4 {
        let yaw = look.yaw * share
        let pitch = look.pitch * share
        let aroundZ = float4x4(
            SIMD4(cosf(yaw), sinf(yaw), 0, 0), SIMD4(-sinf(yaw), cosf(yaw), 0, 0),
            SIMD4(0, 0, 1, 0), SIMD4(0, 0, 0, 1)
        )
        let aroundX = float4x4(
            SIMD4(1, 0, 0, 0), SIMD4(0, cosf(pitch), sinf(pitch), 0),
            SIMD4(0, -sinf(pitch), cosf(pitch), 0), SIMD4(0, 0, 0, 1)
        )
        return aroundZ * aroundX
    }

    private static func translation(_ offset: SIMD3<Float>) -> float4x4 {
        var matrix = matrix_identity_float4x4
        matrix.columns.3 = SIMD4(offset, 1)
        return matrix
    }
}
