// The idle selector, clip cache, and report book-keeping of `IdleCoordinator`.

import Foundation
import OpenSkyConditions
import OpenSkyFormatsAnimation
import OpenSkyFormatsCore
public import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyRuntimeState
import OpenSkyWorldConditionFunctions
import OpenSkyWorldInterface
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

extension IdleCoordinator.Playing {
    /// The object change an annotation makes: nil when it changes nothing, else the
    /// prop to show, or a nil prop to remove the one shown. The player has no playback,
    /// so no prop.
    mutating func applyAnimationObject(_ name: String) -> ActorPropAttachment?? {
        guard
            playback != nil,
            let change = IdleCore.objectChange(
                for: name, objects: animationObjects, shown: shownObject
            )
        else { return nil }
        switch change {
        case let .show(object):
            guard let prop = Self.attachment(object.prop) else { return nil }
            hasProp = true
            shownObject = object
            return .some(prop)
        case .remove:
            hasProp = false
            shownObject = nil
            return .some(nil)
        }
    }

    static func attachment(_ prop: IdleProp) -> ActorPropAttachment? {
        guard case let .attached(_, modelPath, bone) = prop else { return nil }
        return ActorPropAttachment(modelPath: modelPath, bone: bone)
    }

    /// A bone of the clip at `now`, in the actor's root frame.
    func boneMatrix(named bone: String, at now: Float) -> float4x4? {
        guard
            now < end,
            let pose = clip.worldPose(at: max(0, now - start)),
            let index = pose.bones.index(of: bone),
            pose.matrices.indices.contains(index)
        else { return nil }
        return pose.matrices[index]
    }

    func bone(named bone: String, at now: Float) -> SIMD3<Float>? {
        boneMatrix(named: bone, at: now).map { matrix in
            SIMD3(matrix.columns.3.x, matrix.columns.3.y, matrix.columns.3.z)
        }
    }

    /// Where the bone faces: the bind pose faces +Y, so this is +Y turned as the clip
    /// turns the bone away from its bind pose.
    func boneForward(named bone: String, at now: Float) -> SIMD3<Float>? {
        guard
            let posed = boneMatrix(named: bone, at: now),
            let index = clip.boneIndex.index(of: bone)
        else { return nil }
        let bind = clip.bindWorldMatrices
        guard bind.indices.contains(index) else { return nil }
        let turn = posed * bind[index].inverse
        let forward = turn * SIMD4<Float>(0, 1, 0, 0)
        return SIMD3(forward.x, forward.y, forward.z)
    }
}

/// The condition checks the idle selector runs.
enum IdleConditionChecks {
    /// The name of the first function whose condition fails, or nil when all pass.
    static func firstFailingFunction(
        in conditions: [Condition], context: ConditionContext
    ) -> String? {
        var evaluator = ConditionEvaluator(context: context)
        return evaluator.firstFailure(in: conditions).map(evaluator.functionName(of:))
    }

    /// One attack and whether it kills, for `ShouldAttackKill`.
    static func attack(
        attacker: ReferenceKey, target: ReferenceKey, kills: Bool
    ) -> AttackKillResolution {
        AttackKillResolution(attacks: [
            AttackKillResolution.Attack(attacker: attacker, target: target, kills: kills)
        ])
    }
}

extension IdleCoordinator {
    func conditionContext(for actor: ReferenceKey) -> ConditionContext {
        var context = worldConditionContext()
        context.subject = actor
        context.furniture = furnitureResolution
        // A furniture idle tests the furniture as its Target, such as its keywords.
        context.target = furnitureUses[actor]?.furniture
        // An actor whose graph does not run reads 0 for every variable.
        if
            context[resolution: GraphVariableResolution.self].graphs[actor] == nil,
            actor != .player
        {
            context[resolution: GraphVariableResolution.self].values[actor] = [:]
            context[resolution: GraphVariableResolution.self].floats[actor] = [:]
        }
        return context
    }

    /// Within one `advance`, actors share the world's context until a state write.
    func worldConditionContext() -> ConditionContext {
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

    /// `target` replaces the furniture as the conditions' Target, such as a dragon's perch.
    /// `adjust` adds what only the caller knows, such as whether its attack kills.
    func selector(
        for actor: ReferenceKey,
        target: ReferenceKey? = nil,
        adjust: ((inout ConditionContext) -> Void)? = nil
    ) -> IdleSelector {
        var base: ConditionContext?
        let project = graphProject(of: actor)
        let check: IdleSelector.Check = { [weak self] idle in
            // A tree such as `ActionActivate` mixes idles of several graphs, like a lever's.
            if let project, !IdleCore.idle(behaviorFile: idle.fileName, belongsTo: project) {
                return "behavior graph"
            }
            var context = base ?? self?.conditionContext(for: actor) ?? ConditionContext()
            if base == nil, let target {
                context.target = target
            }
            if base == nil {
                adjust?(&context)
            }
            base = context
            context.functions = self?.conditionFunctions ?? .empty
            return IdleConditionChecks.firstFailingFunction(in: idle.conditions, context: context)
        }
        guard let store else {
            return IdleSelector(children: { _ in [] }, check: check)
        }
        return IdleSelector(store: store, check: check)
    }

    /// The project folder of the actor's graph, read from its skeleton path:
    /// `meshes\actors\character\` for a human.
    func graphProject(of actor: ReferenceKey) -> String? {
        let skeleton = actorPlayback(actor)?.clip.skeletonMeshPath
            ?? (actor == .player ? Self.playerSkeletonPath : nil)
        return skeleton.flatMap(IdleCore.graphProject(skeletonMeshPath:))
    }

    /// Shows or removes the object an annotation names. It replaces the graph's prop,
    /// because an actor carries one prop.
    func applyAnimationObject(_ name: String, to playing: inout Playing, on actor: ReferenceKey) {
        if let change = playing.applyAnimationObject(name) {
            world?.setProp(change, on: actor)
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
            actorPlayback(actor)?.endOverride()
        }
        if playing.hasProp {
            world?.setProp(nil, on: actor)
        }
    }

    /// A bone of the clip `actor` plays now, in the actor's root frame. The player's
    /// seat idle places its eye this way.
    public func idleBone(of actor: ReferenceKey, named bone: String) -> SIMD3<Float>? {
        guard let now = world?.idleAnimationTime else { return nil }
        return sessions[actor]?.playing?.bone(named: bone, at: now)
    }

    /// Where the bone faces in the actor's root frame: the bind pose faces +Y, so this
    /// is +Y turned as the clip turns the bone away from its bind pose.
    public func idleBoneForward(of actor: ReferenceKey, named bone: String) -> SIMD3<Float>? {
        guard let now = world?.idleAnimationTime else { return nil }
        return sessions[actor]?.playing?.boneForward(named: bone, at: now)
    }

    /// The start of the idle `actor` plays now, so a caller acts once per idle.
    public func idleStart(of actor: ReferenceKey) -> Float? {
        sessions[actor]?.playing?.start
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
