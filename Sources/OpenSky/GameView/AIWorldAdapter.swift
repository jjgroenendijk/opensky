// App side of the AI coordinators: packages, the AI & Navigation panel, NPC
// gait clips, and perception. It wires them into the frame loop and answers
// their ports from the session systems. See docs/engine/coordinators.md.

import OpenSkyActorsInterface
import OpenSkyCombat
import OpenSkyConditions
import OpenSkyCrime
import OpenSkyDiagnostics
import OpenSkyFactions
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyPerception
import OpenSkyPerceptionInterface
import OpenSkyPhysics
import OpenSkyQuestsInterface
import OpenSkyRendering
import OpenSkyScripting
import OpenSkyWorld
import OpenSkyWorldInterface
import OpenSkyWorldState
import simd

final class AIWorldAdapter {
    unowned let game: GameViewController

    init(game: GameViewController) {
        self.game = game
    }

    func wireAIOverlay(renderer: Renderer, streamer: CellStreamer) {
        renderer.worldOverlaySources
            .register(identifier: "navigation") { [weak streamer] context, list in
                streamer?.appendNavigationWorldOverlay(context: context, to: &list)
            }
    }

    func wireNPCMovement(renderer: Renderer, streamer: CellStreamer) {
        streamer.npcMovementConfiguration = renderer.locomotion.configuration
        let worldState = game.worldState
        streamer.onNPCMovementPersist = { persistence in
            worldState.set(persistence.transform, for: persistence.actor, in: persistence.cell)
        }
        streamer.onNPCPosesChanged = { [weak renderer] deltas in
            renderer?.npcInstanceDeltas = deltas
        }
        let animation = game.npcAnimation
        streamer.onNPCLocomotionDrive = { [weak animation] update in
            animation?.drive(update)
        }
    }

    /// Package conditions read the live quest, actor and reference state, so
    /// selection advances after those runtimes in the same world tick.
    func wirePackages(provider: any WorldDataProviding, renderer: Renderer) {
        guard let store = (provider as? PackageDataProviding)?.packageStore else { return }
        game.packages.wire(store: store)
        let packages = game.packages
        let advancePreviousSystems = renderer.onWorldUpdate
        renderer.onWorldUpdate = { [weak packages] delta in
            advancePreviousSystems?(delta)
            packages?.advance()
        }
    }

    /// Runs after NPC movement and the combat loop, because the pass reads
    /// where actors ended up this frame and which of them are hostile.
    func wirePerception(provider: any WorldDataProviding, renderer: Renderer) {
        guard let settings = (provider as? CombatDataProviding)?.detectionSettings else {
            return
        }
        let perception = game.perception
        let crime = game.crime
        perception.wire(settings: settings)
        let advanceWorld = renderer.onWorldUpdate
        renderer.onWorldUpdate = { [weak perception, weak crime] delta in
            advanceWorld?(delta)
            perception?.advance(by: delta)
            // After the pass, so a trespass is judged against this frame's detection.
            crime?.advanceTrespass()
            // After the trespass, so the guards see a bounty charged this frame.
            crime?.advanceGuardResponse()
        }
        renderer.worldOverlaySources
            .register(identifier: "detection") { [weak perception] context, list in
                perception?.appendWorldOverlay(context: context, to: &list)
            }
    }
}

extension AIWorldAdapter: PackageWorld {
    func packageResidents() -> [RuntimeReferenceEntry]? {
        guard game.renderer != nil else { return nil }
        return game.streamer?.residentActorEntries()
    }

    var packageClock: GameClock? {
        game.renderer?.gameClock
    }

    func packageConditionContext(clock: GameClock) -> ConditionContext {
        ConditionContext(
            globals: game.runtimeState.globalResolution(),
            quests: game.scripts.bridge?.questRuntime?.resolution() ?? .empty,
            aliases: game.scripts.bridge?.questRuntime?.aliasResolution() ?? .empty,
            actors: game.runtimeStateWorld.actorResolution(),
            detection: game.perception.perceptionResolution(),
            referenceEnable: ReferenceEnableResolution(snapshot: game.worldState.snapshot()),
            clock: clock,
            references: game.streamer?.residentReferenceIndex()
                ?? RuntimeReferenceIndex(entries: [])
        )
    }
}

