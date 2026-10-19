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
    var actorWorld: ActorWorldAdapter { get }
    var audioFileSystem: (any GameFileSource)? { get }
    var gameSession: GameSession? { get }
    var playerSettingsStore: PlayerSettingsStore { get }
    var scripts: ScriptCoordinator { get }
    var streamer: CellStreamer? { get }
    var vehicleWorld: VehicleWorldAdapter { get }
    var worldData: WorldDataStores? { get }
}

final class ActorGraphWorldAdapter {
    unowned let game: any ActorGraphWorldHost
    private(set) lazy var graphs = ActorGraphCoordinator(
        world: self, files: { [unowned game] in game.audioFileSystem }
    )
    /// Each mover's drive gait, which picks its footstep list.
    private var gaits: [ReferenceKey: LocomotionGait] = [:]
    /// Each actor base's race graph project; nil when its race names none.
    private var projectPaths: [FormID: String?] = [:]

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
        graphs.onAnimationEvent = { [weak self] actor, name in
            self?.forward(name, from: actor)
        }
        gameSession.worldTick.register(.actorGraphs) { [weak self] delta in
            self?.graphs.tick(deltaTime: delta)
        }
    }

    /// One NPC mover's drive, as its graph's locomotion inputs.
    func drive(_ update: NPCLocomotionDriveUpdate) {
        let moving = update.intent != .still
        gaits[update.actor] = update.gait
        graphs.setMotion(
            ActorGraphMotion(
                isMoving: moving,
                isRunning: moving && update.gait == .run,
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

    private func forward(_ name: String, from actor: ReferenceKey) {
        game.gameSession?.animationEvents?.handle(name, from: actor)
        game.scripts.runtime?.queueAnimationEvent(sender: actor, name: name)
        guard
            let feet = game.actorWorld.combatActor(key: actor)?.feet,
            let footsteps = game.gameSession?.footstepDirector
        else { return }
        footsteps.handleActorGraphEvents([name], gait: gaits[actor] ?? .walk, position: feet)
    }

    private func projectPath(ofBase base: FormID) -> String? {
        if let cached = projectPaths[base] {
            return cached
        }
        guard let resolver = game.worldData?.actorValueBaselines?.resolver else { return nil }
        let identity = ActorIdentityRecords(resolver: resolver)
        let race = identity.race(ofBase: base).flatMap { identity.races[$0.rawValue] }
        let graphs = race?.details.behaviorGraphs
        let female = identity.isFemale(ofBase: base) ?? false
        let model = (female ? graphs?.female : nil) ?? graphs?.male
        let path = model.map { ActorGraphCore.projectPath(modelPath: $0.path) }
        projectPaths[base] = .some(path)
        return path
    }
}

extension ActorGraphWorldAdapter: ActorGraphWorld {
    func actorGraphCandidates() -> [ActorGraphCandidate] {
        guard let streamer = game.streamer else { return [] }
        // A rider plays the rider clips of its mount's gait instead.
        let links = game.vehicleWorld.vehicles.core.links
        return game.actorWorld.combatActors().compactMap { actor in
            guard
                !actor.isDead, links[actor.key] == nil,
                let base = streamer.residentActorEntry(key: actor.key)?.placedActor?.base,
                let path = projectPath(ofBase: base)
            else { return nil }
            return ActorGraphCandidate(
                key: actor.key, projectPath: path, feet: actor.feet, rotationZ: actor.facing
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

/// The Behaviour Graphs section reads the adapter.
extension ActorGraphWorldAdapter: ActorGraphControlProviding {
    func actorGraphSnapshot(for actor: ReferenceKey?) -> ActorGraphControlSnapshot {
        graphs.snapshot(for: actor)
    }

    func setActorGraphsEnabled(_ enabled: Bool) {
        graphs.isEnabled = enabled
        game.playerSettingsStore.set(.actorGraphs, to: enabled ? 1 : 0)
    }

    func setActorGraphCutoff(_ cutoff: ActorGraphCutoff) {
        graphs.cutoff = cutoff
        game.playerSettingsStore.set(
            .actorGraphFullRateDistance, to: Double(cutoff.fullRateDistance)
        )
        game.playerSettingsStore.set(.actorGraphDistance, to: Double(cutoff.maximumDistance))
    }

    func sendActorGraphEvent(_ event: String, to actor: ReferenceKey) -> Bool {
        graphs.raise(event, on: actor)
    }
}
