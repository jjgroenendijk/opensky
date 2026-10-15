// The idle selector, clip cache, and report book-keeping of `IdleCoordinator`.

import Foundation
import OpenSkyConditions
import OpenSkyFormatsAnimation
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData
import simd

extension IdleCoordinator.Playing {
    /// A held idle sends its clip's annotations again on every loop.
    mutating func repeatLoops(until now: Float) {
        let duration = clip.animation.duration
        while let loopStart = loopEnd, loopStart <= now, duration > 0 {
            events += IdleCore.markEvents(
                marks, clipDuration: duration, seconds: duration
            ).map { IdleAnimationEvent(time: loopStart + $0.time, name: $0.name) }
            loopEnd = loopStart + duration
        }
    }
}

extension IdleCoordinator {
    func conditionContext(for actor: ReferenceKey) -> ConditionContext {
        var context = world?.idleConditionContext() ?? ConditionContext()
        context.subject = actor
        context.furniture = FurnitureConditionResolution(uses: furnitureUses, isAvailable: true)
        // A furniture idle tests the furniture as its Target, such as its keywords.
        context.target = furnitureUses[actor]?.furniture
        // Only the player runs a live graph; another actor's variables read 0.
        if actor != .player {
            context.graphVariables.values[actor] = [:]
            context.graphVariables.floats[actor] = [:]
        }
        return context
    }

    func selector(for actor: ReferenceKey) -> IdleSelector {
        let base = conditionContext(for: actor)
        let project = graphProject(of: actor)
        let check: IdleSelector.Check = { idle in
            // A tree such as `ActionActivate` mixes idles of several graphs, like a lever's.
            if let project, !IdleCore.idle(behaviorFile: idle.fileName, belongsTo: project) {
                return "behavior graph"
            }
            var evaluator = ConditionEvaluator(context: base)
            return evaluator.firstFailure(in: idle.conditions).map(evaluator.functionName(of:))
        }
        guard let store else {
            return IdleSelector(children: { _ in [] }, check: check)
        }
        return IdleSelector(store: store, check: check)
    }

    /// The project folder of the actor's graph, read from its skeleton path:
    /// `meshes\actors\character\` for a human.
    func graphProject(of actor: ReferenceKey) -> String? {
        let skeleton = world?.actorPlayback(for: actor)?.clip.skeletonMeshPath
            ?? (actor == .player ? Self.playerSkeletonPath : nil)
        return skeleton.flatMap(IdleCore.graphProject(skeletonMeshPath:))
    }

    static func attachment(_ prop: IdleProp) -> ActorPropAttachment? {
        guard case let .attached(_, modelPath, bone) = prop else { return nil }
        return ActorPropAttachment(modelPath: modelPath, bone: bone)
    }

    /// Drops the prop of the idle that ends. A finite clip retires on its own; a held
    /// one is stopped.
    func endIdle(of actor: ReferenceKey) {
        positions[actor] = nil
        guard let playing = sessions[actor]?.playing else { return }
        if !playing.end.isFinite {
            world?.actorPlayback(for: actor)?.endOverride()
        }
        if playing.hasProp {
            world?.setProp(nil, on: actor)
        }
    }

    /// A bone of the clip `actor` plays now, in the actor's root frame. The player's
    /// seat idle places its eye this way.
    public func idleBone(of actor: ReferenceKey, named bone: String) -> SIMD3<Float>? {
        idleBoneMatrix(of: actor, named: bone).map { matrix in
            SIMD3(matrix.columns.3.x, matrix.columns.3.y, matrix.columns.3.z)
        }
    }

    /// Where the bone faces in the actor's root frame: the bind pose faces +Y, so this
    /// is +Y turned as the clip turns the bone away from its bind pose.
    public func idleBoneForward(of actor: ReferenceKey, named bone: String) -> SIMD3<Float>? {
        guard
            let clip = sessions[actor]?.playing?.clip,
            let posed = idleBoneMatrix(of: actor, named: bone),
            let index = clip.boneIndex.index(of: bone)
        else { return nil }
        let bind = clip.bindWorldMatrices
        guard bind.indices.contains(index) else { return nil }
        let turn = posed * bind[index].inverse
        let forward = turn * SIMD4<Float>(0, 1, 0, 0)
        return SIMD3(forward.x, forward.y, forward.z)
    }

    /// The start of the idle `actor` plays now, so a caller acts once per idle.
    public func idleStart(of actor: ReferenceKey) -> Float? {
        sessions[actor]?.playing?.start
    }

    private func idleBoneMatrix(of actor: ReferenceKey, named bone: String) -> float4x4? {
        guard
            let playing = sessions[actor]?.playing,
            let now = world?.idleAnimationTime, now < playing.end,
            let pose = playing.clip.worldPose(at: max(0, now - playing.start)),
            let index = pose.bones.index(of: bone),
            pose.matrices.indices.contains(index)
        else { return nil }
        return pose.matrices[index]
    }

    func clip(_ path: String, skeleton: String) -> AssetLoadState<ActorAnimationClip>? {
        clips?.state(of: ActorClipKey(skeletonMeshPath: skeleton, animationPath: path))
    }

    func failed(_ actor: ReferenceKey, source: String, _ reason: String) -> IdleReport {
        record(IdleReport(
            actor: actor, source: source, trace: [], chosen: nil, plan: nil, seconds: 0,
            failure: reason
        ))
    }

    func record(_ report: IdleReport) -> IdleReport {
        reports[report.actor] = report
        return report
    }
}
