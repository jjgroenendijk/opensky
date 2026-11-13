// Bethesda's wrapper generators: the per-bone switch, the cyclic blend crossfade,
// and the offset animation. Each runs its default child and then layers its own
// part on top (docs/engine/behavior-runtime.md).

import Foundation
public import OpenSkyFormatsAnimation
import simd

nonisolated extension BehaviorGraphInstance.Generators {
    /// `BSBoneSwitchGenerator`: the default generator, with each child's pose
    /// replacing it on the bones that child's bone weights cover.
    func evaluateBoneSwitch(
        _ switcher: BSBoneSwitchGenerator, depth: Int, deltaTime: Float
    ) -> BehaviorPose {
        var pose = graph.skeleton.absolute(evaluateGenerator(
            at: switcher.defaultGenerator,
            depth: depth,
            deltaTime: deltaTime
        ))
        for target in switcher.children.compactMap(\.self) {
            guard
                let node = graph.compiledNode(at: target),
                let data = node.object as? BSBoneSwitchGeneratorBoneData
            else { continue }
            graph.markReached(target)
            let authored = data.boneWeight.flatMap { target in
                graph.markReached(target)
                return graph.object(at: target, as: HKBBoneWeightArray.self)?.boneWeights
            }
            guard
                let weights = graph
                    .characterBoneWeights(of: node, path: "spBoneWeight") ?? authored,
                !weights.isEmpty
            else { continue }
            let child = graph.skeleton.absolute(
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
    /// the blender's parameter. `m_EventToFreezeBlendValue` holds the parameter until
    /// `m_EventToCrossBlend` crossfades from the held pose to the live blend, over
    /// `m_fTransitionDuration` with `m_eBlendCurve` (docs/engine/behavior-runtime.md#generators).
    func evaluateCyclicBlend(
        _ cyclic: BSCyclicBlendTransitionGenerator,
        _ visit: BehaviorVisit,
        deltaTime: Float
    ) -> BehaviorPose {
        let (target, bound, depth) = (visit.target, visit.bound, visit.depth)
        var state = graph.nodeStates[target] ?? graph.markReached(target)
        let isHolding = state.frozenBlendParameter != nil || state.crossBlendSource != nil
        let crossBlends = isHolding && graph.events.isActive(id: cyclic.eventToCrossBlend.id)
        // The copy starts from the blender as it stood before this update.
        let copy = crossBlends && state.crossBlendSource == nil
            ? state.frozenBlendParameter
            .map { BehaviorCyclicCopy(states: graph.nodeStates, parameter: $0) }
            : nil
        if let blender = cyclic.blenderGenerator {
            let parameter = bound.float("fBlendParameter", or: cyclic.blendParameter)
            if crossBlends {
                state.frozenBlendParameter = nil
            } else if !isHolding, graph.events.isActive(id: cyclic.eventToFreezeBlendValue.id) {
                state.frozenBlendParameter = graph.nodeMemory
                    .blendParameterOverrides[blender] ?? parameter
            }
            graph.nodeMemory.blendParameterOverrides[blender] = state
                .frozenBlendParameter ?? parameter
        }
        let live = evaluateGenerator(
            at: cyclic.blenderGenerator,
            depth: depth,
            deltaTime: deltaTime
        )
        if crossBlends {
            // A repeat while blending mirrors the progress: e becomes d - e.
            let duration = bound.float("fTransitionDuration", or: cyclic.transitionDuration)
            if state.crossBlendSource != nil {
                state.elapsed = max(duration - state.elapsed, 0)
            } else {
                state.crossBlendSource = graph.nodeMemory.cyclicLastPoses[target] ?? live
                state.elapsed = 0
                graph.nodeMemory.cyclicCopies[target] = copy
            }
        }
        var result = live
        if let still = state.crossBlendSource {
            let source = runCopy(of: cyclic, at: target, depth: depth, deltaTime: deltaTime)
                ?? still
            state.elapsed += deltaTime
            result = blendedCrossFade(source, live, weight: crossFadeWeight(state, cyclic, bound))
            let duration = bound.float("fTransitionDuration", or: cyclic.transitionDuration)
            if state.elapsed >= duration {
                state.crossBlendSource = nil
                graph.nodeMemory.cyclicCopies[target] = nil
            }
        }
        if !BehaviorBlendCurve.isKnown(cyclic.blendCurve) {
            graph.tally.note(.transitionBlendCurveApproximated)
        }
        graph.nodeStates[target] = state
        graph.nodeMemory.cyclicLastPoses[target] = result
        return result
    }

    /// Steps the held copy of the blender at its held parameter, with the copy's own node
    /// states. Its annotations stay silent, because the live blender sends them.
    private func runCopy(
        of cyclic: BSCyclicBlendTransitionGenerator,
        at target: HKXPointerTarget,
        depth: Int,
        deltaTime: Float
    ) -> BehaviorPose? {
        guard
            let blender = cyclic.blenderGenerator,
            var copy = graph.nodeMemory.cyclicCopies[target]
        else {
            return nil
        }
        graph.nodeMemory.cyclicCopies[target] = nil
        let live = graph.nodeStates
        let liveParameter = graph.nodeMemory.blendParameterOverrides[blender]
        let wasMuted = graph.nodeMemory.mutesClipAnnotations
        graph.nodeStates = copy.states
        copy.states = [:]
        graph.nodeMemory.blendParameterOverrides[blender] = copy.parameter
        graph.nodeMemory.mutesClipAnnotations = true
        let pose = evaluateGenerator(at: blender, depth: depth, deltaTime: deltaTime)
        copy.states = graph.nodeStates
        graph.nodeStates = live
        graph.nodeMemory.blendParameterOverrides[blender] = liveParameter
        graph.nodeMemory.mutesClipAnnotations = wasMuted
        graph.nodeMemory.cyclicCopies[target] = copy
        return pose
    }

    private func crossFadeWeight(
        _ state: BehaviorNodeState,
        _ cyclic: BSCyclicBlendTransitionGenerator,
        _ bound: [String: BehaviorVariableValue]
    ) -> Float {
        let duration = bound.float("fTransitionDuration", or: cyclic.transitionDuration)
        return duration > 0
            ? BehaviorBlendCurve.weight(state.elapsed / duration, curve: cyclic.blendCurve) : 1
    }

    private func blendedCrossFade(
        _ source: BehaviorPose,
        _ live: BehaviorPose,
        weight: Float
    ) -> BehaviorPose {
        var pose = graph.blenders.blendFull(source, live, weight: weight)
        pose.rootMotion = live.rootMotion
        return pose
    }

    /// `BSOffsetAnimationGenerator`: the default pose plus the additive offset clip,
    /// held at the frame `m_fOffsetVariable` picks in the range from start to end.
    func evaluateOffsetAnimation(
        _ offset: BSOffsetAnimationGenerator,
        _ visit: BehaviorVisit,
        deltaTime: Float
    ) -> BehaviorPose {
        let (target, bound, depth) = (visit.target, visit.bound, visit.depth)
        let pose = graph.skeleton.absolute(evaluateGenerator(
            at: offset.defaultGenerator, depth: depth, deltaTime: deltaTime
        ))
        let start = bound.float("fOffsetRangeStart", or: offset.offsetRangeStart)
        let end = bound.float("fOffsetRangeEnd", or: offset.offsetRangeEnd)
        let value = bound.float("fOffsetVariable", or: offset.offsetVariable)
        let fraction = Self.offsetFraction(value, start: start, end: end)
        let frames = offsetFrameCount(offset)
        let phase = Self.offsetPhase(fraction, frameCount: frames)
        let frame = min(Int(phase * Float(max(frames - 1, 0))), max(frames - 2, 0))
        var state = graph.markReached(target)
        let outer = graph.pendingClipPhase
        graph.pendingClipPhase = (phase, false)
        let sampled = evaluateGenerator(
            at: offset.offsetClipGenerator, depth: depth, deltaTime: 0
        )
        graph.pendingClipPhase = outer
        let moved = abs(fraction - state.offsetFraction) > Self.offsetEpsilon
        if state.offsetLayer == nil || (frame != state.offsetFrame && moved) {
            state.offsetLayer = sampled
            state.offsetFrame = frame
            state.offsetFraction = fraction
        }
        graph.nodeStates[target] = state
        guard let layer = state.offsetLayer, layer.isAdditive else { return pose }
        return BehaviorPoseMath.adding(layer, to: pose) { _ in 1 }
    }

    static let offsetEpsilon: Float = 1.19e-7

    /// Where the variable sits in the range, clamped; an empty range is 0.
    static func offsetFraction(_ value: Float, start: Float, end: Float) -> Float {
        let range = end - start
        guard abs(range) > offsetEpsilon, value.isFinite else { return 0 }
        return min(max((value - start) / range, 0), 1)
    }

    /// The clip phase for `fraction`: from the second frame at 0 to the end at 1.
    static func offsetPhase(_ fraction: Float, frameCount: Int) -> Float {
        guard frameCount > 1 else { return fraction }
        let first = 1 / Float(frameCount - 1)
        return first + (1 - first) * fraction
    }

    private func offsetFrameCount(_ offset: BSOffsetAnimationGenerator) -> Int {
        guard
            let target = offset.offsetClipGenerator,
            let generator = graph.object(at: target, as: HKBClipGenerator.self)
        else { return 0 }
        return graph.clipSource.clip(
            named: generator.animationName, bindingIndex: generator.animationBindingIndex
        )?.frameCount ?? 0
    }
}

/// The node states and held parameter of a cyclic blend's running copy.
nonisolated struct BehaviorCyclicCopy: Equatable, Sendable {
    var states: [HKXPointerTarget: BehaviorNodeState]
    let parameter: Float
}
