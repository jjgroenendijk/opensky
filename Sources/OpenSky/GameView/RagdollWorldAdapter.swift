// App side of `RagdollCoordinator`: steps it from the renderer's frame hooks and
// answers `RagdollSessionWorld` from the streamer, the render scene, and the
// other session systems. The rules live in the coordinator
// (docs/engine/coordinators.md).

import OpenSkyActorPresentation
import OpenSkyActors
import OpenSkyActorsInterface
import OpenSkyCells
import OpenSkyCombat
import OpenSkyCombatInterface
import OpenSkyCrime
import OpenSkyEffects
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventory
import OpenSkyInventoryInterface
import OpenSkyMagic
import OpenSkyMenus
import OpenSkyPhysics
import OpenSkyPlayer
import OpenSkyRendering
import OpenSkyScripting
import OpenSkySessionInterface
import OpenSkyWorld
import OpenSkyWorldInterface
import OpenSkyWorldState
import simd

/// What `RagdollWorldAdapter` reads from the session. `GameViewController` conforms.
@MainActor
protocol RagdollWorldHost: AnyObject {
    var audio: any AudioPort { get }
    func actorPlayback(for key: ReferenceKey) -> (any ActorAnimationPlaybackPort)?
    var actorGraphWorld: any ActorGraphWorldPort { get }
    var actorValues: any ActorValuePort { get }
    func animatedPose(for key: ReferenceKey) -> [String: float4x4]?
    var audioFileSystem: (any GameFileSource)? { get }
    var cinematicWorld: any CinematicCameraWorldPort { get }
    var containerMenu: any ContainerMenuPort { get }
    var crime: any CrimePort { get }
    var effects: any EffectsPort { get }
    var effectsWorld: any EffectsWorldPort { get }
    var inventory: any InventoryPort { get }
    var magic: any MagicPort { get }
    var menuWorld: any MenuWorldPort { get }
    var ragdoll: any RagdollPort { get }
    var renderer: (any RendererPort)? { get }
    var gameSession: (any GameSessionPort)? { get }
    var scripts: any ScriptPort { get }
    var storyWorld: any StoryWorldPort { get }
    var streamer: (any CellStreamerPort)? { get }
    var worldData: WorldDataStores? { get }
    var worldState: any WorldStateStorePort { get }
    var hud: any HUDPort { get }
    var messages: any MessageCoordinatorPort { get }
    var mapWorld: any MapWorldPort { get }
    var saveGames: any SaveGameWorldPort { get }
    var titleMenu: any TitleMenuPort { get }
    func quitToMainMenu()
}

/// Answers `RagdollSessionWorld` from the session systems `game` owns.
final class RagdollWorldAdapter {
    unowned let game: any RagdollWorldHost

    init(game: any RagdollWorldHost) {
        self.game = game
    }

    /// Nil without game data, so the runtime stays nil.
    func sessionData() -> RagdollSessionData? {
        game.worldData.map { provider in
            RagdollSessionData(
                collisionModels: game.audioFileSystem.map(NIFCollisionLibrary.init),
                deathSettings: DeathSettings.resolve(store: provider.gameSettings)
            )
        }
    }

    /// A world-tick step, so the ragdolls see the same simulated
    /// delta as the other systems, and a menu-paused frame stops a falling
    /// corpse. The pose reaches the scene on the drawn frame, so a paused
    /// corpse stays where it was.
    func wireRagdoll(gameSession: GameSession) {
        let ragdoll = game.ragdoll
        let worldTick = gameSession.worldTick
        worldTick.register(.ragdoll) { [weak self, weak ragdoll, weak gameSession] delta in
            guard let ragdoll, let gameSession else { return }
            let locomotion = gameSession.locomotion
            self?.run(ragdoll.advance(
                events: locomotion.graphEvents.drain(locomotion.ragdollEventConsumer),
                controls: locomotion.ragdollGraphControls,
                delta: delta
            ))
            self?.advancePlayerDeath(delta: delta)
            if let streamer = self?.game.streamer {
                ragdoll.runtime?.solveLinks(to: &streamer.dynamicBodies, frameTime: delta)
            }
        }
        gameSession.frameSteps.register(.ragdoll) { [weak self, weak ragdoll] _ in
            self?.run(ragdoll?.publishPoses() ?? [])
        }
    }

