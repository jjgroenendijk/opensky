// The quest notices the HUD shows each frame the quest state changed, the object
// animation coordinators that share the "Animated objects" switch, and the
// adapters and coordinators that get session parts as closures.

import OpenSkyActorPresentation
import OpenSkyAIPackages
import OpenSkyEffects
import OpenSkyFormatsMesh
import OpenSkyMenus
import OpenSkyObjectAnimation
import OpenSkyPlayer
import OpenSkyQuests
import OpenSkyQuestsInterface
import OpenSkyWorld
import OpenSkyWorldState

extension GameSessionScope {
    func updateQuestNotices() {
        guard let runtime = journal.runtime else { return }
        questNotices.update(
            runtime: runtime, quests: runtime.runtimeQuests(),
            revision: runtime.store.revision(of: [.quest]),
            strings: journal.strings, aliases: journalMenu.aliasNaming(runtime: runtime)
        )
    }

    func makeSequenceDoors() -> SequenceDoorCoordinator {
        let doors = SequenceDoorCoordinator(
            world: objectAnimationWorld, viewer: { [unowned self] in billboardViewer }
        )
        doors.isEnabled = objectBehaviors.isEnabled
        return doors
    }

    /// The camera that world billboards and effect billboards turn to.
    var billboardViewer: NIFBillboard.Viewer? {
        gameSession.map { NIFBillboard.Viewer(camera: $0.freeFlyCamera) }
    }

    func makeNodeControllers() -> NodeControllerCoordinator {
        let nodes = NodeControllerCoordinator(world: objectAnimationWorld)
        nodes.isEnabled = objectBehaviors.isEnabled
        return nodes
    }

    func makeScriptWorld() -> ScriptWorldAdapter {
        let adapter = ScriptWorldAdapter(game: ports)
        adapter.weather = { [unowned self] in gameSession?.weather }
        return adapter
    }

    func makePlayerWorld() -> PlayerWorldAdapter {
        let adapter = PlayerWorldAdapter(game: ports)
        adapter.locomotion = { [unowned self] in gameSession?.locomotion }
        adapter.firstPersonRig = { [unowned self] in gameSession?.playerFirstPersonRig }
        adapter.playerFace = { [unowned self] in gameSession?.playerBody?.face }
        return adapter
    }

    func makeNPCAnimation() -> NPCAnimationCoordinator {
        let coordinator = NPCAnimationCoordinator(world: aiWorld)
        coordinator.actorPlayback = { [unowned self] in actorPlayback(for: $0) }
        return coordinator
    }

    func makeIdles() -> IdleCoordinator {
        let coordinator = IdleCoordinator(world: idleWorld, data: idleWorld.sessionData())
        coordinator.actorPlayback = { [unowned self] in actorPlayback(for: $0) }
        return coordinator
    }

    func makeObjectAnimationWorld() -> ObjectAnimationWorldAdapter {
        let adapter = ObjectAnimationWorldAdapter(game: ports)
        adapter.animatedObjects = { [unowned self] in streamer?.residentAnimatedObjects() ?? [] }
        adapter.sequenceDoors = { [unowned self] in streamer?.residentSequenceDoors() ?? [] }
        adapter.nodeAnimations = { [unowned self] in streamer?.residentNodeAnimations() ?? [] }
        return adapter
    }

    func makeEffectModelPoser() -> EffectModelPoser {
        let poser = EffectModelPoser(
            files: { [unowned self] in audioFileSystem },
            meshes: { [unowned self] in effects.meshes },
            graphs: effectGraphs,
            viewer: { [unowned self] in billboardViewer }
        )
        poser.isEnabled = objectBehaviors.isEnabled
        return poser
    }

    func makeActorGraphs() -> ActorGraphCoordinator {
        let coordinator = ActorGraphCoordinator(
            world: actorGraphWorld, files: { [unowned self] in audioFileSystem }
        )
        coordinator.actorPlayback = { [unowned self] in actorPlayback(for: $0) }
        return coordinator
    }
}
