// App side of the idle runtime and the head assembly switch. It answers their
// ports from the session systems and runs the idle pass in the frame loop.
// See docs/engine/coordinators.md.

import OpenSkyActorPresentation
import OpenSkyAIPackages
import OpenSkyCells
import OpenSkyCombat
import OpenSkyConditions
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyNavigation
import OpenSkyPlayer
import OpenSkyRendering
import OpenSkyRuntimeState
import OpenSkyWorld
import OpenSkyWorldState
import simd

/// What `IdleWorldAdapter` reads from the session. `GameViewController` conforms.
@MainActor
protocol IdleWorldHost: AnyObject {
    func actorPlayback(for key: ReferenceKey) -> ActorAnimationPlayback?
    var actorGraphWorld: ActorGraphWorldAdapter { get }
    var actorWorld: ActorWorldAdapter { get }
    var aiWorld: AIWorldAdapter { get }
    var audioFileSystem: (any GameFileSource)? { get }
    var packages: PackageCoordinator { get }
    var player: PlayerCoordinator { get }
    var renderer: Renderer? { get }
    var gameSession: GameSession? { get }
    var idles: IdleCoordinator { get }
    var runtimeStateWorld: RuntimeStateWorldAdapter { get }
    var sessionWiring: WorldSessionWiring { get }
    var streamer: CellStreamer? { get }
    var vehicleWorld: VehicleWorldAdapter { get }
    var worldData: WorldDataStores? { get }
    var worldState: WorldStateStore { get }
}

final class IdleWorldAdapter {
    unowned let game: any IdleWorldHost
    var idles: IdleCoordinator {
        game.idles
    }

    init(game: any IdleWorldHost) {
        self.game = game
    }

    /// The clip loader is built first.
    func sessionData() -> IdleSessionData? {
        guard
            let store = game.worldData?.idleStore,
            let files = game.audioFileSystem,
            let clips = game.sessionWiring.animationClips
        else { return nil }
        return IdleSessionData(store: store, files: files, clips: clips)
    }

    /// After packages, because the pass reads each actor's current procedure.
    func wireIdles(gameSession: GameSession) {
        let idles = idles
        guard idles.store != nil else { return }
        gameSession.worldTick.register(.idles) { [weak idles] _ in
            idles?.advance()
        }
    }
}

extension IdleWorldAdapter: IdleWorld {
    func idleAnimationEvent(_ name: String, on actor: ReferenceKey) {
        game.vehicleWorld.handleIdleAnimationEvent(name, from: actor)
    }

    func idleReferencePlacements() -> [IdleReferencePlacement]? {
        guard game.renderer != nil, let streamer = game.streamer else { return nil }
        let scenes = streamer.interiorScene.map { [$0] }
            ?? streamer.composition.cells.values
            .sorted { $0.summary.cellName < $1.summary.cellName }
        return scenes.flatMap { scene in
            scene.references.sortedEntries().compactMap { entry in
                entry.placedReference.map {
                    IdleReferencePlacement(
                        reference: entry.key,
                        base: $0.base,
                        plugin: scene.ownerPluginName ?? "Skyrim.esm",
                        position: $0.placement.position
                    )
                }
            }
        }
    }

    func idleActors() -> [IdleActorPresence] {
        let packages = Dictionary(
            game.packages.readouts().compactMap { readout in
                readout.procedure.map { (readout.actor, $0) }
            },
            uniquingKeysWith: { first, _ in first }
        )
        let actors = game.actorWorld.combatActors().map {
            var presence = IdleActorPresence(
                key: $0.key, feet: $0.feet, procedure: packages[$0.key], isDead: $0.isDead
            )
            presence.area = game.packages.sandboxArea(of: $0.key)
            return presence
        }
        // The player has no package, so it takes no marker; a script idle still plays.
        let player = game.gameSession.map {
            IdleActorPresence(
                key: .player, feet: $0.walkController.feetPosition, procedure: nil, isDead: false
            )
        }
        return actors + (player.map { [$0] } ?? [])
    }

    func idleConditionContext() -> ConditionContext {
        guard let clock = game.gameSession?.gameClock else { return ConditionContext() }
        var context = game.aiWorld.packageConditionContext(clock: clock)
        // Idle trees test keywords, such as the chopping block's `isExecutioner`.
        context.data = game.runtimeStateWorld.conditionData()
        return context
    }

    var idleStateSequence: UInt64 {
        game.worldState.nextJournalSequence
    }

    func actorPlayback(for actor: ReferenceKey) -> ActorAnimationPlayback? {
        game.actorPlayback(for: actor)
    }

    var idleAnimationTime: Float? {
        game.renderer?.animationTime
    }

    func moveActor(_ actor: ReferenceKey, to point: SIMD3<Float>) -> NPCMoveCommandResult {
        game.aiWorld.moveActor(actor, to: point)
    }

    func setProp(_ prop: ActorPropAttachment?, on actor: ReferenceKey) {
        guard
            let streamer = game.streamer,
            let placed = streamer.referenceEntry(key: actor)?.placedActor
        else { return }
        streamer.setActorProp(prop, on: placed.formID)
    }

    func raiseIdleEvent(_ name: String, state: String?, on actor: ReferenceKey) -> Bool {
        guard actor == .player else {
            return game.actorGraphWorld.graphs.raise(name, on: actor)
        }
        game.player.playIdle(named: name, state: state)
        return true
    }
}
