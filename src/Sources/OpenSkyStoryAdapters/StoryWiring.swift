// `StoryWorldAdapter` joins the started session: what `wireStory` registered.

import Foundation
import OpenSkyActorPresentation
import OpenSkyActorsInterface
import OpenSkyAIPackages
public import OpenSkyCells
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
import OpenSkyScriptingInterface
import OpenSkySessionInterface
public import OpenSkyWorld
import OpenSkyWorldConditions
import OpenSkyWorldInterface
import OpenSkyWorldState

/// After `wireDialogue`, because scenes speak through the dialogue index.
public struct StoryWiring {
    public init(_ adapter: StoryWorldAdapter, provider: WorldDataStores, gameSession: GameSession) {
        let data = provider.storyData
        // The quest store's space, so a DLC scene names its quest as the runtime does.
        let questStore = provider.questStore
        if
            let dialogue = provider.dialogueStore,
            let files = adapter.game.audioFileSystem
        {
            let locator = VoiceLineLocator(dialogue: dialogue, quests: questStore)
            adapter.state.voiceLocator = locator
            adapter.state.voiceTimer = SceneVoiceTimer(
                locator: locator, read: { try files.contents(forPath: $0) }
            )
        }
        adapter.game.scripts.bridge?.storyNatives.questStarted = { [weak adapter] quest in
            adapter?.scenes.questDidStart(quest)
        }
        adapter.game.scripts.bridge?.storyNatives.questFailed = { [weak adapter] quest in
            adapter?.questFailed(quest)
        }
        let commands = adapter.game.followerCommandWorld
        adapter.game.scripts.bridge?.storyNatives
            .favorStateChanged = { [weak commands] actor, isSet in
                commands?.favorStateChanged(actor, isDoingFavor: isSet)
            }
        adapter.game.scripts.bridge?.sessionNatives.conditionEvaluator = { [weak adapter] in
            ConditionEvaluator(
                context: adapter?.conditionContext() ?? ConditionContext(), registry: .standard
            )
        }
        if let files = provider.scriptFileSystem {
            adapter.sessionStartLists = data.plugins.map {
                PluginQuestList.load(plugin: $0.name, masters: $0.masters, files: files)
            }
            adapter.runSessionStart(lists: adapter.sessionStartLists)
        }
        gameSession.worldTick.register(.story) { [weak adapter] _ in
            adapter?.state.voiceTimer?.drain()
            adapter?.ambientTalk.tickAmbientSpeech()
            adapter?.sceneLines.run(adapter?.scenes.tick() ?? [])
            adapter?.socialSearch.run(adapter?.storyManager.social.tick() ?? [])
            adapter?.checkPlayerLocation()
        }
    }
}
