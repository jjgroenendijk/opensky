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
nonisolated struct BehaviorBlendChild: Sendable {
    let pose: BehaviorPose
    let weight: Float
    let motionWeight: Float
    /// One weight per skeleton bone, or nil for a child that contributes at
    /// full weight everywhere.
    let boneWeights: [Float]?
}

/// One node reached in the walk: where it sits, the variable values its bindings
/// give it, and how deep the walk is.
nonisolated struct BehaviorVisit {
    let target: HKXPointerTarget
    let bound: [String: BehaviorVariableValue]
    let depth: Int
}

nonisolated extension BehaviorGraphInstance.Generators {
    /// The pose of the generator at `target`, or the reference pose when there
    /// is nothing there to evaluate.
    func evaluateGenerator(
        at target: HKXPointerTarget?,
        depth: Int,
        deltaTime: Float
    ) -> BehaviorPose {
        guard let target else { return graph.skeleton.restPose }
        guard depth < BehaviorGraphInstance.maximumDepth else {
            graph.tally.note(.depthCapReached)
            return graph.skeleton.restPose
        }
        guard let node = graph.compiledNode(at: target) else { return graph.skeleton.restPose }
        graph.markReached(target)
        graph.tally.noteGenerator()
        if graph.isDisabled(node) {
            graph.tally.note(.disabledNode)
            return graph.skeleton.restPose
        }
        let visit = BehaviorVisit(target: target, bound: graph.boundValues(of: node), depth: depth)
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
            return graph.clipPlayback.evaluateClip(
                clip,
                at: target,
                bound: bound,
                deltaTime: deltaTime
            )
        case let blender as HKBBlenderGenerator:
            var bound = bound
            if let parameter = graph.nodeMemory.blendParameterOverrides[target] {
                bound["blendParameter"] = .real(parameter)
            }
            return graph.blenders.evaluateBlend(
                blender.blender, bound: bound, depth: next, deltaTime: deltaTime
            )
        case let matching as HKBPoseMatchingGenerator:
            return graph.blenders.evaluatePoseMatching(
                matching, inner, deltaTime: deltaTime
            )
        case let selector as HKBManualSelectorGenerator:
            return evaluateSelector(
                selector, bound: bound, depth: next, deltaTime: deltaTime
            )
        case let wrapper as HKBModifierGenerator:
            let pose = graph.skeleton.absolute(evaluateGenerator(
                at: wrapper.generator, depth: next, deltaTime: deltaTime
            ))
            return graph.applyModifier(at: wrapper.modifier, to: pose, deltaTime: deltaTime)
        case let machine as HKBStateMachine:
            return graph.stateMachines.evaluateStateMachine(
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
            graph.noteStateTag(of: tagging, bound: bound)
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
            return graph.skeleton.restPose
        case let synced as BSSynchronizedClipGenerator:
            return graph.clipPlayback.evaluateSynchronizedClip(
                synced, depth: depth, deltaTime: deltaTime
            )
        case let reference as HKBBehaviorReferenceGenerator:
            return graph.childGraphs.evaluateBehaviorReference(reference, deltaTime: deltaTime)
        case let sequence as BGSGamebryoSequenceGenerator:
            if let name = sequence.sequence, !name.isEmpty {
                graph.gamebryoSequencesThisUpdate.append(name)
            }
            return graph.skeleton.restPose
        default:
            graph.tally.noteUnevaluatedGenerator(object.className)
            return graph.skeleton.restPose
        }
    }

    // MARK: - Selection

    /// `hkbManualSelectorGenerator`: exactly one child runs, chosen by
    /// `m_selectedGeneratorIndex`, which is normally variable-bound. An index
    /// outside the child list selects nothing and produces the reference pose,
    /// which is what Havok does with an unset selector.
    func evaluateSelector(
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
            return graph.skeleton.restPose
        }
        return evaluateGenerator(
            at: selector.generators[index], depth: depth, deltaTime: deltaTime
        )
    }
}
