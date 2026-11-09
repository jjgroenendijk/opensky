// `StoryWorldAdapter` built over the started session: it registers its frame steps and
// session events as it is built (docs/decisions/session-scope.md).

import Foundation
import OpenSkyActorPresentation
import OpenSkyActorsInterface
import OpenSkyAIPackages
import OpenSkyCells
import OpenSkyConditions
import OpenSkyCrime
import OpenSkyDialogue
import OpenSkyDialogueInterface
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyMenusInterface
import OpenSkyQuests
import OpenSkyQuestsInterface
import OpenSkyRendering
import OpenSkyRuntimeState
public import OpenSkyScriptingInterface
import OpenSkySessionInterface
public import OpenSkyWorld
import OpenSkyWorldConditions
import OpenSkyWorldInterface
import OpenSkyWorldState

extension StoryWorldAdapter {
    /// Without a stage, as in a test, it registers nothing.
    public convenience init(
        game: some StoryWorldHost & StoryAmbientTalkHost & StorySocialSearchHost &
            StorySceneLinesHost & StorySceneCastHost,
        stage: SessionStage?
    ) {
        self.init(game: game)
        guard let stage else { return }
        registerStory(stage: stage)
    }

    private func registerStory(stage: SessionStage) {
        let provider = stage.data
        let gameSession = stage.gameSession
        // The quest store's space, so a DLC scene names its quest as the runtime does.
        let questStore = provider.questStore
        if
            let dialogue = provider.dialogueStore,
            let files = game.audioFileSystem
        {
            let locator = VoiceLineLocator(dialogue: dialogue, quests: questStore)
            state.voiceLocator = locator
            state.voiceTimer = SceneVoiceTimer(
                locator: locator, read: { try files.contents(forPath: $0) }
            )
        }
        if let files = provider.scriptFileSystem {
            sessionStartLists = provider.storyData.plugins.map {
                PluginQuestList.load(plugin: $0.name, masters: $0.masters, files: files)
            }
        }
        gameSession.worldTick.register(.story) { [weak self] _ in
            self?.state.voiceTimer?.drain()
            self?.ambientTalk.tickAmbientSpeech()
            self?.sceneLines.run(self?.scenes.tick() ?? [])
            self?.socialSearch.run(self?.storyManager.social.tick() ?? [])
            self?.checkPlayerLocation()
        }
    }

    /// The story half of the Papyrus bridge's natives; the scope fills them as it builds
    /// the bridge.
    public func fillStoryNatives(
        _ story: inout PapyrusStoryNatives, _ session: inout PapyrusSessionNatives
    ) {
        story.questStarted = { [weak self] quest in
            self?.scenes.questDidStart(quest)
        }
        story.questFailed = { [weak self] quest in
            self?.questFailed(quest)
        }
        story.favorStateChanged = { [weak game = self.game] actor, isSet in
            game?.followerCommandWorld.favorStateChanged(actor, isDoingFavor: isSet)
        }
        session.conditionEvaluator = { [weak self] in
            ConditionEvaluator(
                context: self?.conditionContext() ?? ConditionContext(functions: .standard)
            )
        }
    }

    /// Runs each plugin's start-game-enabled quests, once the session has started.
    public func runSessionStartLists() {
        guard !sessionStartLists.isEmpty else { return }
        runSessionStart(lists: sessionStartLists)
    }
}
