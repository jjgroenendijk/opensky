// Bethesda's aiming modifiers. `BSLookAtModifier` turns head and eye bones towards
// a target, `BSDirectAtModifier` turns a spine chain so a weapon points at it. Both
// take the target in world space and ease in and out by per-update gains.

import Foundation
import OpenSkyFormatsAnimation
import simd

nonisolated extension BehaviorGraphInstance {
    func runAimModifier(
        _ object: any HKBClass, _ step: BehaviorModifierStep, to pose: BehaviorPose
    ) -> BehaviorPose {
        switch object {
        case let modifier as BSLookAtModifier:
            return applyLookAt(modifier, step, to: pose)
        case let modifier as BSDirectAtModifier:
            return applyDirectAt(modifier, step, to: pose)
        default:
            tally.notePassthroughModifier(object.className)
            return pose
        }
    }

    /// The aim target in model space: the camera position when `useCamera`, else
    /// `location`. Both are world space.
    private func aimTarget(
        _ bound: [String: BehaviorVariableValue],
        prefix: String,
        useCamera: Bool,
        camera: SIMD3<Float>,
        location: SIMD4<Float>
    ) -> SIMD3<Float> {
        let world = useCamera
            ? SIMD3(
                bound.float("\(prefix)X", or: camera.x),
                bound.float("\(prefix)Y", or: camera.y),
                bound.float("\(prefix)Z", or: camera.z)
            )
            : BehaviorModelPose.vector3(bound.quad("targetLocation", or: location))
        return characterContext.modelPoint(fromWorld: world)
    }

    /// Eases `current` towards `goal`, by `onGain` when rising and `offGain` when falling.
    private static func ease(_ current: Float, to goal: Float, on: Float, off: Float) -> Float {
        let gain = min(max(goal > current ? on : off, 0), 1)
        return current + (goal - current) * gain
    }

    /// `rotation`, shortened to at most `limitDegrees` when the limit is positive.
    private static func limited(_ rotation: simd_quatf, _ limitDegrees: Float) -> simd_quatf {
        let limit = limitDegrees * .pi / 180
        guard limit > 0, rotation.angle > limit else { return rotation }
        return BehaviorModelPose.partial(rotation, limit / rotation.angle)
    }

    // MARK: - Look at

    /// `BSLookAtModifier`: each enabled bone, spine to head and then the eyes,
    /// turns its forward axis towards the target, limited per bone. When the
    /// target is past `m_limitAngleDegrees` from the character's facing, the
    /// look fades out unless `m_continueLookOutsideOfLimit` is set.
    private func applyLookAt(
        _ modifier: BSLookAtModifier, _ step: BehaviorModifierStep, to pose: BehaviorPose
    ) -> BehaviorPose {
        let bound = step.bound
        let camera = SIMD3(modifier.lookAtCameraX, modifier.lookAtCameraY, modifier.lookAtCameraZ)
        let target = aimTarget(
            bound, prefix: "lookAtCamera",
            useCamera: bound.bool("lookAtCamera", or: modifier.lookAtCamera),
            camera: camera, location: modifier.targetLocation
        )
        var model = BehaviorModelPose(pose, skeleton: skeleton)
        let lookFrom = modifier.bones.last.map(\.index).flatMap { model.contains($0) ? $0 : nil }
        let toTarget = target - (lookFrom.map { model.translations[$0] } ?? SIMD3())
        let facing = BehaviorModelPose.rotation(from: SIMD3(0, 1, 0), to: toTarget).angle
        let outside = facing * 180 / .pi
            > bound.float("limitAngleDegrees", or: modifier.limitAngleDegrees)
        let wantsLook = bound.bool("lookAtTarget", or: modifier.lookAtTarget)
            && (!outside || bound.bool(
                "continueLookOutsideOfLimit", or: modifier.continueLookOutsideOfLimit
            ))
        var state = markReached(step.target)
        let joints = lookAtJoints(modifier, bound)
        if state.weights.count != joints.count {
            state.weights = Array(repeating: 0, count: joints.count)
        }
        var result = pose
        for (slot, joint) in joints.enumerated()
            where joint.enabled && model.contains(joint.index)
        {
            state.weights[slot] = Self.ease(
                state.weights[slot], to: wantsLook ? 1 : 0, on: joint.onGain, off: joint.offGain
            )
            let forward = model.rotations[joint.index].act(joint.forward)
            let desired = target - model.translations[joint.index]
            let turn = Self.limited(
                BehaviorModelPose.rotation(from: forward, to: desired), joint.limitDegrees
            )
            model.rotate(
                joint.index, by: BehaviorModelPose.partial(turn, state.weights[slot]), in: &result
            )
        }
        if outside, state.flags.first != true {
            raise(modifier.targetOutOfLimitEvent)
        }
        state.flags = [outside]
        nodeStates[step.target] = state
        writeOutputs(["targetOutsideLimits": .bool(outside)], of: step.node)
        return result
    }

    private struct LookAtJoint {
        let index: Int
        let forward: SIMD3<Float>
        let limitDegrees: Float
        let onGain: Float
        let offGain: Float
        let enabled: Bool
    }

    /// The head bones then the eye bones, with their bound overrides. Without
    /// `m_useBoneGains` every bone eases at the modifier's own gains.
    private func lookAtJoints(
        _ modifier: BSLookAtModifier, _ bound: [String: BehaviorVariableValue]
    ) -> [LookAtJoint] {
        let useBoneGains = bound.bool("useBoneGains", or: modifier.useBoneGains)
        let onGain = bound.float("onGain", or: modifier.onGain)
        let offGain = bound.float("offGain", or: modifier.offGain)
        let groups = [("bones", modifier.bones), ("eyeBones", modifier.eyeBones)]
        return groups.flatMap { member, bones in
            bones.enumerated().map { index, bone in
                let path = "\(member):\(index)/"
                return LookAtJoint(
                    index: bound.int(path + "index", or: bone.index),
                    forward: BehaviorModelPose.vector3(bound.quad(
                        path + "fwdAxisLS",
                        or: bone.forwardAxisLS
                    )),
                    limitDegrees: bound.float(
                        path + "limitAngleDegrees",
                        or: bone.limitAngleDegrees
                    ),
                    onGain: useBoneGains ? bound.float(path + "onGain", or: bone.onGain) : onGain,
                    offGain: useBoneGains ? bound
                        .float(path + "offGain", or: bone.offGain) : offGain,
                    enabled: bound.bool(path + "enabled", or: bone.enabled)
                )
            }
        }
    }

    // MARK: - Direct at

    /// `BSDirectAtModifier`: the heading and pitch from the source bone to the
    /// target, limited and offset, eased in, and spread evenly over the chain.
    /// Heading turns about the model up axis, pitch about the model right axis.
    private func applyDirectAt(
        _ modifier: BSDirectAtModifier, _ step: BehaviorModifierStep, to pose: BehaviorPose
    ) -> BehaviorPose {
        let bound = step.bound
        let camera = SIMD3(
            modifier.directAtCameraX, modifier.directAtCameraY, modifier.directAtCameraZ
        )
        let target = aimTarget(
            bound, prefix: "directAtCamera",
            useCamera: bound.bool("directAtCamera", or: modifier.directAtCamera),
            camera: camera, location: modifier.targetLocation
        )
        var model = BehaviorModelPose(pose, skeleton: skeleton)
        let chain = model.chain(
            from: bound.int("startBoneIndex", or: modifier.startBoneIndex),
            to: bound.int("endBoneIndex", or: modifier.endBoneIndex)
        )
        let source = bound.int("sourceBoneIndex", or: modifier.sourceBoneIndex)
        let origin = model.contains(source)
            ? model.translations[source] : chain.first.map { model.translations[$0] } ?? SIMD3()
        let goal = directAtGoal(modifier, bound, toTarget: target - origin)
        var state = markReached(step.target)
        let current = state.weights.count == 2 ? SIMD2(state.weights[0], state.weights[1]) : SIMD2()
        let onGain = bound.float("onGain", or: modifier.onGain)
        let offGain = bound.float("offGain", or: modifier.offGain)
        let eased = SIMD2(
            Self.ease(current.x, to: goal.x, on: onGain, off: offGain),
            Self.ease(current.y, to: goal.y, on: onGain, off: offGain)
        )
        state.weights = [eased.x, eased.y]
        nodeStates[step.target] = state
        var result = pose
        let share = 1 / Float(max(chain.count, 1)) * .pi / 180
        for bone in chain {
            let heading = simd_quatf(angle: -eased.x * share, axis: SIMD3(0, 0, 1))
            let pitch = simd_quatf(angle: eased.y * share, axis: SIMD3(1, 0, 0))
            model.rotate(bone, by: heading * pitch, in: &result)
        }
        writeOutputs(
            [
                "active": .bool(goal != SIMD2() || simd_length(eased) > 0.01),
                "currentHeadingOffset": .real(eased.x),
                "currentPitchOffset": .real(eased.y)
            ],
            of: step.node
        )
        return result
    }

    /// The heading and pitch the chain eases towards, in degrees; zero when the
    /// modifier is not aiming.
    private func directAtGoal(
        _ modifier: BSDirectAtModifier,
        _ bound: [String: BehaviorVariableValue],
        toTarget: SIMD3<Float>
    ) -> SIMD2<Float> {
        guard
            bound.bool("directAtTarget", or: modifier.directAtTarget),
            simd_length(toTarget) > 0
        else { return SIMD2() }
        let heading = atan2(toTarget.x, toTarget.y) * 180 / .pi
        let pitch = atan2(toTarget.z, simd_length(SIMD2(toTarget.x, toTarget.y))) * 180 / .pi
        let headingLimit = abs(bound.float("limitHeadingDegrees", or: modifier.limitHeadingDegrees))
        let pitchLimit = abs(bound.float("limitPitchDegrees", or: modifier.limitPitchDegrees))
        return SIMD2(
            min(max(heading, -headingLimit), headingLimit)
                + bound.float("offsetHeadingDegrees", or: modifier.offsetHeadingDegrees),
            min(max(pitch, -pitchLimit), pitchLimit)
                + bound.float("offsetPitchDegrees", or: modifier.offsetPitchDegrees)
        )
    }
}
