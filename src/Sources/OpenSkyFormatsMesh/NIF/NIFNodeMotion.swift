// The turn rules of the node controllers: an axis that faces a direction, a path's
// follow and bank, and a lag bone's trail (docs/formats/nif-controllers.md).

import Foundation
import simd

nonisolated enum NIFPathOrientation {
    /// The follow rotation at `fraction`, banked into turns; nil when the path does not follow.
    static func rotation(of path: NIFPath, atFraction fraction: Float) -> simd_quatf? {
        let source = path.interpolator
        guard source.follows, let direction = path.tangent(atFraction: fraction) else {
            return nil
        }
        var axis = SIMD3<Float>.zero
        axis[min(max(Int(source.followAxis), 0), 2)] = source.flips ? -1 : 1
        return facing(direction, axis: axis, roll: bank(of: path, atFraction: fraction))
    }

    /// The roll into a turn: the full bank angle at the path's largest bend, less on a
    /// gentler one by `atan(c / cMax) * 4 / pi`.
    static func bank(of path: NIFPath, atFraction fraction: Float) -> Float {
        let source = path.interpolator
        let largest = path.maximumCurvature
        guard source.banks, largest > 0 else { return 0 }
        let bend = path.curvature(atFraction: fraction)
        var share: Float = 1
        if abs(bend) < largest {
            share = atan(abs(bend) / largest) * 4 / .pi
        }
        let turn: Float = bend < 0 ? -1 : 1
        return Float(source.bankDirection.signum()) * source.maximumBankAngle * share * turn
    }

    /// A rotation that points the object's `axis` along `direction`, keeping the object's
    /// up as close to +Z as it can, then turned `roll` radians about the axis.
    static func facing(_ direction: SIMD3<Float>, axis: SIMD3<Float>, roll: Float) -> simd_quatf? {
        guard simd_length_squared(direction) > 1e-12 else { return nil }
        let forward = simd_normalize(direction)
        let objectUp: SIMD3<Float> = abs(axis.z) > 0.5 ? [0, 1, 0] : [0, 0, 1]
        var worldUp: SIMD3<Float> = abs(axis.z) > 0.5 ? [0, 1, 0] : [0, 0, 1]
        if abs(simd_dot(worldUp, forward)) > 0.999 {
            worldUp = abs(forward.x) < 0.9 ? [1, 0, 0] : [0, 1, 0]
        }
        let up = simd_normalize(worldUp - forward * simd_dot(worldUp, forward))
        let object = simd_float3x3(columns: (axis, objectUp, simd_cross(axis, objectUp)))
        let target = simd_float3x3(columns: (forward, up, simd_cross(forward, up)))
        let turn = simd_quatf(target * object.transpose).normalized
        return (turn * simd_quatf(angle: roll, axis: axis)).normalized
    }
}

nonisolated public enum NIFLagBoneMotion {
    /// One step of a lag bone from last frame's transform toward `goal`, its rest under the
    /// moving parent. Rates are fractions per second (docs/formats/nif-controllers.md).
    public static func step(
        _ current: NIFNodeTransform, toward goal: NIFNodeTransform, _ lag: NIFLagBone,
        deltaTime: Float
    ) -> NIFNodeTransform {
        let dt = max(deltaTime, 0)
        let rate = lag.linearVelocity * dt
        var position = goal.translation
        if lag.linearVelocity > 0 {
            var start = current.translation
            var gap = goal.translation - start
            let distance = simd_length(gap)
            if distance >= rate {
                if distance > lag.maximumDistance, distance > 0 {
                    let direction = gap / distance
                    start += direction * (distance - lag.maximumDistance)
                    gap = direction * lag.maximumDistance
                }
                position = start + gap * rate
            }
        }
        let turn = simd_clamp(lag.linearRotation * dt, 0, 1)
        return NIFNodeTransform(
            translation: position,
            rotation: nlerp(current.rotation, goal.rotation, turn),
            scale: goal.scale
        )
    }

    private static func nlerp(_ from: simd_quatf, _ to: simd_quatf, _ share: Float) -> simd_quatf {
        let target = simd_dot(from.vector, to.vector) < 0 ? simd_quatf(vector: -to.vector) : to
        let mixed = simd_mix(from.vector, target.vector, SIMD4(repeating: share))
        guard simd_length_squared(mixed) > 1e-12 else { return to }
        return simd_quatf(vector: simd_normalize(mixed))
    }
}
