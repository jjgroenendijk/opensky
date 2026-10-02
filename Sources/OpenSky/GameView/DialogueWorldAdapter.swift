// App side of `DialogueCoordinator`: wires the dialogue index and the Talk
// seams onto the streamer, and answers `DialogueWorld` from the session
// systems. The rules live in the coordinator (docs/engine/coordinators.md).

import OpenSkyActorsInterface
import OpenSkyCombat
import OpenSkyConditions
import OpenSkyDiagnostics
import OpenSkyDialogue
import OpenSkyDialogueInterface
import OpenSkyFactions
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyPhysics
import OpenSkyQuestsInterface
import OpenSkyRendering
import OpenSkyScripting
import OpenSkyWorld
import OpenSkyWorldInterface
import OpenSkyWorldState
import simd

/// Answers `DialogueWorld` from the session systems `game` owns.
final class DialogueWorldAdapter {
    unowned let game: GameViewController

    init(game: GameViewController) {
        self.game = game
    }

    /// Hostility and death decide who is worth talking to, so the candidate
    /// list is built here, not in streaming.
    func wireDialogue(provider: any WorldDataProviding, streamer: CellStreamer) {
        game.dialogue.index = (provider as? DialogueDataProviding)?.dialogueStore
        streamer.talk.candidateSource = { [weak self] in
            self?.talkCandidates() ?? []
        }
        streamer.talk.activations.add { [weak self] event in
            self?.game.dialogueMenu.begin(with: event.speaker)
        }
    }

    /// Runs after the other `onWorldUpdate` systems, so the camera reads this
    /// frame's pose.
    func wireDialogueCamera(renderer: Renderer) {
        let advancePreviousSystems = renderer.onWorldUpdate
        renderer.onWorldUpdate = { [weak self] delta in
            advancePreviousSystems?(delta)
            self?.game.dialogueCamera.refreshFocus()
        }
        renderer.worldOverlaySources
            .register(identifier: "dialogue-camera") { [weak renderer] context, list in
                renderer?.appendDialogueCameraOverlay(context: context, to: &list)
            }
    }

    /// Dead and hostile actors are left out. An actor with no passing topic
    /// still opens an empty menu, so the condition trace can explain why.
    func talkCandidates() -> [TalkCandidate] {
        guard let streamer = game.streamer else { return [] }
        return game.actorWorld.combatActors().compactMap { observation in
            guard
                !observation.isDead,
                game.factions.hostility(of: observation.key) != .hostile,
                let entry = streamer.referenceEntry(key: observation.key),
                let actor = entry.placedActor
            else {
                return nil
            }
            return TalkCandidate(
                key: observation.key,
                reference: entry.formID,
                base: actor.base,
                feet: observation.feet,
                name: speakerName(entry: entry, fallback: observation.name)
            )
        }
    }

    private func speakerName(entry: RuntimeReferenceEntry, fallback: String) -> String {
        if let name = game.streamer?.interactionName(reference: entry.formID), !name.isEmpty {
            return name
        }
        return fallback.isEmpty ? entry.key.description : fallback
    }

    /// The same resolved name the crosshair prompt uses, so the prompt and the
    /// menu header agree.
    func speakerLabel(for speaker: ReferenceKey) -> String {
        guard let entry = game.streamer?.referenceEntry(key: speaker) else {
            return speaker.description
        }
        let name = game.streamer?.interactionName(reference: entry.formID)
        return name?.isEmpty == false ? (name ?? "") : speaker.description
    }

    /// The posed `NPC Head [Head]` bone, or the capsule eye height when the
    /// actor has no rig.
    func headPosition(of actor: ReferenceKey) -> SIMD3<Float>? {
        guard
            let streamer = game.streamer,
            let entry = streamer.referenceEntry(key: actor),
            let placed = entry.placedActor
        else { return nil }
        let override = streamer.npcTransform(for: actor)
        let feet = override?.position ?? placed.placement.position
        guard
            let pose = game.animatedPose(for: actor),
            let head = pose[DialogueCamera.headBoneName]
        else {
            return feet + SIMD3<Float>(0, 0, PlayerCapsule.standard.eyeHeight)
        }
        let actorToWorld = MatrixMath.placement(
            position: feet,
            rotation: override?.rotation ?? placed.placement.rotation,
            scale: override?.scale ?? placed.scale
        )
        let world = actorToWorld * head
        return SIMD3(world.columns.3.x, world.columns.3.y, world.columns.3.z)
    }
}

extension DialogueWorldAdapter: DialogueWorld {
    func questStates() -> QuestResolution? {
        game.scripts.bridge?.questRuntime?.resolution()
    }

    func conditionContext() -> ConditionContext {
        game.runtimeState.conditionContext()
    }

    var conditionRegistry: ConditionFunctionRegistry {
        .standard
    }

    var fragments: (any DialogueFragmentDispatching)? {
        game.scripts.bridge
    }

    func loadStrings() -> LocalizedStrings? {
        game.localizedStringsLoader?()
    }

    func suspendPackage(for actor: ReferenceKey) {
        game.packages.suspend(actor)
    }

    func resumePackage(for actor: ReferenceKey) {
        game.packages.resume(actor)
    }

    func stopActor(_ actor: ReferenceKey) {
        game.streamer?.stopActor(actor)
    }

    func faceActor(_ actor: ReferenceKey, towards point: SIMD3<Float>) {
        game.streamer?.faceActor(actor, towards: point)
    }

    func releaseFacing(of actor: ReferenceKey) {
        game.streamer?.releaseActorFacing(actor)
    }
}
