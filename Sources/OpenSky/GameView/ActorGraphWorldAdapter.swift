// App side of the per-actor behaviour graphs: hands the coordinator the loaded actors
// and their race graphs, steps it in the world update, and sends each fired event to
// sounds, footsteps, and Papyrus. The rules live in `ActorGraphCoordinator`
// (docs/engine/actor-graphs.md).

import OpenSkyActorPresentation
import OpenSkyAIPackages
import OpenSkyBehavior
import OpenSkyCells
import OpenSkyCombat
import OpenSkyConditions
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyPhysics
import OpenSkyPlayer
import OpenSkyRendering
import OpenSkyScripting
import OpenSkyWorld
import OpenSkyWorldState
import simd

/// What `ActorGraphWorldAdapter` reads from the session. `GameViewController` conforms.
@MainActor
protocol ActorGraphWorldHost: AnyObject {
    func actorPlayback(for key: ReferenceKey) -> ActorAnimationPlayback?
    var actorGraphs: ActorGraphCoordinator { get }
    var actorWorld: ActorWorldAdapter { get }
    var audioFileSystem: (any GameFileSource)? { get }
    var dragonFlight: DragonFlightCoordinator { get }
    var gameSession: GameSession? { get }
    var objectAnimationWorld: ObjectAnimationWorldAdapter { get }
    var playerSettingsStore: PlayerSettingsStore { get }
    var scripts: ScriptCoordinator { get }
    var streamer: CellStreamer? { get }
    var vehicleWorld: VehicleWorldAdapter { get }
    var worldData: WorldDataStores? { get }
    var worldState: WorldStateStore { get }
}

final class ActorGraphWorldAdapter {
    unowned let game: any ActorGraphWorldHost
    var graphs: ActorGraphCoordinator {
        game.actorGraphs
    }

    /// Each mover's drive gait, which picks its footstep list.
    private var gaits: [ReferenceKey: LocomotionGait] = [:]
    /// Each mover's ground material, which picks its footstep sound.
    private var groundMaterials: [ReferenceKey: FormID] = [:]
    /// Each rolled actor base's race graph project and weight.
    private var graphBases: [LeveledActorRollKey: GraphBase] = [:]

    /// `path` is nil when the race names no graph.
    private struct GraphBase {
        let path: String?
        let weight: Float
    }

    private static let settings: Set<PlayerSettingID> = [
        .actorGraphs, .actorGraphFullRateDistance, .actorGraphDistance
    ]

    init(game: any ActorGraphWorldHost) {
        self.game = game
    }

    /// After the idles, so an idle event raised this frame reaches the graph's step.
    func wire(gameSession: GameSession) {
        guard game.audioFileSystem != nil else { return }
        let store = game.playerSettingsStore
        graphs.load(settings: store)
        // The launcher page writes the same settings while a session runs.
        store.observe { [weak self, weak store] id in
            guard let store, Self.settings.contains(id) else { return }
            self?.graphs.load(settings: store)
        }
        gameSession.worldTick.register(.actorGraphs) { [weak self] delta in
            self?.graphs.tick(deltaTime: delta)
        }
    }

    /// One NPC mover's drive, as its graph's locomotion inputs.
    func drive(_ update: NPCLocomotionDriveUpdate) {
        let moving = update.intent != .still
        gaits[update.actor] = update.gait
        groundMaterials[update.actor] = update.groundMaterial
        graphs.setMotion(
            ActorGraphMotion(
                isMoving: moving,
                isSprinting: moving && update.gait == .sprint,
                isSneaking: update.gait == .sneak
            ),
            for: update.actor
        )
    }

    /// Every running graph's variables, the player's included.
    func graphVariableResolution() -> GraphVariableResolution {
        graphs.variableResolution(player: game.gameSession?.locomotion.graph?.variables)
    }

    func actorGraphFired(_ name: String, from actor: ReferenceKey) {
        game.gameSession?.animationEvents?.handle(name, from: actor)
        game.dragonFlight.handle(name, from: actor)
        game.scripts.runtime?.queueAnimationEvent(sender: actor, name: name)
        guard
            let feet = game.actorWorld.combatActor(key: actor)?.feet,
            let footsteps = game.gameSession?.footstepDirector
        else { return }
        footsteps.handleActorGraphEvents(
            [name], gait: gaits[actor] ?? .walk, position: feet,
            armatures: game.actorPlayback(for: actor)?.armorAddons.footstepArmatures ?? [],
            material: groundMaterials[actor]
        )
    }

    private func graphBase(of actor: ReferenceKey, base: FormID) -> GraphBase? {
        guard let resolver = game.worldData?.actorValueBaselines?.resolver else { return nil }
        let roll = game.worldState.leveledRoll(
            of: actor, base: base, with: resolver.templates.leveling
        )
        let key = LeveledActorRollKey(base: base, roll: roll)
        if let cached = graphBases[key] {
            return cached
        }
        let identity = ActorIdentityRecords(resolver: resolver)
        let race = identity.race(ofBase: base, roll: roll).flatMap { identity.races[$0.rawValue] }
        let graphs = race?.details.behaviorGraphs
        let female = identity.isFemale(ofBase: base, roll: roll) ?? false
        let model = (female ? graphs?.female : nil) ?? graphs?.male
        let path = model.map { ActorGraphCore.projectPath(modelPath: $0.path) }
        let weight = (try? resolver.templates.rolling(roll).resolve(base: base).weight) ?? 50
        let graphBase = GraphBase(path: path, weight: weight)
        graphBases[key] = graphBase
        return graphBase
    }
}

extension ActorGraphWorldAdapter: ActorGraphWorld {
    func animationWaitFinished(token: UInt64, fired: Bool) {
        game.objectAnimationWorld.answerWait(token: token, fired: fired)
    }

    func actorGraphCandidates() -> [ActorGraphCandidate] {
        guard let streamer = game.streamer else { return [] }
        // A rider plays the rider clips of its mount's gait instead.
        let links = game.vehicleWorld.vehicles.core.links
        return game.actorWorld.combatActors().compactMap { actor in
            guard
                !actor.isDead, links[actor.key] == nil,
                let base = streamer.residentActorEntry(key: actor.key)?.placedActor?.base,
                let graphBase = graphBase(of: actor.key, base: base),
                let path = graphBase.path
            else { return nil }
            return ActorGraphCandidate(
                key: actor.key, projectPath: path, feet: actor.feet, rotationZ: actor.facing,
                weight: graphBase.weight
            )
        }
    }

    var actorGraphViewer: SIMD3<Float>? {
        game.gameSession?.freeFlyCamera.position
    }

    func actorPlayback(for actor: ReferenceKey) -> ActorAnimationPlayback? {
        game.actorPlayback(for: actor)
    }
}