extension AIWorldAdapter: AINavigationWorld {
    var isStreaming: Bool {
        game.streamer != nil
    }

    var camera: AICameraPose? {
        game.renderer.map {
            AICameraPose(position: $0.freeFlyCamera.position, forward: $0.freeFlyCamera.forward)
        }
    }

    func actorCandidates() -> [AIActorCandidate] {
        game.actorWorld.combatActors().map {
            AIActorCandidate(key: $0.key, name: $0.name, feet: $0.feet, isDead: $0.isDead)
        }
    }

    func collisionCandidates(overlapping bounds: ModelBounds) -> [StaticCollisionShape] {
        game.streamer?.collisionCandidates(overlapping: bounds) ?? []
    }

    func residentActor(for reference: FormID) -> ReferenceKey? {
        game.streamer?.residentActorEntries().first { $0.formID == reference }?.key
    }

    func movementReadout(for actor: ReferenceKey) -> NPCMovementReadout? {
        game.streamer?.npcMovementReadouts().first { $0.actor == actor }
    }

    var activeMoverCount: Int {
        game.streamer?.npcMovement.activeMoverCount ?? 0
    }

    func moveActor(_ actor: ReferenceKey, to point: SIMD3<Float>) -> NPCMoveCommandResult {
        game.streamer?.moveActor(actor, to: point) ?? .actorNotResident
    }

    func stopActor(_ actor: ReferenceKey) -> Bool {
        game.streamer?.stopActor(actor) ?? false
    }

    func isHostile(_ actor: ReferenceKey) -> Bool {
        game.factions.hostility(of: actor) == .hostile
    }

    func setHostile(_ hostile: Bool, actor: ReferenceKey) {
        game.factions.setHostility(hostile ? .hostile : .neutral, on: actor)
    }
}

extension AIWorldAdapter: NPCAnimationWorld {
    func actorPlayback(for actor: ReferenceKey) -> ActorAnimationPlayback? {
        game.actorPlayback(for: actor)
    }

    var animationClips: ActorClipLoader? {
        game.sessionWiring.animationClips
    }
}

extension AIWorldAdapter: PerceptionSessionWorld {
    func perceptionCandidates() -> [PerceptionCandidate] {
        let packaged = Set(game.packages.readouts().filter { $0.currentPackage != nil }
            .map(\.actor))
        let isExterior = game.streamer?.interiorScene == nil
        return game.actorWorld.combatActors().map { actor in
            PerceptionCandidate(
                observer: PerceptionObserver(
                    key: actor.key,
                    feet: actor.feet,
                    eye: actor.feet + SIMD3(0, 0, actor.capsule.eyeHeight * max(actor.scale, 0)),
                    facing: actor.facing,
                    isExterior: isExterior,
                    label: actor.label
                ),
                isDead: actor.isDead,
                isHostile: game.factions.hostility(of: actor.key) == .hostile,
                isEngaged: game.combat.loop?.phase(of: actor.key)?.isEngaged == true,
                hasPackage: packaged.contains(actor.key)
            )
        }
    }

    func perceptionTargets() -> [PerceptionTarget] {
        guard let renderer = game.renderer else { return [] }
        let status = renderer.locomotion.status
        let isMoving = simd_length_squared(status.lastPlan.horizontalDisplacement) > 0
        return [PerceptionTarget(
            key: .player,
            feet: status.feetPosition,
            eye: status.feetPosition + SIMD3(0, 0, PlayerCapsule.standard.eyeHeight),
            gait: isMoving ? status.gait : nil,
            isSneaking: status.gait == .sneak,
            equippedWeight: 0,
            name: "Player"
        )]
    }

    func perceptionHasLineOfSight(from origin: SIMD3<Float>, to destination: SIMD3<Float>) -> Bool {
        guard let streamer = game.streamer else { return true }
        let offset = destination - origin
        let distance = simd_length(offset)
        guard
            distance.isFinite, distance > 0,
            let ray = InteractionRay(origin: origin, direction: offset, maximumDistance: distance)
        else { return true }
        let shapes = streamer.staticCollisionCandidates(overlapping: ray.bounds)
        return InteractionRaycaster.nearestHit(ray: ray, shapes: shapes) == nil
    }
}
