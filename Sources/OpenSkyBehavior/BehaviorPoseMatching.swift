// `hkbPoseMatchingGenerator`: picks the child clip whose start pose best matches the
// live pose, such as a ragdoll's, and blends to it
// (docs/engine/behavior-runtime.md#pose-matching).

import Foundation
import OpenSkyFormatsAnimation
public import simd

/// What one pose matcher keeps between updates.
nonisolated public struct BehaviorPoseMatchState: Equatable, Sendable {
    public var isMatching: Bool
    public var current: Int?
    /// The best child of the last update, and how long it has stayed best.
    public var best: Int?
    public var bestTime: Float = 0
    public var weights: [Float]
    /// The orientation of each child's start pose, nil where it has none.
    public var signatures: [simd_quatf?]
    public var previousPelvis: SIMD3<Float>?
}

/// The pure rules: errors, the switch test, and the weight steps.
nonisolated public enum BehaviorPoseMatchRules {
    /// `1 - |dot|`, so 0 is a perfect match and 1 the worst. No signature is worst.
    public static func errors(live: simd_quatf, signatures: [simd_quatf?]) -> [Float] {
        signatures.map { signature in
            signature.map { 1 - abs(simd_dot($0.vector, live.vector)) } ?? 1
        }
    }

    /// The time the same best child must stay best before a switch.
    public static func switchTime(error: Float, noError: Float, fullError: Float) -> Float {
        (1 - error) * noError + error * fullError
    }

    /// The current child rises to 1 at `blendSpeed` per second, the others fall to 0.
    public static func stepped(
        _ weights: [Float], toward current: Int, by amount: Float
    ) -> [Float] {
        weights.enumerated().map { index, weight in
            index == current ? min(weight + amount, 1) : max(weight - amount, 0)
        }
    }

    /// The orientation of the frame three bones span; heading about up is removed.
    public static func frame(
        root: SIMD3<Float>, other: SIMD3<Float>, another: SIMD3<Float>
    ) -> simd_quatf? {
        let axis = other - root
        let normal = simd_cross(another - root, axis)
        guard simd_length(axis) > 1e-6, simd_length(normal) > 1e-6 else { return nil }
        let first = simd_normalize(axis)
        let third = simd_normalize(normal)
        let basis = simd_float3x3(columns: (first, simd_cross(third, first), third))
        var rotation = simd_quatf(basis)
        let heading = SIMD2(first.x, first.y)
        if simd_length(heading) > 1e-4 {
            rotation = simd_quatf(angle: -atan2(heading.y, heading.x), axis: SIMD3(0, 0, 1))
                * rotation
        }
        return simd_normalize(rotation)
    }
}

