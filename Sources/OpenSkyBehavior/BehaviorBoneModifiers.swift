// Modifiers that move bones or the character: twist, character rotation, the
// tweener, limb IK, and the pass-by trigger, plus the ragdoll hand-offs the physics
// layer reads from `physicsRequests`. Aiming is in `BehaviorAimModifiers.swift`.

import Foundation
import OpenSkyFormatsAnimation
import simd

nonisolated extension BehaviorGraphInstance {
    private static let modelUp = SIMD3<Float>(0, 0, 1)
    private static let modelForward = SIMD3<Float>(0, 1, 0)

    func runBoneModifier(
        _ object: any HKBClass, _ step: BehaviorModifierStep, to pose: BehaviorPose
    ) -> BehaviorPose {
        switch object {
        case let modifier as HKBTwistModifier:
            return applyTwist(modifier, step, to: pose)
        case let modifier as HKBRotateCharacterModifier:
            return applyRotateCharacter(modifier, step, to: pose)
        case let modifier as BSTweenerModifier:
            return applyTweener(modifier, step, to: pose)
        case let modifier as BSLimbIKModifier:
            return applyLimbIK(modifier, step, to: pose)
        case let modifier as BSPassByTargetTriggerModifier:
            applyPassByTarget(modifier, step)
            return pose
        default:
            return runPhysicsModifier(object, step, to: pose)
        }
    }

    private func runPhysicsModifier(
        _ object: any HKBClass, _ step: BehaviorModifierStep, to pose: BehaviorPose
    ) -> BehaviorPose {
        switch object {
        case let modifier as HKBKeyframeBonesModifier:
            applyKeyframeBones(modifier)
            return pose
        case let modifier as HKBGetUpModifier:
            let bound = step.bound
            physicsRequests.getUp = BehaviorGetUpRequest(
                groundNormal: BehaviorModelPose.vector3(
                    bound.quad("groundNormal", or: modifier.groundNormal)
                ),
                duration: bound.float("duration", or: modifier.duration),
                alignDuration: bound.float(
                    "alignWithGroundDuration", or: modifier.alignWithGroundDuration
                ),
                rootBoneIndex: bound.int("rootBoneIndex", or: modifier.rootBoneIndex)
            )
            return pose
        case let modifier as HKBFootIkControlsModifier:
            applyFootIkControls(modifier, step)
            return pose
        case let modifier as HKBFootIkModifier:
            return applyFootIk(modifier, step, to: pose)
        default:
            return runAimModifier(object, step, to: pose)
        }
    }

    // MARK: - Twist and rotation

    /// `hkbTwistModifier`: spreads `m_twistAngle` (radians) over the chain from
    /// the start bone to the end bone, evenly or ramped towards the end. A
    /// non-additive twist in local axes replaces each bone's own twist.
    private func applyTwist(
        _ modifier: HKBTwistModifier, _ step: BehaviorModifierStep, to pose: BehaviorPose
    ) -> BehaviorPose {
        let bound = step.bound
        let rawAxis = BehaviorModelPose.vector3(bound.quad(
            "axisOfRotation",
            or: modifier.axisOfRotation
        ))
        guard simd_length(rawAxis) > 0 else { return pose }
        let axis = simd_normalize(rawAxis)
        let angle = bound.float("twistAngle", or: modifier.twistAngle)
        var result = pose
        var model = BehaviorModelPose(pose, skeleton: skeleton)
        let chain = model.chain(
            from: bound.int("startBoneIndex", or: modifier.startBoneIndex),
            to: bound.int("endBoneIndex", or: modifier.endBoneIndex)
        )
        let ramped = bound.int("setAngleMethod", or: modifier.setAngleMethod) == 1
        let total = ramped ? Float(chain.count * (chain.count + 1)) / 2 : Float(chain.count)
        let local = bound.int("rotationAxisCoordinates", or: modifier.rotationAxisCoordinates) == 1
        let additive = bound.bool("isAdditive", or: modifier.isAdditive)
        if !additive, !local {
            tally.note(.twistModelAxisAsAdditive)
        }
        for (position, bone) in chain.enumerated() {
            let share = (ramped ? Float(position + 1) : 1) / max(total, 1)
            let twist = simd_quatf(angle: angle * share, axis: axis)
            if local {
                result.bones[bone] = Self.twisted(result.bones[bone], twist, axis, additive)
                model.compose(result)
            } else {
                model.rotate(bone, by: twist, in: &result)
            }
        }
        return result
    }

    private static func twisted(
        _ bone: HKABonePose, _ twist: simd_quatf, _ axis: SIMD3<Float>, _ additive: Bool
    ) -> HKABonePose {
        var rotation = bone.rotation
        if !additive {
            // Swing-twist split: keep the swing, drop the twist about `axis`.
            let projected = simd_dot(rotation.imag, axis) * axis
            let current = simd_quatf(
                ix: projected.x,
                iy: projected.y,
                iz: projected.z,
                r: rotation.real
            )
            if simd_length(current.vector) > 0 {
                rotation *= simd_normalize(current).inverse
            }
        }
        return HKABonePose(
            translation: bone.translation,
            rotation: BehaviorPoseMath.normalized(rotation * twist),
            scale: bone.scale
        )
    }

    /// `hkbRotateCharacterModifier`: turns the character about the axis at
    /// `m_degreesPerSecond` times `m_speedMultiplier`, through the root travel.
    private func applyRotateCharacter(
        _ modifier: HKBRotateCharacterModifier, _ step: BehaviorModifierStep, to pose: BehaviorPose
    ) -> BehaviorPose {
        let bound = step.bound
        let rawAxis = BehaviorModelPose.vector3(bound.quad(
            "axisOfRotation",
            or: modifier.axisOfRotation
        ))
        let axis = simd_length(rawAxis) > 0 ? simd_normalize(rawAxis) : Self.modelUp
        let degrees = bound.float("degreesPerSecond", or: modifier.degreesPerSecond)
            * bound.float("speedMultiplier", or: modifier.speedMultiplier) * step.deltaTime
        var result = pose
        result.rootMotion.rotation = BehaviorPoseMath.normalized(
            pose.rootMotion.rotation * simd_quatf(angle: degrees * .pi / 180, axis: axis)
        )
        return result
    }

    // MARK: - Moving the character

    /// `BSTweenerModifier`: moves the character to the target position and
    /// rotation (world space) over `m_tweenDuration`, through the root travel.
    /// Without `m_useTweenDuration` it arrives in one update.
    private func applyTweener(
        _ modifier: BSTweenerModifier, _ step: BehaviorModifierStep, to pose: BehaviorPose
    ) -> BehaviorPose {
        let bound = step.bound
        var state = markReached(step.target)
        let duration = bound.bool("useTweenDuration", or: modifier.useTweenDuration)
            ? bound.float("tweenDuration", or: modifier.tweenDuration) : 0
        let remaining = max(duration - state.elapsed, 0)
        let fraction = remaining <= step.deltaTime ? 1 : step.deltaTime / remaining
        state.elapsed += step.deltaTime
        nodeStates[step.target] = state
        var result = pose
        let context = characterContext
        if bound.bool("tweenPosition", or: modifier.tweenPosition) {
            let target = BehaviorModelPose.vector3(bound.quad(
                "targetPosition",
                or: modifier.targetPosition
            ))
            result.rootMotion.translation = context.modelPoint(fromWorld: target) * fraction
            result.rootMotion.isExtracted = true
        }
        if bound.bool("tweenRotation", or: modifier.tweenRotation) {
            let raw = bound.quad("targetRotation", or: modifier.targetRotation)
            let target = BehaviorPoseMath.normalized(simd_quatf(vector: raw))
            let turn = BehaviorPoseMath.normalized(context.worldRotation.inverse * target)
            result.rootMotion.rotation = BehaviorModelPose.partial(turn, fraction)
            result.rootMotion.isExtracted = true
        }
        return result
    }

    /// `BSPassByTargetTriggerModifier`: raises `m_triggerEvent` once, when the
    /// character is past the target along the movement direction and within
    /// `m_radius` of the line through it.
    private func applyPassByTarget(
        _ modifier: BSPassByTargetTriggerModifier, _ step: BehaviorModifierStep
    ) {
        var state = markReached(step.target)
        guard !state.hasFiredAlarm else { return }
        let bound = step.bound
        let target = BehaviorModelPose.vector3(bound.quad(
            "targetPosition",
            or: modifier.targetPosition
        ))
        let rawDirection = BehaviorModelPose.vector3(
            bound.quad("movementDirection", or: modifier.movementDirection)
        )
        let context = characterContext
        let direction = simd_length(rawDirection) > 0
            ? simd_normalize(rawDirection) : context.worldRotation.act(Self.modelForward)
        let offset = context.worldPosition - target
        let along = simd_dot(offset, direction)
        let lateral = simd_length(offset - direction * along)
        if along >= 0, lateral <= bound.float("radius", or: modifier.radius) {
            state.hasFiredAlarm = true
            raise(modifier.triggerEvent)
        }
        nodeStates[step.target] = state
    }

    /// `BSLimbIKModifier`: when the ground probe finds geometry along the limb,
    /// lifts the limb about its start bone, by up to `m_limitAngleDegrees` and
    /// eased by `m_gain`. With no probe or no hit it eases back to the animation.
    private func applyLimbIK(
        _ modifier: BSLimbIKModifier, _ step: BehaviorModifierStep, to pose: BehaviorPose
    ) -> BehaviorPose {
        let bound = step.bound
        var model = BehaviorModelPose(pose, skeleton: skeleton)
        let chain = model.chain(
            from: bound.int("startBoneIndex", or: modifier.startBoneIndex),
            to: bound.int("endBoneIndex", or: modifier.endBoneIndex)
        )
        guard let start = chain.first, let end = chain.last, start != end else { return pose }
        var state = markReached(step.target)
        let context = characterContext
        let from = model.translations[start]
        let limb = model.translations[end] - from
        let hit = context.ground?.firstHit(
            from: context.worldPoint(fromModel: from),
            to: context.worldPoint(fromModel: model.translations[end]),
            radius: bound.float("boneRadius", or: modifier.boneRadius)
        )
        let limit = bound.float("limitAngleDegrees", or: modifier.limitAngleDegrees)
        let goal = hit.map { (1 - min(max($0, 0), 1)) * limit } ?? 0
        let current = state.weights.first ?? 0
        let gain = min(max(bound.float("gain", or: modifier.gain), 0), 1)
        let angle = current + (goal - current) * gain
        state.weights = [angle]
        nodeStates[step.target] = state
        let side = simd_cross(limb, Self.modelUp)
        guard abs(angle) > 0, simd_length(side) > 0 else { return pose }
        var result = pose
        model.rotate(
            start, by: simd_quatf(angle: angle * .pi / 180, axis: simd_normalize(side)), in: &result
        )
        return result
    }

    // MARK: - Physics hand-offs

    private func applyKeyframeBones(_ modifier: HKBKeyframeBonesModifier) {
        var bones = Set(modifier.keyframeInfo.filter(\.isValid).map(\.boneIndex))
        if
            let list = modifier.keyframedBonesList,
            let array = object(at: list, as: HKBBoneIndexArray.self)
        {
            markReached(list)
            bones.formUnion(array.boneIndices)
        }
        physicsRequests.keyframedBones = bones.filter { $0 >= 0 }.sorted()
    }

    private func applyFootIkControls(
        _ modifier: HKBFootIkControlsModifier, _ step: BehaviorModifierStep
    ) {
        var gains: [String: Float] = [:]
        for name in HKBFootIkGains.memberNames {
            gains[name] = step.bound.float(
                "controlData/gains/\(name)", or: modifier.gains.value(name)
            )
        }
        physicsRequests.footIkGains = gains
        writeOutputs(["errorOutTranslation": .quad(SIMD4(footIkError, 0))], of: step.node)
    }
}
