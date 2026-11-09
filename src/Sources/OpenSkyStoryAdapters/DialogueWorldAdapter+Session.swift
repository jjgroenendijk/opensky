// `DialogueWorldAdapter` built over the started session: it registers its frame steps and
// session events as it is built (docs/decisions/session-scope.md).

import OpenSkyActorPresentation
import OpenSkyActorsInterface
import OpenSkyAIPackages
import OpenSkyCells
import OpenSkyCombatInterface
import OpenSkyConditions
import OpenSkyDialogue
import OpenSkyDialogueInterface
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventoryInterface
import OpenSkyPhysics
import OpenSkyPlayer
import OpenSkyProgressionInterface
import OpenSkyQuestsInterface
import OpenSkyRenderCore
import OpenSkyRendering
import OpenSkyRuntimeState
import OpenSkyScriptingInterface
import OpenSkySessionInterface
public import OpenSkyWorld
import OpenSkyWorldConditions
public import OpenSkyWorldInterface
import OpenSkyWorldState
import simd

extension DialogueWorldAdapter {
    /// Without a stage, as in a test, it registers nothing.
    public convenience init(
        game: some DialogueWorldHost & DialogueCameraFocusHost & DialogueSpeakersHost &
            DialogueOutcomesHost,
        stage: SessionStage?
    ) {
        self.init(game: game)
        guard let stage else { return }
        registerDialogue(stage: stage)
        registerDialogueCamera(stage: stage)
    }

    private func registerDialogue(stage: SessionStage) {
        let streamer = stage.streamer
        streamer.talk.candidateSource = { [weak self] ray in
            self?.speakers.talkCandidates(along: ray) ?? []
        }
        streamer.talk.activations.register(.dialogue) { [weak self] event in
            self?.handleTalkActivation(event)
        }
    }

    /// Activating a living actor while sneaking opens its pockets instead of a talk.
    public func handleTalkActivation(_ event: TalkActivationEvent) {
        if game.mountWorld.mountOnActivation(event.speaker) {
            return
        }
        if game.player.isSneaking, game.containerMenu.openPickpocket(of: event.speaker) {
            return
        }
        game.dialogueMenu.begin(with: event.speaker)
    }

    /// Runs after the actor systems in the world tick, so the camera reads
    /// this frame's pose.
    private func registerDialogueCamera(stage: SessionStage) {
        let gameSession = stage.gameSession
        gameSession.worldTick.register(.dialogueCamera) { [weak game = cameraFocus.game] delta in
            game?.dialogueCamera.refreshFocus()
            game?.faceMorphs.tick(now: game?.renderer?.animationTime ?? 0)
            game?.headTracking.tick(deltaTime: delta)
        }
        gameSession.renderer.worldOverlaySources
            .register(identifier: "dialogue-camera") { [weak gameSession] context, list in
                gameSession?.appendDialogueCameraOverlay(context: context, to: &list)
            }
    }
}
