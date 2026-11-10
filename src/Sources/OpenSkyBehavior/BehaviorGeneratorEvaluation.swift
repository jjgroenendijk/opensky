// Generator evaluation: a depth-first walk from the root generator, children in
// declared order. A node reached twice is evaluated twice, because both parents want
// its pose. A class without semantics passes its child's or the reference pose and adds
// a `BehaviorTally` entry (docs/engine/behavior-runtime.md). State machines continue
// in `BehaviorStateMachineEvaluation.swift`.

import Foundation
public import OpenSkyFormatsAnimation
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

/// One node reached in the walk: where it sits, the variable values its bindings
/// give it, and how deep the walk is.
nonisolated struct BehaviorVisit {
    let target: HKXPointerTarget
    let bound: [String: BehaviorVariableValue]
    let depth: Int
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
        let visit = BehaviorVisit(target: target, bound: boundValues(of: node), depth: depth)
        return evaluate(node.object, visit, deltaTime: deltaTime)
    }

    /// Routes one decoded object to its semantics. Split from the guard clauses
    /// above so neither half runs past the body-length limit.
    private func evaluate(
        _ object: any HKBClass,
        _ visit: BehaviorVisit,
        deltaTime: Float
    ) -> BehaviorPose {
        let (target, bound, depth) = (visit.target, visit.bound, visit.depth)
        let next = depth + 1
        let inner = BehaviorVisit(target: target, bound: bound, depth: next)
        switch object {
        case let clip as HKBClipGenerator:
            return evaluateClip(clip, at: target, bound: bound, deltaTime: deltaTime)
        case let blender as HKBBlenderGenerator:
            var bound = bound
            if let parameter = blendParameterOverrides[target] {
                bound["blendParameter"] = .real(parameter)
            }
            return evaluateBlend(
                blender.blender, bound: bound, depth: next, deltaTime: deltaTime
            )
        case let matching as HKBPoseMatchingGenerator:
            return evaluatePoseMatching(
                matching, inner, deltaTime: deltaTime
            )
        case let selector as HKBManualSelectorGenerator:
            return evaluateSelector(
                selector, bound: bound, depth: next, deltaTime: deltaTime
            )
        case let wrapper as HKBModifierGenerator:
            let pose = skeleton.absolute(evaluateGenerator(
                at: wrapper.generator, depth: next, deltaTime: deltaTime
            ))
            return applyModifier(at: wrapper.modifier, to: pose, deltaTime: deltaTime)
        case let machine as HKBStateMachine:
            return evaluateStateMachine(
                machine, inner, deltaTime: deltaTime
            )
        default:
            return evaluateBethesda(
                object, inner, deltaTime: deltaTime
            )
        }
    }

    /// The Bethesda generator classes and the leftovers, kept in their own
    /// switch so neither routing function grows past the complexity limit.
    private func evaluateBethesda(
        _ object: any HKBClass,
        _ visit: BehaviorVisit,
        deltaTime: Float
    ) -> BehaviorPose {
        let (bound, depth) = (visit.bound, visit.depth)
        switch object {
        case let tagging as BSiStateTaggingGenerator:
            noteStateTag(of: tagging, bound: bound)
            return evaluateGenerator(
                at: tagging.defaultGenerator, depth: depth, deltaTime: deltaTime
            )
        case let switcher as BSBoneSwitchGenerator:
            return evaluateBoneSwitch(switcher, depth: depth, deltaTime: deltaTime)
        case let cyclic as BSCyclicBlendTransitionGenerator:
            return evaluateCyclicBlend(
                cyclic, visit, deltaTime: deltaTime
            )
        case let offset as BSOffsetAnimationGenerator:
            return evaluateOffsetAnimation(
                offset, visit, deltaTime: deltaTime
            )
        case is HKBReferencePoseGenerator:
            return skeleton.restPose
        case let synced as BSSynchronizedClipGenerator:
            return evaluateSynchronizedClip(
                synced, depth: depth, deltaTime: deltaTime
            )
        case let reference as HKBBehaviorReferenceGenerator:
            return evaluateBehaviorReference(reference, deltaTime: deltaTime)
        case let sequence as BGSGamebryoSequenceGenerator:
            if let name = sequence.sequence, !name.isEmpty {
                gamebryoSequencesThisUpdate.append(name)
            }
            return skeleton.restPose
        default:
            tally.noteUnevaluatedGenerator(object.className)
            return skeleton.restPose
        }
    }

    // MARK: - Blending

    /// `hkbBlenderGenerator`: mixes child poses by `m_weight` and root travel by
    /// `m_worldFromModelWeight`. A bone whose weights sum to at most
    /// `m_referencePoseWeightThreshold` takes the reference pose for the rest.
    public func evaluateBlend(
        _ blender: HKBBlenderFields,
        bound: [String: BehaviorVariableValue],
        depth: Int,
        deltaTime: Float,
        weights: [Float]? = nil
    ) -> BehaviorPose {
        let threshold = bound.float(
            "m_referencePoseWeightThreshold",
            or: blender
                .referencePoseWeightThreshold
        )
        let children = blendChildren(
            blender, bound: bound, depth: depth, deltaTime: deltaTime, weights: weights
        )
        let masked = children.map {
            BehaviorPoseMath.MaskedChild(
                pose: $0.pose, weight: $0.weight, boneWeights: $0.boneWeights
            )
        }
        let full = masked.filter { !$0.pose.isAdditive }
        var blended = full.isEmpty
            ? BehaviorPoseMath.unchanged(boneCount: skeleton.referencePose.count)
            : BehaviorPoseMath.blend(
                masked: full, fallback: skeleton.restPose, referenceThreshold: threshold
            )
        // Each additive child adds on top at its own weight, after the normal children.
        for layer in masked where layer.pose.isAdditive {
            blended = BehaviorPoseMath.adding(
                layer.pose,
                to: blended,
                weight: layer.weight(ofBone:)
            )
        }
        blended.rootMotion = BehaviorPoseMath
            .blend(
                children: children.map { ($0.pose, $0.motionWeight) },
                fallback: skeleton.restPose
            )
            .rootMotion
        return blended
    }

    /// The decoded per-bone mask at `target`, honouring a binding on it, or nil
    /// when the child carries none.
    func boneWeights(at target: HKXPointerTarget?) -> [Float]? {
        guard
            let target,
            let array = object(at: target, as: HKBBoneWeightArray.self),
            !array.boneWeights.isEmpty
        else { return nil }
        markReached(target)
        return array.boneWeights
    }

    // MARK: - Object access

    /// The decoded object at `target` as `Value`, or nil.
    public func object<Value: HKBClass>(at target: HKXPointerTarget, as _: Value.Type) -> Value? {
        object(at: target) as? Value
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