nonisolated extension BehaviorGraphInstance {
    func evaluatePoseMatching(
        _ matching: HKBPoseMatchingGenerator,
        at target: HKXPointerTarget,
        bound: [String: BehaviorVariableValue],
        depth: Int,
        deltaTime: Float
    ) -> BehaviorPose {
        var node = markReached(target)
        var state = node.poseMatch ?? startPoseMatch(matching)
        applyPoseMatchEvents(matching, &state)
        if state.isMatching {
            match(matching, &state, deltaTime: deltaTime)
        }
        if let current = state.current {
            state.weights = BehaviorPoseMatchRules.stepped(
                state.weights, toward: current, by: deltaTime * matching.blendSpeed
            )
        }
        node.poseMatch = state
        nodeStates[target] = node
        return evaluateBlend(
            matching.blender, bound: bound, depth: depth,
            deltaTime: state.isMatching ? 0 : deltaTime, weights: state.weights
        )
    }

    private func startPoseMatch(
        _ matching: HKBPoseMatchingGenerator
    ) -> BehaviorPoseMatchState {
        let children = matching.blender.children
        return BehaviorPoseMatchState(
            isMatching: matching.mode == 0,
            weights: Array(repeating: 0, count: children.count),
            signatures: children.map { $0.flatMap { signature(ofChild: $0, matching) } }
        )
    }

    private func applyPoseMatchEvents(
        _ matching: HKBPoseMatchingGenerator, _ state: inout BehaviorPoseMatchState
    ) {
        for event in events.active {
            if event.id == matching.startPlayingEventId {
                state.isMatching = false
            } else if event.id == matching.startMatchingEventId {
                state.isMatching = true
                restartChild(state.current, of: matching)
            }
        }
    }

    private func match(
        _ matching: HKBPoseMatchingGenerator,
        _ state: inout BehaviorPoseMatchState,
        deltaTime: Float
    ) {
        let live = BehaviorModelPose(
            BehaviorPose(bones: characterContext.livePose ?? lastCompleteBones
                ?? skeleton.referencePose),
            skeleton: skeleton
        )
        guard let orientation = frame(of: live, matching) else { return }
        let errors = BehaviorPoseMatchRules.errors(
            live: orientation, signatures: state.signatures
        )
        guard let best = errors.indices.min(by: { errors[$0] < errors[$1] }) else { return }
        let pelvis = position(ofRagdollBone: matching.pelvisIndex, in: live)
        var speed: Float = 0
        if let pelvis, let previous = state.previousPelvis, deltaTime > 0 {
            speed = simd_distance(pelvis, previous) / deltaTime
        }
        state.previousPelvis = pelvis
        guard let current = state.current else {
            state.current = best
            state.weights = state.weights.indices.map { $0 == best ? 1 : 0 }
            state.best = best
            return
        }
        if state.best == best {
            state.bestTime += deltaTime
        } else {
            state.best = best
            state.bestTime = 0
        }
        if
            best != current,
            state.bestTime > BehaviorPoseMatchRules.switchTime(
                error: errors[best],
                noError: matching.minSwitchTimeNoError,
                fullError: matching.minSwitchTimeFullError
            ),
            speed >= matching.minSpeedToSwitch
        {
            state.current = best
        }
    }

    private func frame(
        of pose: BehaviorModelPose, _ matching: HKBPoseMatchingGenerator
    ) -> simd_quatf? {
        guard
            let root = position(ofRagdollBone: matching.rootBoneIndex, in: pose),
            let other = position(ofRagdollBone: matching.otherBoneIndex, in: pose),
            let another = position(ofRagdollBone: matching.anotherBoneIndex, in: pose)
        else { return nil }
        return BehaviorPoseMatchRules.frame(root: root, other: other, another: another)
    }

    private func position(
        ofRagdollBone index: Int, in pose: BehaviorModelPose
    ) -> SIMD3<Float>? {
        let bone = skeleton.bone(forRagdollBone: index)
        return pose.contains(bone) ? pose.translations[bone] : nil
    }

    /// The orientation of a child clip's pose at its start time.
    private func signature(
        ofChild target: HKXPointerTarget, _ matching: HKBPoseMatchingGenerator
    ) -> simd_quatf? {
        guard
            let generator = clipGenerator(underChild: target),
            let clip = clip(
                named: generator.animationName, bindingIndex: generator.animationBindingIndex
            ),
            clip.duration > 0
        else { return nil }
        let start = generator.cropStartAmountLocalTime + generator.startTime
        let samples = clip.samples(at: min(max(start, 0), clip.duration))
        let mirrored = generator.flags & 0x4 != 0 ? mirror : nil
        let bones = BehaviorPoseMath.applying(
            mirrored?.mirroring(samples, isAdditive: false) ?? samples,
            to: skeleton.referencePose
        )
        let pose = BehaviorModelPose(BehaviorPose(bones: bones), skeleton: skeleton)
        return frame(of: pose, matching)
    }

    private func clipGenerator(underChild target: HKXPointerTarget) -> HKBClipGenerator? {
        guard
            let child = object(at: target, as: HKBBlenderGeneratorChild.self),
            let generator = child.generator
        else { return nil }
        return object(at: generator, as: HKBClipGenerator.self)
    }

    /// Starting to match again plays the current child from its start.
    private func restartChild(_ index: Int?, of matching: HKBPoseMatchingGenerator) {
        guard
            let index, matching.blender.children.indices.contains(index),
            let child = matching.blender.children[index],
            let generator = object(at: child, as: HKBBlenderGeneratorChild.self)?.generator
        else { return }
        nodeStates[generator] = nil
    }
}
