// Generator evaluation (issue #187): the walk that turns a decoded node tree
// into one pose.
//
// The traversal is depth first from the root generator, children in the order
// the class declares them, first-reach activation, and no revisit protection
// beyond the depth cap — a behavior graph is a DAG, and a generator legitimately
// reached twice in one update (a blender child that is also a selector child)
// is evaluated twice, because both parents want its pose.
//
// Every class the class registry decodes is routed here. A class with real
// semantics gets them; a class without gets its child's pose, or the reference
// pose, plus a `BehaviorTally` entry naming what is still owed. Nothing is
// silently approximated: `docs/engine/behavior-runtime.md` lists every entry
// this file can produce and what it will take to clear it.
//
// State machines are deliberately shallow here. Item 14.4 (#330) owns
// transitions, transition effects, and synchronization; what this file does is
// run the start state so that the tree below a state machine is exercised at
// all, and tally `stateMachineStartStateOnly` every time.

import Foundation
import simd

nonisolated extension BehaviorGraphInstance {
    /// The pose of the generator at `target`, or the reference pose when there
    /// is nothing there to evaluate.
    func evaluateGenerator(
        at target: HKXPointerTarget?,
        depth: Int,
        deltaTime: Float
    ) -> BehaviorPose {
        guard let target else { return skeleton.restPose }
        guard depth < Self.maximumDepth else {
            tally.note(.depthCapReached)
            return skeleton.restPose
        }
        guard let object = object(at: target) else { return skeleton.restPose }
        markReached(target)
        tally.noteGenerator()
        if isDisabled(object) {
            tally.note(.disabledNode)
            return skeleton.restPose
        }
        let bound = boundValues(of: object)
        return evaluate(
            object, at: target, bound: bound, depth: depth, deltaTime: deltaTime
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
                machine, bound: bound, depth: next, deltaTime: deltaTime
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
            tally.notePartialGenerator(BSSynchronizedClipGenerator.className)
            return evaluateGenerator(
                at: synced.clipGenerator, depth: depth, deltaTime: deltaTime
            )
        case is HKBBehaviorReferenceGenerator:
            tally.note(.unresolvedBehaviorReference)
            return skeleton.restPose
        default:
            _ = bound
            tally.noteUnevaluatedGenerator(object.className)
            return skeleton.restPose
        }
    }

    // MARK: - Blending

    /// `hkbBlenderGenerator`: every child evaluated, poses mixed by normalized
    /// weight. The pose blend uses `m_weight`; the root travel uses
    /// `m_worldFromModelWeight`, which is the member whose whole purpose is to
    /// let a child drive motion without driving the pose.
    ///
    /// A child under `m_referencePoseWeightThreshold` is dropped rather than
    /// blended, which is what the member is for.
    func evaluateBlend(
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
        var weighted: [(pose: BehaviorPose, weight: Float)] = []
        var motions: [(pose: BehaviorPose, weight: Float)] = []
        for childTarget in blender.children.compactMap(\.self) {
            guard let child = object(at: childTarget, as: HKBBlenderGeneratorChild.self)
            else { continue }
            markReached(childTarget)
            let childBound = boundValues(of: child)
            let weight = childBound.float("m_weight", or: child.weight)
            guard weight > threshold else { continue }
            if child.boneWeights != nil {
                tally.note(.blenderBoneWeights)
            }
            let pose = evaluateGenerator(
                at: child.generator, depth: depth, deltaTime: deltaTime
            )
            weighted.append((pose, weight))
            motions.append((
                pose,
                childBound.float("m_worldFromModelWeight", or: child.worldFromModelWeight)
            ))
        }
        var blended = BehaviorPoseMath.blend(
            children: weighted, fallback: skeleton.restPose
        )
        blended.rootMotion = BehaviorPoseMath
            .blend(children: motions, fallback: skeleton.restPose)
            .rootMotion
        return blended
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
            return skeleton.restPose
        }
        return evaluateGenerator(
            at: selector.generators[index], depth: depth, deltaTime: deltaTime
        )
    }

    // MARK: - State machines (start state only, issue #330)

    /// Runs the state machine's start state and nothing else. Transitions,
    /// wildcard transitions, transition effects, and event-driven state changes
    /// are item 14.4's, so every call here costs one
    /// `stateMachineStartStateOnly` tally entry.
    ///
    /// `m_startStateMode` 1 reads the start state id from `m_syncVariableIndex`,
    /// which is cheap and honest, so it is honoured. Mode 2 re-enters whatever
    /// was current at deactivation, which needs the transition history this
    /// item does not keep, so it falls back to `m_startStateId`.
    func evaluateStateMachine(
        _ machine: HKBStateMachine,
        bound: [String: BehaviorVariableValue],
        depth: Int,
        deltaTime: Float
    ) -> BehaviorPose {
        tally.note(.stateMachineStartStateOnly)
        // `m_startStateId` is the most-bound member in the vanilla player
        // graph after `blendParameter`: binding it is how the authored data
        // picks a state without a transition.
        var stateId = bound.int("startStateId", or: machine.startStateId)
        if
            machine.startStateMode == 1,
            let synced = variables.value(at: machine.syncVariableIndex)
        {
            stateId = synced.intValue
        }
        let states = machine.states.compactMap(\.self)
        for stateTarget in states {
            guard
                let info = object(at: stateTarget, as: HKBStateMachineStateInfo.self),
                info.stateId == stateId, info.enable
            else {
                continue
            }
            markReached(stateTarget)
            return evaluateGenerator(
                at: info.generator, depth: depth, deltaTime: deltaTime
            )
        }
        tally.note(.stateMachineNoStartState)
        return skeleton.restPose
    }
}
