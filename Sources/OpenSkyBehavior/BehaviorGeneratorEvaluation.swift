// Generator evaluation: a depth-first walk from the root generator, children in
// declared order. A node reached twice is evaluated twice, because both parents want
// its pose. A class without semantics passes its child's or the reference pose and adds
// a `BehaviorTally` entry (docs/engine/behavior-runtime.md). State machines continue
// in `BehaviorStateMachineEvaluation.swift`.

import Foundation
import OpenSkyFormatsAnimation
import simd

/// One evaluated `hkbBlenderGeneratorChild`: its pose and the weights the
/// blender mixes it with. The pose blend uses `m_weight` scaled per bone by
/// `m_boneWeights`; the root travel uses `m_worldFromModelWeight`, which is the
/// member whose whole purpose is to let a child drive motion without driving
/// the pose.
nonisolated public struct BehaviorBlendChild: Sendable {
    public let pose: BehaviorPose
    public let weight: Float
    public let motionWeight: Float
    /// One weight per skeleton bone, or nil for a child that contributes at
    /// full weight everywhere.
    public let boneWeights: [Float]?
}

nonisolated extension BehaviorGraphInstance {
    /// The pose of the generator at `target`, or the reference pose when there
    /// is nothing there to evaluate.
    public func evaluateGenerator(
        at target: HKXPointerTarget?,
        depth: Int,
        deltaTime: Float
    ) -> BehaviorPose {
        guard let target else { return skeleton.restPose }
        guard depth < Self.maximumDepth else {
            tally.note(.depthCapReached)
            return skeleton.restPose
        }
        guard let node = compiledNode(at: target) else { return skeleton.restPose }
        markReached(target)
        tally.noteGenerator()
        if isDisabled(node) {
            tally.note(.disabledNode)
            return skeleton.restPose
        }
        let bound = boundValues(of: node)
        return evaluate(
            node.object, at: target, bound: bound, depth: depth, deltaTime: deltaTime
        )
    }

    /// Routes one decoded object to its semantics. Split from the guard clauses
    /// above so neither half runs past the body-length limit.
    private func evaluate(
        _ object: any HKBClass,
        at target: HKXPointerTarget,
        bound: [String: BehaviorVariableValue],
        depth: Int,
        deltaTime: Float
    ) -> BehaviorPose {
        let next = depth + 1
        switch object {
        case let clip as HKBClipGenerator:
            return evaluateClip(clip, at: target, bound: bound, deltaTime: deltaTime)
        case let blender as HKBBlenderGenerator:
            return evaluateBlend(
                blender.blender, bound: bound, depth: next, deltaTime: deltaTime
            )
        case let matching as HKBPoseMatchingGenerator:
            tally.note(.poseMatchingAsBlender)
            return evaluateBlend(
                matching.blender, bound: bound, depth: next, deltaTime: deltaTime
            )
        case let selector as HKBManualSelectorGenerator:
            return evaluateSelector(
                selector, bound: bound, depth: next, deltaTime: deltaTime
            )
        case let wrapper as HKBModifierGenerator:
            let pose = evaluateGenerator(
                at: wrapper.generator, depth: next, deltaTime: deltaTime
            )
            return applyModifier(at: wrapper.modifier, to: pose, deltaTime: deltaTime)
        case let machine as HKBStateMachine:
            return evaluateStateMachine(
                machine, at: target, bound: bound, depth: next, deltaTime: deltaTime
            )
        default:
            return evaluateBethesda(
                object, bound: bound, depth: next, deltaTime: deltaTime
            )
        }
    }

    /// The Bethesda generator classes and the leftovers, kept in their own
    /// switch so neither routing function grows past the complexity limit.
    private func evaluateBethesda(
        _ object: any HKBClass,
        bound: [String: BehaviorVariableValue],
        depth: Int,
        deltaTime: Float
    ) -> BehaviorPose {
        switch object {
        case let tagging as BSiStateTaggingGenerator:
            // The tag it publishes is read through the graph's own variables,
            // which the authored bindings already write; nothing else to do.
            return evaluateGenerator(
                at: tagging.defaultGenerator, depth: depth, deltaTime: deltaTime
            )
        case let switcher as BSBoneSwitchGenerator:
            tally.notePartialGenerator(BSBoneSwitchGenerator.className)
            return evaluateGenerator(
                at: switcher.defaultGenerator, depth: depth, deltaTime: deltaTime
            )
        case let cyclic as BSCyclicBlendTransitionGenerator:
            tally.notePartialGenerator(BSCyclicBlendTransitionGenerator.className)
            return evaluateGenerator(
                at: cyclic.blenderGenerator, depth: depth, deltaTime: deltaTime
            )
        case let offset as BSOffsetAnimationGenerator:
            tally.notePartialGenerator(BSOffsetAnimationGenerator.className)
            return evaluateGenerator(
                at: offset.defaultGenerator, depth: depth, deltaTime: deltaTime
            )
        case let synced as BSSynchronizedClipGenerator:
            return evaluateSynchronizedClip(
                synced, depth: depth, deltaTime: deltaTime
            )
        case let reference as HKBBehaviorReferenceGenerator:
            return evaluateBehaviorReference(reference, deltaTime: deltaTime)
        default:
            _ = bound
            tally.noteUnevaluatedGenerator(object.className)
            return skeleton.restPose
        }
    }

    // MARK: - Blending

    /// `hkbBlenderGenerator`: mixes child poses by `m_weight` and root travel by
    /// `m_worldFromModelWeight`. A child under `m_referencePoseWeightThreshold` is dropped.
    public func evaluateBlend(
        _ blender: HKBBlenderFields,
        bound: [String: BehaviorVariableValue],
        depth: Int,
        deltaTime: Float
    ) -> BehaviorPose {
        noteBlendGaps(blender)
        let threshold = bound.float(
            "m_referencePoseWeightThreshold",
            or: blender
                .referencePoseWeightThreshold
        )
        let children = blendChildren(
            blender, threshold: threshold, depth: depth, deltaTime: deltaTime
        )
        var blended = BehaviorPoseMath.blend(
            masked: children.map {
                BehaviorPoseMath.MaskedChild(
                    pose: $0.pose, weight: $0.weight, boneWeights: $0.boneWeights
                )
            },
            fallback: skeleton.restPose
        )
        blended.rootMotion = BehaviorPoseMath
            .blend(
                children: children.map { ($0.pose, $0.motionWeight) },
                fallback: skeleton.restPose
            )
            .rootMotion
        return blended
    }

    /// Evaluates every contributing child, the sync master first so its phase is
    /// current for the rest. Its result returns to its own index, keeping blend order.
    private func blendChildren(
        _ blender: HKBBlenderFields,
        threshold: Float,
        depth: Int,
        deltaTime: Float
    ) -> [BehaviorBlendChild] {
        let targets = blender.children.compactMap(\.self)
        var results = [BehaviorBlendChild?](repeating: nil, count: targets.count)
        let master = blender.indexOfSyncMasterChild
        if targets.indices.contains(master) {
            results[master] = blendChild(
                at: targets[master], threshold: threshold, depth: depth, deltaTime: deltaTime
            )
            pendingClipPhase = continuousClipPhase(
                of: object(at: targets[master], as: HKBBlenderGeneratorChild.self)?.generator
            )
        }
        for (index, target) in targets.enumerated() where index != master {
            results[index] = blendChild(
                at: target, threshold: threshold, depth: depth, deltaTime: deltaTime
            )
        }
        pendingClipPhase = nil
        return results.compactMap(\.self)
    }

    /// One `hkbBlenderGeneratorChild`, or nil when it is not one or its weight
    /// leaves it out of the blend.
    private func blendChild(
        at target: HKXPointerTarget,
        threshold: Float,
        depth: Int,
        deltaTime: Float
    ) -> BehaviorBlendChild? {
        guard
            let node = compiledNode(at: target),
            let child = node.object as? HKBBlenderGeneratorChild
        else {
            return nil
        }
        markReached(target)
        let bound = boundValues(of: node)
        let weight = bound.float("m_weight", or: child.weight)
        guard weight > threshold else { return nil }
        return BehaviorBlendChild(
            pose: evaluateGenerator(at: child.generator, depth: depth, deltaTime: deltaTime),
            weight: weight,
            motionWeight: bound.float(
                "m_worldFromModelWeight", or: child.worldFromModelWeight
            ),
            boneWeights: boneWeights(at: child.boneWeights)
        )
    }

    /// The decoded per-bone mask at `target`, honouring a binding on it, or nil
    /// when the child carries none.
    private func boneWeights(at target: HKXPointerTarget?) -> [Float]? {
        guard
            let target,
            let array = object(at: target, as: HKBBoneWeightArray.self),
            !array.boneWeights.isEmpty
        else { return nil }
        markReached(target)
        return array.boneWeights
    }

    private func noteBlendGaps(_ blender: HKBBlenderFields) {
        // Bit 2 is the parametric blend and bit 0 the cyclic sync; both change
        // how weights are derived, and neither is implemented here.
        if blender.flags & 0x5 != 0 {
            tally.note(.blenderParametricAsWeights)
        }
        if blender.subtractLastChild {
            tally.note(.blenderSubtractLastChild)
        }
    }

    // MARK: - Selection

    /// `hkbManualSelectorGenerator`: exactly one child runs, chosen by
    /// `m_selectedGeneratorIndex`, which is normally variable-bound. An index
    /// outside the child list selects nothing and produces the reference pose,
    /// which is what Havok does with an unset selector.
    public func evaluateSelector(
        _ selector: HKBManualSelectorGenerator,
        bound: [String: BehaviorVariableValue],
        depth: Int,
        deltaTime: Float
    ) -> BehaviorPose {
        let index = bound.int(
            "m_selectedGeneratorIndex",
            or: selector
                .selectedGeneratorIndex
        )
        guard selector.generators.indices.contains(index) else {
            return skeleton.restPose
        }
        return evaluateGenerator(
            at: selector.generators[index], depth: depth, deltaTime: deltaTime
        )
    }
}
