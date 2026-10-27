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
        let onOffGain = physicsRequests.footIkGains?["onOffGain"] ?? modifier.gains
            .value("onOffGain")
        var model = BehaviorModelPose(pose, skeleton: skeleton)
        var result = pose
        var errors = SIMD3<Float>()
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
                state.weights[slot] *= 1 - min(max(onOffGain, 0), 1)
                continue
            }
            state.flags[slot] = false
            state.weights[slot] += (1 - state.weights[slot]) * min(max(onOffGain, 0), 1)
            let error = ground - animatedGround + offset
            var goal = ankle + SIMD3(0, 0, error)
            if leg.maxAnkleHeightMS > leg.minAnkleHeightMS {
                goal.z = min(
                    max(goal.z, ground + leg.minAnkleHeightMS),
                    ground + leg.maxAnkleHeightMS
                )
            }
            errors.z += error
            Self.solveTwoBone(
                leg, toward: ankle + (goal - ankle) * state.weights[slot], model: &model,
                pose: &result
            )
        }
        nodeStates[step.target] = state
        footIkError = modifier.legs.isEmpty ? SIMD3() : errors / Float(modifier.legs.count)
        return result
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
