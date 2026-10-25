// Bethesda's wrapper generators: the per-bone switch, the cyclic blend crossfade,
// and the offset animation. Each runs its default child and then layers its own
// part on top (docs/engine/behavior-runtime.md).

import Foundation
import OpenSkyFormatsAnimation
import simd

nonisolated extension BehaviorGraphInstance {
    /// `BSBoneSwitchGenerator`: the default generator, with each child's pose
    /// replacing it on the bones that child's bone weights cover.
    func evaluateBoneSwitch(
        _ switcher: BSBoneSwitchGenerator, depth: Int, deltaTime: Float
    ) -> BehaviorPose {
        var pose = skeleton.absolute(evaluateGenerator(
            at: switcher.defaultGenerator,
            depth: depth,
            deltaTime: deltaTime
        ))
        for target in switcher.children.compactMap(\.self) {
            guard
                let node = compiledNode(at: target),
                let data = node.object as? BSBoneSwitchGeneratorBoneData
            else { continue }
            markReached(target)
            guard
                let weightsTarget = data.boneWeight,
                let weights = object(at: weightsTarget, as: HKBBoneWeightArray.self)?.boneWeights,
                !weights.isEmpty
            else { continue }
            markReached(weightsTarget)
            let child = skeleton.absolute(
                evaluateGenerator(at: data.generator, depth: depth, deltaTime: deltaTime)
            )
            for bone in pose.bones.indices
                where weights.indices.contains(bone) && weights[bone] > 0
            {
                guard child.bones.indices.contains(bone) else { continue }
                pose.bones[bone] = BehaviorPoseMath.blend(
                    pose.bones[bone], child.bones[bone], weight: min(weights[bone], 1)
                )
            }
        }
        return pose
    }

    /// `BSCyclicBlendTransitionGenerator`: runs its blender with `m_fBlendParameter` as
    /// the blender's parameter. `m_EventToCrossBlend` starts a crossfade from the pose of
    /// that moment to the live blend, over `m_fTransitionDuration` with `m_eBlendCurve`.
    func evaluateCyclicBlend(
        _ cyclic: BSCyclicBlendTransitionGenerator,
        at target: HKXPointerTarget,
        bound: [String: BehaviorVariableValue],
        depth: Int,
        deltaTime: Float
    ) -> BehaviorPose {
        if let blender = cyclic.blenderGenerator {
            blendParameterOverrides[blender] = bound.float(
                "fBlendParameter", or: cyclic.blendParameter
            )
        }
        let live = evaluateGenerator(
            at: cyclic.blenderGenerator,
            depth: depth,
            deltaTime: deltaTime
        )
        var state = nodeStates[target] ?? markReached(target)
        if events.isActive(id: cyclic.eventToCrossBlend.id) {
            state.crossBlendSource = state.crossBlendSource.map {
                blendedCrossFade($0, live, state, cyclic, bound)
            } ?? cyclicLastPoses[target] ?? live
            state.elapsed = 0
        }
        var result = live
        if let source = state.crossBlendSource {
            state.elapsed += deltaTime
            result = blendedCrossFade(source, live, state, cyclic, bound)
            let duration = bound.float("fTransitionDuration", or: cyclic.transitionDuration)
            if state.elapsed >= duration {
                state.crossBlendSource = nil
            }
        }
        if !BehaviorBlendCurve.isKnown(cyclic.blendCurve) {
            tally.note(.transitionBlendCurveApproximated)
        }
        nodeStates[target] = state
        cyclicLastPoses[target] = result
        return result
    }

    private func blendedCrossFade(
        _ source: BehaviorPose,
        _ live: BehaviorPose,
        _ state: BehaviorNodeState,
        _ cyclic: BSCyclicBlendTransitionGenerator,
        _ bound: [String: BehaviorVariableValue]
    ) -> BehaviorPose {
        let duration = bound.float("fTransitionDuration", or: cyclic.transitionDuration)
        let weight = duration > 0
            ? BehaviorBlendCurve.weight(state.elapsed / duration, curve: cyclic.blendCurve) : 1
        var pose = blendFull(source, live, weight: weight)
        pose.rootMotion = live.rootMotion
        return pose
    }

    /// `BSOffsetAnimationGenerator`: the default pose plus the offset clip's
    /// difference from the reference pose, with the clip held at the fraction
    /// `m_fOffsetVariable` makes of the range from start to end.
    func evaluateOffsetAnimation(
        _ offset: BSOffsetAnimationGenerator,
        bound: [String: BehaviorVariableValue],
        depth: Int,
        deltaTime: Float
    ) -> BehaviorPose {
        var pose = skeleton.absolute(evaluateGenerator(
            at: offset.defaultGenerator,
            depth: depth,
            deltaTime: deltaTime
        ))
        let start = bound.float("fOffsetRangeStart", or: offset.offsetRangeStart)
        let end = bound.float("fOffsetRangeEnd", or: offset.offsetRangeEnd)
        let value = bound.float("fOffsetVariable", or: offset.offsetVariable)
        let fraction = end != start ? min(max((value - start) / (end - start), 0), 1) : 0
        let outer = pendingClipPhase
        pendingClipPhase = (fraction, false)
        let layer = evaluateGenerator(at: offset.offsetClipGenerator, depth: depth, deltaTime: 0)
        pendingClipPhase = outer
        if layer.isAdditive {
            return BehaviorPoseMath.adding(layer, to: pose) { _ in 1 }
        }
        let rest = skeleton.referencePose
        for bone in pose.bones.indices
            where layer.bones.indices.contains(bone) && rest.indices.contains(bone)
        {
            let base = pose.bones[bone]
            let added = layer.bones[bone]
            let delta = BehaviorPoseMath.normalized(rest[bone].rotation.inverse * added.rotation)
            pose.bones[bone] = HKABonePose(
                translation: base.translation + added.translation - rest[bone].translation,
                rotation: BehaviorPoseMath.normalized(base.rotation * delta),
                scale: base.scale
            )
        }
        return pose
    }

    /// Blends two poses. When only one is additive, both become full poses first.
    func blendFull(_ lhs: BehaviorPose, _ rhs: BehaviorPose, weight: Float) -> BehaviorPose {
        guard lhs.isAdditive != rhs.isAdditive else {
            return BehaviorPoseMath.blend(lhs, rhs, weight: weight)
        }
        return BehaviorPoseMath.blend(
            skeleton.absolute(lhs),
            skeleton.absolute(rhs),
            weight: weight
        )
    }
}
