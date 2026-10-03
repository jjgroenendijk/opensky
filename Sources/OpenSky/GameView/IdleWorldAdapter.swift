// App side of the idle runtime and the head assembly switch. It answers their
// ports from the session systems and runs the idle pass in the frame loop.
// See docs/engine/coordinators.md.

import OpenSkyCombat
import OpenSkyConditions
import OpenSkyFormatsESM
import OpenSkyRendering
import OpenSkyWorld
import OpenSkyWorldState
import simd

final class IdleWorldAdapter {
    unowned let game: GameViewController
    /// Ambient idles at idle markers, with their props.
    let idles = IdleCoordinator()
    /// The per-actor switch between the baked and the assembled head.
    let headAssembly = HeadAssemblyCoordinator()

    init(game: GameViewController) {
        self.game = game
        idles.attach(world: self)
        headAssembly.attach(world: self)
    }

    /// After packages, because the pass reads each actor's current procedure.
    func wireIdles(provider: any WorldDataProviding, renderer: Renderer) {
        guard
            let store = (provider as? IdleDataProviding)?.idleStore,
            let files = game.audioFileSystem
        else { return }
        idles.wire(store: store, files: files)
        let idles = idles
        let advanceWorld = renderer.onWorldUpdate
        renderer.onWorldUpdate = { [weak idles] delta in
            advanceWorld?(delta)
            idles?.advance()
        }
    }

    private func updatePresentationState(
        of actor: ReferenceKey,
        _ change: (inout ActorPresentationState) -> Void
    ) {
        game.worldState.updatePresentation(
            of: actor, in: game.streamer?.cellLocation(of: actor), change
        )
    }
}

extension IdleWorldAdapter: IdleWorld {
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
        return game.actorWorld.combatActors().map {
            IdleActorPresence(
                key: $0.key, feet: $0.feet, procedure: packages[$0.key], isDead: $0.isDead
            )
        }
    }

    func idleConditionContext() -> ConditionContext {
        guard let clock = game.renderer?.gameClock else { return ConditionContext() }
        return game.aiWorld.packageConditionContext(clock: clock)
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

    func updatePresentation(
        of actor: ReferenceKey,
        _ change: (inout ActorPresentationState) -> Void
    ) {
        updatePresentationState(of: actor, change)
    }
}

extension IdleWorldAdapter: HeadAssemblyWorld {
    func actorHead(for actor: ReferenceKey) -> ActorHeadReadout? {
        guard
            let streamer = game.streamer,
            let placed = streamer.referenceEntry(key: actor)?.placedActor
        else { return nil }
        return streamer.actorHead(forActor: placed.formID)
    }

    func presentation(of actor: ReferenceKey) -> ActorPresentationState? {
        game.worldState.component(ActorPresentationState.self, for: actor)
    }
}
