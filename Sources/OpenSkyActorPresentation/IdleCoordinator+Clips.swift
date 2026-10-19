// The idle selector, clip cache, and report book-keeping of `IdleCoordinator`.

import Foundation
import OpenSkyConditions
import OpenSkyFormatsAnimation
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyRuntimeState
import OpenSkyWorldConditions
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
        var context = worldConditionContext()
        context.subject = actor
        context.furniture = FurnitureConditionResolution(uses: furnitureUses, isAvailable: true)
        // A furniture idle tests the furniture as its Target, such as its keywords.
        context.target = furnitureUses[actor]?.furniture
        // An actor whose graph does not run reads 0 for every variable.
        if context.graphVariables.graphs[actor] == nil, actor != .player {
            context.graphVariables.values[actor] = [:]
            context.graphVariables.floats[actor] = [:]
        }
        return context
    }

    /// Within one `advance`, actors share the world's context until a state write.
    private func worldConditionContext() -> ConditionContext {
        guard let world else { return ConditionContext() }
        guard isAdvancing else { return world.idleConditionContext() }
        let sequence = world.idleStateSequence
        if let passContext, passContext.sequence == sequence {
            return passContext.context
        }
        let context = world.idleConditionContext()
        passContext = (sequence, context)
        return context
    }

    func selector(for actor: ReferenceKey) -> IdleSelector {
        var base: ConditionContext?
        let project = graphProject(of: actor)
        let check: IdleSelector.Check = { [weak self] idle in
            // A tree such as `ActionActivate` mixes idles of several graphs, like a lever's.
            if let project, !IdleCore.idle(behaviorFile: idle.fileName, belongsTo: project) {
                return "behavior graph"
            }
            let context = base ?? self?.conditionContext(for: actor) ?? ConditionContext()
            base = context
            var evaluator = ConditionEvaluator(context: context)
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

    /// Shows or removes the object an annotation names. It replaces the graph's prop,
    /// because an actor carries one prop. The player has no playback, so no prop.
    func applyAnimationObject(_ name: String, to playing: inout Playing, on actor: ReferenceKey) {
        guard
            playing.playback != nil,
            let change = IdleCore.objectChange(
                for: name, objects: playing.animationObjects, shown: playing.shownObject
            )
        else { return }
        switch change {
        case let .show(object):
            guard let prop = Self.attachment(object.prop) else { return }
            world?.setProp(prop, on: actor)
            playing.hasProp = true
            playing.shownObject = object
        case .remove:
            world?.setProp(nil, on: actor)
            playing.hasProp = false
            playing.shownObject = nil
        }
    }

    /// Drops the prop of the idle that ends. A finite clip retires on its own; a held
    /// one is stopped.
    func endIdle(of actor: ReferenceKey) {
        positions[actor] = nil
        guard let playing = sessions[actor]?.playing else { return }
        if !playing.end.isFinite, playing.throughGraph {
            _ = world?.raiseIdleEvent(Self.defaultStateEvent, state: nil, on: actor)
        } else if !playing.end.isFinite {
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
