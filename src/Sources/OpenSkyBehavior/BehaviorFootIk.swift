// `hkbFootIkModifier`: moves each ankle by how far the real ground under it differs
// from the ground the animation was made on, with a two-bone solve from hip to ankle.
// With no ground probe the ground is flat at `m_originalGroundHeightMS`, so a pose on
// flat ground comes out unchanged.

import Foundation
import OpenSkyFormatsAnimation
import simd

nonisolated extension BehaviorGraphInstance {
    func applyFootIk(
        _ modifier: HKBFootIkModifier, _ step: BehaviorModifierStep, to pose: BehaviorPose
    ) -> BehaviorPose {
        guard characterContext.footIk else {
            footIkError = SIMD3()
            return pose
        }
        let bound = step.bound
        var state = markReached(step.target)
        if state.weights.count != modifier.legs.count {
            state.weights = Array(repeating: 0, count: modifier.legs.count)
            state.flags = Array(repeating: false, count: modifier.legs.count)
        }
        let animatedGround = bound.float(
            "originalGroundHeightMS",
            or: modifier.originalGroundHeightMS
        )
        let offset = bound.float("verticalOffset", or: modifier.verticalOffset)
        let onOffGain = Self.timed(gain("onOffGain", modifier), step.deltaTime)
        var model = BehaviorModelPose(pose, skeleton: skeleton)
        var result = pose
        var errors: [Float] = []
        for (slot, leg) in modifier.legs.enumerated() {
            guard [leg.hipIndex, leg.kneeIndex, leg.ankleIndex].allSatisfy(model.contains) else {
                continue
            }
            let ankle = model.translations[leg.ankleIndex]
            let ground = groundHeight(under: ankle, modifier, bound, flat: animatedGround)
            guard let ground else {
                if !state.flags[slot] {
                    raise(leg.ungroundedEvent)
                }
                state.flags[slot] = true
                state.weights[slot] *= 1 - onOffGain
                continue
            }
            state.flags[slot] = false
            state.weights[slot] += (1 - state.weights[slot]) * onOffGain
            let error = ground - animatedGround + offset
            var goal = ankle + SIMD3(0, 0, error)
            if leg.maxAnkleHeightMS > leg.minAnkleHeightMS {
                goal.z = min(
                    max(goal.z, ground + leg.minAnkleHeightMS),
                    ground + leg.maxAnkleHeightMS
                )
            }
            errors.append(error)
            Self.solveTwoBone(
                leg, toward: ankle + (goal - ankle) * state.weights[slot], model: &model,
                pose: &result
            )
        }
        nodeStates[step.target] = state
        let feedback = gain("worldFromModelFeedbackGain", modifier)
        footIkError = feedback > 0 ? SIMD3(0, 0, Self.combinedError(
            errors, bias: gain("errorUpDownBias", modifier)
        ) * Self.timed(feedback, step.deltaTime)) : SIMD3()
        return result
    }

    /// The controls modifier's gain when one runs, else the foot IK modifier's own.
    private func gain(_ name: String, _ modifier: HKBFootIkModifier) -> Float {
        physicsRequests.footIkGains?[name] ?? modifier.gains.value(name)
    }

    /// A gain is a rate at 30 updates a second, so a step of `deltaTime` applies this much.
    static func timed(_ gain: Float, _ deltaTime: Float) -> Float {
        min(max(gain * deltaTime * 30, 0), 1)
    }

    /// The bias picks between the foot that must move down most (0) and the one that
    /// must move up most (1).
    static func combinedError(_ errors: [Float], bias: Float) -> Float {
        guard let low = errors.min(), let high = errors.max() else { return 0 }
        return (1 - bias) * low + bias * high
    }

    private func groundHeight(
        under ankle: SIMD3<Float>,
        _ modifier: HKBFootIkModifier,
        _ bound: [String: BehaviorVariableValue],
        flat: Float
    ) -> Float? {
        guard let probe = characterContext.ground else { return flat }
        return probe.groundHeight(
            at: ankle,
            up: bound.float("raycastDistanceUp", or: modifier.raycastDistanceUp),
            down: bound.float("raycastDistanceDown", or: modifier.raycastDistanceDown)
        )
    }

    /// Bends the knee so hip to ankle spans the distance to `goal` (law of
    /// cosines), then turns the hip so the ankle lands on it.
    static func solveTwoBone(
        _ leg: HKBFootIkModifierLeg,
        toward goal: SIMD3<Float>,
        model: inout BehaviorModelPose,
        pose: inout BehaviorPose
    ) {
        let hip = model.translations[leg.hipIndex]
        let knee = model.translations[leg.kneeIndex]
        let ankle = model.translations[leg.ankleIndex]
        let upper = simd_length(knee - hip)
        let lower = simd_length(ankle - knee)
        guard upper > 0, lower > 0 else { return }
        let reach = min(
            max(simd_length(goal - hip), abs(upper - lower) + 1e-4),
            upper + lower - 1e-4
        )
        let wanted = acos(min(max(
            (upper * upper + lower * lower - reach * reach) / (2 * upper * lower), -1
        ), 1))
        let current = acos(min(max(simd_dot(
            simd_normalize(hip - knee), simd_normalize(ankle - knee)
        ), -1), 1))
        var axis = simd_cross(hip - knee, ankle - knee)
        if simd_length(axis) < 1e-6 {
            axis = model.rotations[leg.kneeIndex].act(BehaviorModelPose.vector3(leg.kneeAxisLS))
        }
        if simd_length(axis) > 1e-6 {
            model.rotate(
                leg.kneeIndex, by: simd_quatf(angle: wanted - current, axis: simd_normalize(axis)),
                in: &pose
            )
        }
        let bent = model.translations[leg.ankleIndex]
        model.rotate(
            leg.hipIndex, by: BehaviorModelPose.rotation(from: bent - hip, to: goal - hip),
            in: &pose
        )
    }
}
