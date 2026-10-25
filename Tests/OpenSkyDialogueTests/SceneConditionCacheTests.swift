// The scene condition seam is kept across reads: it follows every scene-state
// write, and an alias filled again without one.

import OpenSkyDialogue
import OpenSkyDialogueFixtures
import OpenSkyDialogueInterface
import OpenSkyFeaturesTesting
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyQuestsInterface
import OpenSkyWorldState
import Testing

@MainActor
struct SceneConditionCacheTests {
    private let speaker = DialogueRuntimeFixture.speakerKey

    private func aliases(filled: Bool) throws -> QuestAliasResolution {
        let quests = try DialogueRuntimeFixture.questStore()
        let questKey = try #require(quests.key(for: FormID(DialogueRuntimeFixture.runningQuest)))
        let fills = filled ? [QuestAliasFill(aliasID: 0, reference: speaker)] : []
        return QuestAliasResolution(
            defaults: quests, tables: [questKey: QuestAliasState(fills: fills)]
        )
    }

    @Test func theSeamFollowsSceneWritesAndAliasFills() throws {
        let store = WorldStateStore()
        let world = try FakeDialogueWorld(
            quests: QuestResolution(defaults: DialogueRuntimeFixture.questStore()),
            context: DialogueRuntimeFixture.context()
        )
        let dialogue = DialogueCoordinator(store: store, world: world, index: nil)
        let scene = try SceneFixture.scene()
        let coordinator = SceneCoordinator(
            dialogue: dialogue, world: FakeSceneHost(), catalog: SceneCatalog(scenes: [scene])
        )
        let filled = try aliases(filled: true)

        #expect(!coordinator.conditionResolution(aliases: filled).isPlaying(scene.formID))

        store.set(SceneRuntimeState(phase: 1, completed: [0]), for: scene.key)
        let playing = coordinator.conditionResolution(aliases: filled)
        #expect(playing.isPlaying(scene.formID))
        #expect(playing.isInScene(speaker))
        #expect(try !coordinator.conditionResolution(aliases: aliases(filled: false))
            .isInScene(speaker))

        store.reset(.scene, for: scene.key)
        #expect(!coordinator.conditionResolution(aliases: filled).isPlaying(scene.formID))

        let empty = SceneCoordinator(
            dialogue: dialogue, world: FakeSceneHost(), catalog: SceneCatalog(scenes: [])
        )
        store.set(SceneRuntimeState(phase: 1), for: scene.key)
        #expect(!empty.conditionResolution(aliases: filled).isPlaying(scene.formID))
    }
}