    func run(_ commands: [RagdollCommand]) {
        for command in commands {
            switch command {
            case let .reportMurder(key):
                game.crime.reportMurder(of: key)
                game.cinematicWorld.actorDied(key)
            case let .publishPoses(poses):
                game.renderer?.scene.ragdollPoses = poses
            case let .publishPlayerRagdoll(bones):
                game.gameSession?.playerBody?.animation.setRagdollBones(bones)
            case let .publishSeveredHeads(poses):
                game.renderer?.scene.severedHeadPoses = poses
            case let .enterBleedout(key):
                enterBleedout(key)
            case let .leaveBleedout(key):
                leaveBleedout(key)
            case let .enterKnockdown(key):
                enterKnockdown(key)
            case let .getUp(key, feet, yaw):
                getUp(key, feet: feet, yaw: yaw)
            case let .endKnockdown(key):
                endKnockdown(key)
            }
        }
    }
}

extension RagdollWorldAdapter: RagdollSessionWorld {
    var ragdollResidents: [RagdollResident] {
        guard let streamer = game.streamer else { return [] }
        return streamer.residentActorEntries().compactMap { entry in
            entry.placedActor.map {
                RagdollResident(key: entry.key, position: $0.placement.position)
            }
        }
    }

    var residentRagdollCells: Set<CellSceneLocation> {
        game.streamer?.residentCellLocations ?? []
    }

    func hasZeroHealth(_ key: ReferenceKey) -> Bool {
        guard let values = game.actorValues.runtime, let holder = holder(of: key) else {
            return false
        }
        return values.hasZeroHealth(holder)
    }

    func holder(of key: ReferenceKey) -> ActorValueHolder? {
        if key == .player {
            return .player
        }
        guard
            let streamer = game.streamer,
            let actor = streamer.referenceEntry(key: key)?.placedActor
        else { return nil }
        return ActorValueHolder(
            key: key, subject: .actor(base: actor.base), cell: streamer.cellLocation(of: key)
        )
    }

    func ragdollPose(of key: ReferenceKey) -> RagdollActorPose? {
        if key == .player {
            return playerRagdollPose
        }
        guard
            let renderer = game.renderer,
            let streamer = game.streamer,
            let actor = streamer.referenceEntry(key: key)?.placedActor,
            let playback = game.actorPlayback(for: key),
            let animated = playback.clip.orderedWorldTransforms(at: renderer.animationTime)
        else { return nil }
        return RagdollActorPose(
            reference: actor.formID,
            cell: streamer.cellLocation(of: key) ?? .interior(actor.formID),
            scale: actor.scale,
            actorToWorld: MatrixMath.placement(
                position: actor.placement.position,
                rotation: actor.placement.rotation,
                scale: actor.scale
            ),
            skeletonMeshPath: playback.clip.skeletonMeshPath,
            skeleton: playback.clip.skeleton,
            animatedBoneMatrices: animated
        )
    }

    func animatedPose(of key: ReferenceKey) -> [String: float4x4]? {
        if key == .player {
            return game.gameSession?.playerBody?.animation.animatedBonesByName
        }
        return game.animatedPose(for: key)
    }

    /// The player body is drawn apart from the cell's actors, so its pose comes from
    /// the graph's buffer and its placement from the body.
    private var playerRagdollPose: RagdollActorPose? {
        guard
            let body = game.gameSession?.playerBody,
            let skeletonPath = body.assembly.visual.skeletonPath
                .flatMap({ try? VirtualFileSystem.meshPath($0) }),
            let animated = body.animation.animatedBoneMatrices,
            let cell = game.streamer?.currentCellLocation
        else { return nil }
        return RagdollActorPose(
            reference: FormID(0x14),
            cell: cell,
            scale: 1,
            actorToWorld: body.transform,
            skeletonMeshPath: skeletonPath,
            skeleton: body.animation.skeleton,
            animatedBoneMatrices: animated
        )
    }

