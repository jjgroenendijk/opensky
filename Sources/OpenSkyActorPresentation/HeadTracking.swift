// Turns an actor's neck and head toward what it looks at, on top of the clip it plays.
// The angles are measured from the body's forward axis, so they do not depend on how
// each bone's own axes point. Limits and speed come from `HeadTrackingSettings`; the
// shares are OpenSky's own. See docs/engine/head-tracking.md.

import OpenSkyFormatsAnimation
import OpenSkyFormatsCore
import simd

/// How far the head turns from the body's forward axis, in radians. Positive yaw
/// turns left, positive pitch looks up, and roll tilts around the forward axis.
nonisolated public struct HeadLook: Equatable, Sendable {
    public var yaw: Float
    public var pitch: Float
    public var roll: Float

    public static let forward = HeadLook(yaw: 0, pitch: 0)

    public init(yaw: Float, pitch: Float, roll: Float = 0) {
        self.yaw = yaw
        self.pitch = pitch
        self.roll = roll
    }

    /// This look with a lip track's head motion added on top.
    public func adding(_ motion: LipHeadMotion) -> HeadLook {
        HeadLook(yaw: yaw + motion.yaw, pitch: pitch + motion.pitch, roll: roll + motion.roll)
    }
}

nonisolated public enum HeadTrackingCore {
    public static let neckBone = "NPC Neck [Neck]"
    public static let headBone = "NPC Head [Head]"
    /// A target further round than this is behind the actor, which looks ahead.
    public static let giveUpYaw: Float = .pi * 0.6
    /// The neck takes this part of the turn, and the head the rest.
    public static let neckShare: Float = 0.4
    /// Below this, in radians, a turn has reached its goal.
    static let arrivedAngle: Float = 0.0001

    /// The look from `eye` toward `target`, both in the actor's own frame: +Y forward,
    /// +Z up, as the skeleton is authored. Nil when the target is behind.
    public static func look(
        from eye: SIMD3<Float>, at target: SIMD3<Float>,
        settings: HeadTrackingSettings = .vanilla
    ) -> HeadLook? {
        let offset = target - eye
        let flat = simd_length(SIMD2(offset.x, offset.y))
        guard flat > 0.001, offset.x.isFinite, offset.y.isFinite, offset.z.isFinite else {
            return nil
        }
        let yaw = atan2f(-offset.x, offset.y)
        guard abs(yaw) <= giveUpYaw else { return nil }
        return limited(HeadLook(yaw: yaw, pitch: atan2f(offset.z, flat)), settings: settings)
    }

    public static func limited(_ look: HeadLook, settings: HeadTrackingSettings) -> HeadLook {
        let yaw = settings.maximumYaw
        let pitch = settings.pitchRange
        return HeadLook(
            yaw: min(max(look.yaw, -yaw), yaw),
            pitch: min(max(look.pitch, pitch.lowerBound), pitch.upperBound),
            roll: look.roll
        )
    }

    /// One frame of a turn from `current` toward `goal`. A head at rest stays put while the
    /// goal is inside the dead zone; a turning head keeps going until it arrives, slowing
    /// down near the goal.
    public static func turn(
        _ current: HeadLook, toward goal: HeadLook, isTurning: Bool,
        deltaTime: Float, settings: HeadTrackingSettings
    ) -> (look: HeadLook, isTurning: Bool) {
        guard isTurning || !settings.isInsideDeadZone(current, goal: goal) else {
            return (current, false)
        }
        let remaining = max(abs(goal.yaw - current.yaw), abs(goal.pitch - current.pitch))
        let step = settings.turnSpeed(remaining: remaining) * max(deltaTime, 0)
        let next = approach(current, goal, step: step)
        let left = max(abs(goal.yaw - next.yaw), abs(goal.pitch - next.pitch))
        return (next, left > arrivedAngle)
    }

    /// The glance away from the target at `time` seconds: forward outside each cycle's
    /// glance window. `seed` gives each actor its own glances.
    public static func glance(at time: Float, seed: UInt32, timing: HeadGlanceTiming) -> HeadLook {
        let largest = max(abs(timing.offsetMin), abs(timing.offsetMax))
        guard time.isFinite, time >= 0, timing.resetPosition > 0, largest > 0 else {
            return .forward
        }
        let cycle = (time / timing.resetPosition).rounded(.down)
        let phase = time - cycle * timing.resetPosition
        let roll = SeededRoll(seed: seed, cycle: UInt32(truncatingIfNeeded: Int(cycle)))
        let stay = lerp(timing.stayInOffsetMin, timing.stayInOffsetMax, roll.value(0))
        guard phase >= timing.pickNewOffset, phase < timing.pickNewOffset + stay else {
            return .forward
        }
        func offset(_ index: UInt32) -> Float {
            let size = lerp(timing.offsetMin, timing.offsetMax, roll.value(index))
            return (roll.value(index + 1) < 0.5 ? -size : size) * .pi / 180
        }
        return HeadLook(yaw: offset(1), pitch: offset(3))
    }

    static func lerp(_ low: Float, _ high: Float, _ amount: Float) -> Float {
        low + (high - low) * amount
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
        let roll = look.roll * share
        let aroundY = float4x4(
            SIMD4(cosf(roll), 0, -sinf(roll), 0), SIMD4(0, 1, 0, 0),
            SIMD4(sinf(roll), 0, cosf(roll), 0), SIMD4(0, 0, 0, 1)
        )
        let aroundZ = float4x4(
            SIMD4(cosf(yaw), sinf(yaw), 0, 0), SIMD4(-sinf(yaw), cosf(yaw), 0, 0),
            SIMD4(0, 0, 1, 0), SIMD4(0, 0, 0, 1)
        )
        let aroundX = float4x4(
            SIMD4(1, 0, 0, 0), SIMD4(0, cosf(pitch), sinf(pitch), 0),
            SIMD4(0, -sinf(pitch), cosf(pitch), 0), SIMD4(0, 0, 0, 1)
        )
        return aroundZ * aroundX * aroundY
    }

    private static func translation(_ offset: SIMD3<Float>) -> float4x4 {
        var matrix = matrix_identity_float4x4
        matrix.columns.3 = SIMD4(offset, 1)
        return matrix
    }
}

/// Repeatable numbers in 0 ..< 1 from an actor's seed and a cycle, so a glance or an eye
/// drift is the same each time it is asked for.
nonisolated struct SeededRoll {
    let seed: UInt32
    let cycle: UInt32

    func value(_ index: UInt32) -> Float {
        var mixed = seed &* 2_654_435_761 ^ cycle &* 2_246_822_519 ^ index &* 3_266_489_917
        mixed ^= mixed >> 15
        mixed = mixed &* 2_246_822_519
        mixed ^= mixed >> 13
        return Float(mixed % 10000) / 10000
    }
}
