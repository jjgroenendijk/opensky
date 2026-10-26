// The turn rules of the node controllers: an axis that faces a direction, a path's
// follow and bank, and a lag bone's trail. nif.xml names the fields but not the math,
// so each rule here is OpenSky's reading (docs/formats/nif-controllers.md).

import Foundation
import simd

nonisolated enum NIFPathOrientation {
    /// The fraction of the path a follow or bank looks ahead and behind, when the
    /// interpolator's smoothing is smaller.
    static let minimumLookAhead: Float = 0.01

    /// The follow rotation at `fraction`, banked into turns; nil when the path does not follow.
    static func rotation(of path: NIFPath, atFraction fraction: Float) -> simd_quatf? {
        let source = path.interpolator
        guard source.follows else { return nil }
        let reach = max(source.smoothing, minimumLookAhead)
        guard
            let behind = path.position(atFraction: fraction - reach),
            let here = path.position(atFraction: fraction),
            let ahead = path.position(atFraction: fraction + reach)
        else { return nil }
        var axis = SIMD3<Float>.zero
        axis[min(max(Int(source.followAxis), 0), 2)] = source.flips ? -1 : 1
        var bank: Float = 0
        if source.banks {
            let turn = headingChange(from: here - behind, to: ahead - here)
            let share = simd_clamp(turn / (.pi / 2), -1, 1)
            bank = Float(source.bankDirection.signum()) * share * source.maximumBankAngle
        }
        return facing(ahead - behind, axis: axis, roll: bank)
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

    /// Signed change of heading about +Z between two path steps, radians.
    static func headingChange(from first: SIMD3<Float>, to second: SIMD3<Float>) -> Float {
        let crossZ = first.x * second.y - first.y * second.x
        let dot = first.x * second.x + first.y * second.y
        return atan2(crossZ, dot)
    }
}

nonisolated enum NIFLagBoneMotion {
    /// One step of a lag bone toward `goal`: it closes `linearVelocity` of the gap per
    /// second, never trails more than `maximumDistance`, and turns `linearRotation` of
    /// the way per second.
    static func step(
        _ current: NIFNodeTransform, toward goal: NIFNodeTransform, _ lag: NIFLagBone,
        deltaTime: Float
    ) -> NIFNodeTransform {
        let dt = max(deltaTime, 0)
        var position = simd_mix(
            current.translation, goal.translation, SIMD3(repeating: min(lag.linearVelocity * dt, 1))
        )
        let gap = goal.translation - position
        let distance = simd_length(gap)
        if distance > lag.maximumDistance, distance > 0 {
            position = goal.translation - gap / distance * lag.maximumDistance
        }
        let rotation = simd_slerp(current.rotation, goal.rotation, min(lag.linearRotation * dt, 1))
        return NIFNodeTransform(
            translation: position,
            rotation: rotation.normalized,
            scale: goal.scale
        )
    }
}