    /// Membership in `raisedEvents` after the raise is the graph's own answer.
    func raisePlayerGraphEvent(_ name: String) -> Bool {
        guard let gameSession = game.gameSession else { return false }
        gameSession.locomotion.raise(name)
        return gameSession.locomotion.status.raisedEvents.contains(name)
    }

    /// The same static broadphase the player capsule queries.
    var ragdollStepWorld: DynamicStepWorld {
        guard let streamer = game.streamer else { return DynamicStepWorld() }
        return DynamicStepWorld(
            staticCandidates: { [weak streamer] bounds in
                streamer?.collisionCandidates(overlapping: bounds) ?? []
            }
        )
    }

    func unloadedActorHome(of key: ReferenceKey) -> CellSceneLocation? {
        guard
            let streamer = game.streamer, streamer.referenceEntry(key: key) == nil,
            let placement = streamer.pluginPlacement(of: key), placement.entry.placedActor != nil
        else { return nil }
        return placement.home
    }

    func queueActorDeathEvents(for key: ReferenceKey, killer: ReferenceKey?) -> Int {
        if game.scripts.bridge?.silentDeath != key {
            game.storyWorld.reportKill(victim: key, killer: killer)
        }
        game.scripts.bridge?.recordKill(victim: key, killer: killer)
        game.magic.noteDeath(of: key, killer: killer)
        clearLocations(afterDeathOf: key)
        grantDeathItem(to: key)
        return game.scripts.runtime?.queueActorDeath(actor: key, killer: killer) ?? 0
    }

    /// A location whose last living, enabled boss died clears itself
    /// (docs/formats/locations.md).
    private func clearLocations(afterDeathOf victim: ReferenceKey) {
        guard let store = game.worldData?.locationStore, let bridge = game.scripts.bridge
        else { return }
        let world = game.worldState
        let streamer = game.streamer
        let enable = EnableParentResolver(
            delta: { world.delta(for: $0) },
            parent: { streamer?.referenceEntry(formID: $0) }
        )
        let cleared = store.locationsCleared(byDeathOf: victim) { boss in
            if world.component(ActorDeathState.self, for: boss)?.isDead == true {
                return true
            }
            if let entry = streamer?.referenceEntry(key: boss) {
                return !enable.isEnabled(entry)
            }
            return world.component(ReferenceEnableState.self, for: boss)?.isEnabled == false
        }
        for location in cleared {
            bridge.markLocationCleared(
                ReferenceKey(resolved: location), playsMusic: store.playsClearedMusic(location)
            )
        }
    }

    /// The death item rolls at the actor's own level (docs/engine/leveled-lists.md).
    private func grantDeathItem(to key: ReferenceKey) {
        guard
            let values = game.actorValues.runtime,
            let holder = holder(of: key)
        else { return }
        game.inventory.grantDeathItem(to: key, actorLevel: values.baseline(of: holder).level)
    }

    var selectedRagdollActor: ReferenceKey? {
        guard let streamer = game.streamer else { return nil }
        if
            let target = streamer.interactionTarget,
            let entry = streamer.referenceEntry(formID: target.interaction.reference),
            entry.placedActor != nil
        {
            return entry.key
        }
        return playerFeetPosition.flatMap { streamer.nearestActorEntry(to: $0)?.key }
    }

    var playerFeetPosition: SIMD3<Float>? {
        game.gameSession?.walkController.feetPosition
    }

    /// An ACHR's holder re-derives its baseline from the NPC_'s CNTO list, as
    /// a chest's does, so the corpse needs no new menu.
    func searchCorpse(_ key: ReferenceKey) -> Bool {
        guard
            game.inventory.runtime != nil,
            let streamer = game.streamer,
            let actor = streamer.referenceEntry(key: key)?.placedActor
        else { return false }
        game.containerMenu.target(
            InventoryHolder(
                key: key, owner: .actor(base: actor.base), cell: streamer.cellLocation(of: key)
            ),
            name: "Corpse \(key.description)"
        )
        return true
    }
}
